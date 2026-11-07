//! Works out the smallest set of line replacements between two frames.

use super::paint::Line;

/// Replaces lines `first..last` of the previous frame with `lines`.
#[derive(Debug, PartialEq, Eq)]
pub struct Patch<'a> {
    pub first: usize,
    pub last: usize,
    pub lines: &'a [Line],
}

/// Trims the unchanged start and end. When the middle kept its length it is
/// split into runs of changed lines, otherwise it becomes one replacement.
/// Patches are in order and their ranges refer to the previous frame, so
/// applying them from last to first keeps every range valid.
pub fn diff<'a>(old: &[Line], new: &'a [Line]) -> Vec<Patch<'a>> {
    let shared = old.len().min(new.len());

    let start = (0..shared).find(|&i| old[i] != new[i]).unwrap_or(shared);
    let end = (0..shared - start)
        .find(|&i| old[old.len() - 1 - i] != new[new.len() - 1 - i])
        .unwrap_or(shared - start);

    let (old_end, new_end) = (old.len() - end, new.len() - end);

    if start == old_end && start == new_end {
        return Vec::new();
    }

    if old_end - start != new_end - start {
        return vec![Patch {
            first: start,
            last: old_end,
            lines: &new[start..new_end],
        }];
    }

    let mut patches = Vec::new();
    let mut i = start;
    while i < old_end {
        if old[i] == new[i] {
            i += 1;
            continue;
        }
        let run = i;
        while i < old_end && old[i] != new[i] {
            i += 1;
        }
        patches.push(Patch {
            first: run,
            last: i,
            lines: &new[run..i],
        });
    }
    patches
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lines(values: &[&str]) -> Vec<Line> {
        values
            .iter()
            .map(|value| Line {
                text: value.to_string(),
                marks: Vec::new(),
                ..Line::default()
            })
            .collect()
    }

    fn apply(old: &[Line], patches: &[Patch]) -> Vec<Line> {
        let mut result = old.to_vec();
        for patch in patches.iter().rev() {
            result.splice(patch.first..patch.last, patch.lines.iter().cloned());
        }
        result
    }

    #[test]
    fn identical_frames_produce_nothing() {
        let frame = lines(&["a", "b"]);
        assert!(diff(&frame, &frame).is_empty());
    }

    #[test]
    fn changed_lines_become_separate_runs() {
        let old = lines(&["a", "b", "c", "d", "e"]);
        let new = lines(&["a", "x", "c", "y", "e"]);

        let patches = diff(&old, &new);

        assert_eq!(patches.len(), 2);
        assert_eq!(apply(&old, &patches), new);
    }

    #[test]
    fn inserting_mid_list_touches_only_the_new_lines() {
        let old = lines(&["a", "b", "c"]);
        let new = lines(&["a", "x", "y", "b", "c"]);

        let patches = diff(&old, &new);

        assert_eq!(patches, vec![Patch { first: 1, last: 1, lines: &new[1..3] }]);
    }

    #[test]
    fn removing_mid_list_touches_only_the_removed_lines() {
        let old = lines(&["a", "x", "y", "b"]);
        let new = lines(&["a", "b"]);

        let patches = diff(&old, &new);

        assert_eq!(patches, vec![Patch { first: 1, last: 3, lines: &[] }]);
    }

    #[test]
    fn repeated_lines_do_not_overlap_prefix_and_suffix() {
        let old = lines(&["a", "a"]);
        let new = lines(&["a", "a", "a"]);

        assert_eq!(apply(&old, &diff(&old, &new)), new);
    }

    #[test]
    fn covers_growth_shrink_and_full_replacement() {
        let cases: [(&[&str], &[&str]); 4] = [
            (&[], &["a", "b"]),
            (&["a", "b"], &[]),
            (&["a"], &["b"]),
            (&["a", "b", "c"], &["c", "b", "a", "d"]),
        ];

        for (old, new) in cases {
            let (old, new) = (lines(old), lines(new));
            assert_eq!(apply(&old, &diff(&old, &new)), new);
        }
    }
}
