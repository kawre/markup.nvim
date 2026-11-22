//! Fuzzy matching for pickers, with nucleo, the matcher of the Helix editor.
//!
//! The candidates are handed over once. A search over a few thousand of them
//! takes well under a millisecond, so it runs at once; a larger one runs on a
//! thread of its own, and Lua polls for what it found, so typing never waits.
//! A newer search makes an older one stop where it is.
//!
//! A query that only adds to the last one searches what that one found: nothing
//! the last one left out can match more. What it finds is sorted the same as a
//! search of everything, by score and then by where the candidate is.

use mlua::prelude::*;
use nucleo_matcher::pattern::{CaseMatching, Normalization, Pattern};
use nucleo_matcher::{Config, Matcher, Utf32String};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;

/// Candidates from which a search goes to a thread of its own.
const THREAD_AT: usize = 10_000;
/// Candidates between checks of whether a newer search started.
const CHECK_EVERY: usize = 2048;

/// What a search found: indexes into the candidates, from zero, best first.
type Found = Vec<u32>;

#[derive(Default)]
struct Slot {
    /// The search the result is for, and the result.
    done: Option<(u64, Found)>,
}

pub struct FuzzyMatcher {
    candidates: Arc<Vec<Utf32String>>,
    /// The search running now, which older ones compare against to stop.
    generation: Arc<AtomicU64>,
    slot: Arc<(Mutex<Slot>, Condvar)>,
    /// The last search that finished: its query, and what it found in the
    /// order of the candidates, for a query that only adds to it.
    last: Option<(String, Arc<Vec<u32>>)>,
    /// The query of the search running now, until it is polled.
    pending: Option<String>,
    matcher: Matcher,
}

/// Whether what `query` finds is within what `last` found: it only adds to it,
/// and neither has what can make a longer query match more, such as `!` for a
/// match left out or a `\` before a special character.
fn refines(last: &str, query: &str) -> bool {
    !last.is_empty()
        && query.starts_with(last)
        && !query.contains('!')
        && !query.contains('\\')
        && !last.ends_with('$')
}

/// Scores `pool`, or every candidate, against `query`, best first and, on a
/// tie, in the order of the candidates. None when a newer search started.
fn search(
    candidates: &[Utf32String],
    pool: Option<&[u32]>,
    query: &str,
    matcher: &mut Matcher,
    stop: impl Fn() -> bool,
) -> Option<Found> {
    let pattern = Pattern::parse(query, CaseMatching::Smart, Normalization::Smart);
    let mut scored: Vec<(u32, u32)> = Vec::new();
    let mut score_one = |index: u32| {
        let candidate = &candidates[index as usize];
        if let Some(score) = pattern.score(candidate.slice(..), matcher) {
            scored.push((score, index));
        }
    };
    match pool {
        Some(pool) => {
            for (n, &index) in pool.iter().enumerate() {
                if n % CHECK_EVERY == 0 && stop() {
                    return None;
                }
                score_one(index);
            }
        }
        None => {
            for index in 0..candidates.len() {
                if index % CHECK_EVERY == 0 && stop() {
                    return None;
                }
                score_one(index as u32);
            }
        }
    }
    scored.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
    Some(scored.into_iter().map(|(_, index)| index).collect())
}

impl FuzzyMatcher {
    pub fn new(candidates: Vec<String>) -> Self {
        let candidates = candidates
            .iter()
            .map(|text| Utf32String::from(text.as_str()))
            .collect();
        FuzzyMatcher {
            candidates: Arc::new(candidates),
            generation: Arc::new(AtomicU64::new(0)),
            slot: Arc::new((Mutex::new(Slot::default()), Condvar::new())),
            last: None,
            pending: None,
            matcher: Matcher::new(Config::DEFAULT),
        }
    }

    /// Starts a search for `query`. Returns whether it is done already, which
    /// a small one is: `poll` then has it.
    pub fn start(&mut self, query: &str) -> bool {
        let generation = self.generation.fetch_add(1, Ordering::SeqCst) + 1;
        self.pending = Some(query.to_string());

        let pool = self
            .last
            .as_ref()
            .filter(|(last, _)| refines(last, query))
            .map(|(_, found)| found.clone());
        let size = pool
            .as_ref()
            .map_or(self.candidates.len(), |pool| pool.len());

        if size < THREAD_AT {
            let found = search(
                &self.candidates,
                pool.as_deref().map(|pool| pool.as_slice()),
                query,
                &mut self.matcher,
                || false,
            )
            .unwrap_or_default();
            let (lock, _) = &*self.slot;
            lock.lock().unwrap().done = Some((generation, found));
            return true;
        }

        let candidates = self.candidates.clone();
        let current = self.generation.clone();
        let slot = self.slot.clone();
        let query = query.to_string();
        thread::spawn(move || {
            let mut matcher = Matcher::new(Config::DEFAULT);
            let stop = || current.load(Ordering::SeqCst) != generation;
            let found = search(
                &candidates,
                pool.as_deref().map(|pool| pool.as_slice()),
                &query,
                &mut matcher,
                stop,
            );
            if let Some(found) = found {
                let (lock, ready) = &*slot;
                let mut slot = lock.lock().unwrap();
                // A newer search may have finished first.
                if current.load(Ordering::SeqCst) == generation {
                    slot.done = Some((generation, found));
                    ready.notify_all();
                }
            }
        });
        false
    }

    /// What the newest search found, once it has.
    pub fn poll(&mut self) -> Option<Found> {
        let generation = self.generation.load(Ordering::SeqCst);
        let (lock, _) = &*self.slot;
        let mut slot = lock.lock().unwrap();
        match slot.done.take() {
            Some((done, found)) if done == generation => {
                drop(slot);
                self.finished(&found);
                Some(found)
            }
            // An older one: what the newer one finds comes later.
            Some(_) | None => None,
        }
    }

    /// Waits for the newest search, for when what it finds is needed now.
    pub fn wait(&mut self) -> Option<Found> {
        let generation = self.generation.load(Ordering::SeqCst);
        {
            let (lock, ready) = &*self.slot;
            let slot = lock.lock().unwrap();
            let _slot = ready
                .wait_while(
                    slot,
                    |slot| !matches!(slot.done, Some((done, _)) if done == generation),
                )
                .unwrap();
        }
        self.poll()
    }

    /// Remembers what a search found, in the order of the candidates, for a
    /// query that only adds to it.
    fn finished(&mut self, found: &Found) {
        if let Some(query) = self.pending.take() {
            let mut sorted = found.clone();
            sorted.sort_unstable();
            self.last = Some((query, Arc::new(sorted)));
        }
    }

    /// The characters of candidate `index` that `query` matched, from zero.
    pub fn positions(&mut self, index: usize, query: &str) -> Vec<u32> {
        let Some(candidate) = self.candidates.get(index) else {
            return Vec::new();
        };
        let pattern = Pattern::parse(query, CaseMatching::Smart, Normalization::Smart);
        let mut positions = Vec::new();
        pattern.indices(candidate.slice(..), &mut self.matcher, &mut positions);
        positions.sort_unstable();
        positions.dedup();
        positions
    }
}

impl LuaUserData for FuzzyMatcher {
    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        methods.add_method_mut("start", |_, this, query: String| Ok(this.start(&query)));
        // Indexes from one, as Lua counts.
        let to_lua = |lua: &Lua, found: Option<Found>| -> LuaResult<LuaValue> {
            match found {
                Some(found) => Ok(LuaValue::Table(
                    lua.create_sequence_from(found.into_iter().map(|index| index + 1))?,
                )),
                None => Ok(LuaValue::Nil),
            }
        };
        methods.add_method_mut("poll", move |lua, this, ()| to_lua(lua, this.poll()));
        methods.add_method_mut("wait", move |lua, this, ()| to_lua(lua, this.wait()));
        methods.add_method_mut("positions", |_, this, (index, query): (usize, String)| {
            Ok(this.positions(index.saturating_sub(1), &query))
        });
    }
}

/// `create_matcher(candidates)`, the strings to match, one per item.
pub fn create_matcher(_: &Lua, candidates: Vec<String>) -> LuaResult<FuzzyMatcher> {
    Ok(FuzzyMatcher::new(candidates))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn matcher(candidates: &[&str]) -> FuzzyMatcher {
        FuzzyMatcher::new(candidates.iter().map(|text| text.to_string()).collect())
    }

    fn find(matcher: &mut FuzzyMatcher, query: &str) -> Vec<u32> {
        if !matcher.start(query) {
            return matcher.wait().unwrap();
        }
        matcher.poll().unwrap()
    }

    #[test]
    fn finds_the_best_first_and_ties_in_order() {
        let mut m = matcher(&["add two numbers", "two sum", "three sum", "two sum ii"]);
        let found = find(&mut m, "two sum");
        assert_eq!(found[0], 1);
        assert!(!found.contains(&2));
        // The same score keeps the order of the candidates.
        let mut m = matcher(&["abc", "abc", "abc"]);
        assert_eq!(find(&mut m, "abc"), vec![0, 1, 2]);
    }

    #[test]
    fn a_longer_query_finds_what_a_search_of_everything_does() {
        let words = [
            "sum",
            "two",
            "tree",
            "sub",
            "array",
            "string",
            "subarray sum",
        ];
        let candidates: Vec<String> = (0..500)
            .map(|i| format!("{} {} {}", words[i % 7], words[(i * 3) % 7], i))
            .collect();
        let refs: Vec<&str> = candidates.iter().map(String::as_str).collect();
        let mut refined = matcher(&refs);
        for query in ["s", "su", "sub", "suba", "subar"] {
            let found = find(&mut refined, query);
            let mut fresh = matcher(&refs);
            assert_eq!(found, find(&mut fresh, query), "{query}");
        }
    }

    #[test]
    fn what_can_match_more_searches_everything() {
        assert!(refines("ab", "abc"));
        assert!(!refines("", "a"));
        assert!(!refines("ab", "a"));
        assert!(!refines("!ab", "!abc"));
        assert!(!refines("ab$", "ab$c"));
    }

    #[test]
    fn many_candidates_are_searched_on_a_thread_and_found_all_the_same() {
        let candidates: Vec<String> = (0..THREAD_AT * 2).map(|i| format!("item {i}")).collect();
        let refs: Vec<&str> = candidates.iter().map(String::as_str).collect();
        let mut m = matcher(&refs);
        assert!(!m.start("item 1999"));
        let found = m.wait().unwrap();
        assert_eq!(found[0], 1999);
        // Nothing is left to poll: it was taken.
        assert_eq!(m.poll(), None);
    }

    #[test]
    fn a_newer_search_wins() {
        let candidates: Vec<String> = (0..THREAD_AT * 4).map(|i| format!("item {i}")).collect();
        let refs: Vec<&str> = candidates.iter().map(String::as_str).collect();
        let mut m = matcher(&refs);
        m.start("item 1");
        m.start("item 22");
        let found = m.wait().unwrap();
        assert_eq!(candidates[found[0] as usize], "item 22");
    }

    #[test]
    fn lua_starts_polls_waits_and_asks_for_positions() {
        let lua = Lua::new();
        let create = lua.create_function(create_matcher).unwrap();
        lua.globals().set("create_matcher", create).unwrap();
        let result: (bool, Vec<u32>, Vec<u32>, Option<Vec<u32>>) = lua
            .load(
                r#"
                local m = create_matcher({ "two sum", "three sum", "add two numbers" })
                local done = m:start("two")
                local found = m:poll()
                local positions = m:positions(1, "tsm")
                m:start("sum")
                return done, found, positions, m:wait()
                "#,
            )
            .eval()
            .unwrap();
        assert!(result.0);
        // From one, as Lua counts.
        assert_eq!(result.1[0], 1);
        assert_eq!(result.2, vec![0, 4, 6]);
        assert_eq!(result.3, Some(vec![1, 2]));
    }

    #[test]
    fn positions_are_the_characters_matched() {
        let mut m = matcher(&["two sum"]);
        assert_eq!(m.positions(0, "tsm"), vec![0, 4, 6]);
        assert_eq!(m.positions(5, "tsm"), Vec::<u32>::new());
    }
}
