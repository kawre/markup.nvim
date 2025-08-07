mod fiber;

pub use fiber::*;

use crate::prelude::*;
use std::{
    cell::RefCell,
    collections::{HashMap, HashSet},
    rc::Rc,
};

#[derive(Default)]
pub struct Reconciler {
    current_fiber: Option<FiberRef>,
    work_stack: Vec<FiberRef>,
    work_stack_visited: HashSet<*const ()>,
}

thread_local! {
    static RECONCILER: RefCell<Reconciler> = RefCell::new(Reconciler::default());
}

pub fn with_reconciler<F, R>(f: F) -> R
where
    F: FnOnce(&mut Reconciler) -> R,
{
    RECONCILER.with(|rec| {
        let mut rec = rec.borrow_mut();
        f(&mut rec)
    })
}

pub fn reconcile(root_fiber: FiberRef) -> FiberRef {
    with_reconciler(|rec| {
        rec.current_fiber = None;
        rec.work_stack.clear();
        rec.work_stack_visited.clear();
    });

    prepare_stack(&root_fiber);

    let new_root = work_loop();
    // commit(&rec, &new_root);
    new_root
}

fn prepare_stack(root_fiber: &FiberRef) {
    let props = root_fiber.borrow().pending_props.clone();
    let work_in_progress = Fiber::create_work_in_progress(root_fiber, props);
    with_reconciler(|rec| rec.work_stack.push(work_in_progress.clone()));
}

fn work_loop() -> FiberRef {
    let mut unit: Option<FiberRef> = None;

    loop {
        let maybe_fiber = with_reconciler(|rec| rec.work_stack.pop());

        match maybe_fiber {
            Some(fiber_ref) => {
                unit = Some(fiber_ref.clone());
                process_unit_of_work(&fiber_ref);
            }
            None => break,
        }
    }

    unit.expect("No unit of work processed")
}

#[inline(always)]
fn process_unit_of_work(unit: &FiberRef) {
    let raw_ptr = Rc::as_ptr(unit) as *const ();

    let maybe_visited = with_reconciler(|rec| rec.work_stack_visited.contains(&raw_ptr));
    if maybe_visited {
        complete_unit_of_work(unit);
        return;
    }

    with_reconciler(|rec| rec.current_fiber = Some(unit.clone()));

    let alternate = unit.borrow().alternate.clone();
    let next = begin_work(alternate.as_ref(), unit);

    // let pending_props = next.borrow().pending_props.clone(); // extract before mutable borrow

    // drop(alternate);

    with_reconciler(|rec| {
        rec.current_fiber = None;

        // unit.borrow_mut().memoized_props = next.borrow().pending_props.clone();

        rec.work_stack.push(unit.clone());
        if let Some(next_unit) = next {
            rec.work_stack.push(next_unit);
        }

        rec.work_stack_visited.insert(raw_ptr);
    });
}

#[inline(always)]
fn complete_unit_of_work(unit: &FiberRef) {
    let mut wip_borrow = unit.borrow_mut();
    let mut curr_borrow = wip_borrow.alternate.clone();

    match wip_borrow.kind {
        FiberKind::Element => {
            if let Some(curr) = curr_borrow {
                //
            }
        }
        FiberKind::Text => {
            if let Some(curr) = curr_borrow {
                // curr.borrow_mut().memoized_props = wip_borrow.pending_props.clone();
            }
        }
        _ => {
            // Handle other kinds of fibers if necessary
        }
    }

    if let Some(sibling) = &wip_borrow.sibling {
        with_reconciler(|rec| rec.work_stack.push(sibling.clone()))
    }
}

#[inline(always)]
fn begin_work(current: Option<&FiberRef>, work_in_progress: &FiberRef) -> Option<FiberRef> {
    // let current_ref = current;
    // if check_early_bailout(current_ref, work_in_progress) {
    //     return {
    //         // early bailout
    //         clone_child_fibers(current_ref, work_in_progress);
    //         work_in_progress.clone()
    //     };
    // }

    let new_child = {
        let kind = work_in_progress.borrow().kind.clone();
        // dbg!(&kind);

        match kind {
            FiberKind::Function(_) => update_function_component(current, work_in_progress),
            FiberKind::Element => update_element_component(current, work_in_progress),
            FiberKind::Text => update_text_component(current, work_in_progress),
            FiberKind::Root => update_root_component(current, work_in_progress),
            FiberKind::Context => update_context_component(current, work_in_progress),
            FiberKind::Fragment => update_fragment_component(current, work_in_progress),
        }
    }; // wip_borrow is dropped here

    let mut wip_borrow = work_in_progress.borrow_mut();
    wip_borrow.child = new_child;
    wip_borrow.child.clone()
}

fn check_early_bailout(current: Option<&FiberRef>, work_in_progress: &FiberRef) -> bool {
    // if let Some(current) = current {
    //     let current_borrow = current.borrow();
    //     let wip_borrow = work_in_progress.borrow();
    //     let old_props_ref = current_borrow.pending_props;
    //     let new_props_ref = wip_borrow.pending_props;
    //
    //     if current_borrow.kind == wip_borrow.kind {
    //         if let (Some(old_props), Some(new_props)) = (old_props_ref, new_props_ref) {
    //             if old_props == new_props && wip_borrow.check_flags(Flag::NONE) {
    //                 return true;
    //             }
    //         }
    //     };
    // }
    false
}

fn update_element_component(
    current: Option<&FiberRef>,
    work_in_progress: &FiberRef,
) -> Option<FiberRef> {
    let mut wip_borrow = work_in_progress.borrow_mut();

    let next_props = wip_borrow.pending_props.clone();
    let next_children = next_props.children.clone();

    match current {
        None => wip_borrow.set_flags(Flag::PLACEMENT),
        Some(curr) => {
            let curr_borrow = curr.borrow();
            if wip_borrow.state_node.is_some()
                && curr_borrow.memoized_props != Some(wip_borrow.pending_props.clone())
            {
                wip_borrow.set_flags(Flag::UPDATE);
            }
        }
    };

    drop(wip_borrow);

    if let ElementChildren::Text(_) = next_children {
        reconcile_children(current, work_in_progress, &ElementChildren::None);
    } else {
        reconcile_children(current, work_in_progress, &next_children);
    }

    let wip_borrow = work_in_progress.borrow();
    wip_borrow.child.clone()
}

fn update_text_component(
    current: Option<&FiberRef>,
    work_in_progress: &FiberRef,
) -> Option<FiberRef> {
    if current.is_some() {
        work_in_progress.borrow_mut().set_flags(Flag::UPDATE);
    } else {
        work_in_progress.borrow_mut().set_flags(Flag::PLACEMENT);
    }

    None // leaf node, no children to reconcile
}

fn update_function_component(
    current: Option<&FiberRef>,
    work_in_progress: &FiberRef,
) -> Option<FiberRef> {
    todo!()
}

fn update_root_component(
    current: Option<&FiberRef>,
    work_in_progress: &FiberRef,
) -> Option<FiberRef> {
    todo!()
}

fn update_context_component(
    current: Option<&FiberRef>,
    work_in_progress: &FiberRef,
) -> Option<FiberRef> {
    todo!()
}

fn update_fragment_component(
    current: Option<&FiberRef>,
    work_in_progress: &FiberRef,
) -> Option<FiberRef> {
    todo!()
}

fn clone_child_fibers(current: Option<&FiberRef>, work_in_progress: &FiberRef) {
    if let Some(current) = current {
        let current_child = current.borrow().child.clone();
        let wip_child = work_in_progress.borrow().child.clone();

        if let (Some(c), Some(w)) = (current_child, wip_child) {
            if !Rc::ptr_eq(&c, &w) {
                panic!("Resuming work not yet implemented.");
            }
        }
    };

    let current_child = work_in_progress.borrow().child.clone();

    let Some(current_child) = current_child else {
        return;
    };

    // Clone the first child
    let new_child = Fiber::create_work_in_progress(
        &current_child,
        current_child.borrow().pending_props.clone(),
    );

    {
        work_in_progress.borrow_mut().child = Some(new_child.clone());
        new_child.borrow_mut().return_fiber = Some(work_in_progress.clone());
    }

    let mut current_child_iter = current_child;
    let mut new_child_iter = new_child;

    loop {
        let next_sibling = { current_child_iter.borrow().sibling.clone() };

        if let Some(sibling) = next_sibling {
            let wip_sibling =
                Fiber::create_work_in_progress(&sibling, sibling.borrow().pending_props.clone());

            {
                wip_sibling.borrow_mut().return_fiber = Some(work_in_progress.clone());
                new_child_iter.borrow_mut().sibling = Some(wip_sibling.clone());
            }

            current_child_iter = sibling;
            new_child_iter = wip_sibling;
        } else {
            new_child_iter.borrow_mut().sibling = None;
            break;
        }
    }
}

// fn prepare_new_child(mut new_child: LuaPropsChild) -> FiberRef {
//     while let (LuaPropsChild::Lsx(lsx), Lsx) {
//         new_child = tbl
//             .get("children")
//             .and_then(|v| v.try_into().ok())
//             .unwrap_or(LuaPropsChild::None);
//     }
//
//     new_child
// }

fn reconcile_children(
    current: Option<&FiberRef>,
    work_in_progress: &FiberRef,
    next_children: &ElementChildren,
) {
    let current_first_child = current.and_then(|c| c.borrow().child.clone());
    reconcile_child_fibers(
        work_in_progress,
        current_first_child.as_ref(),
        next_children,
    );
}

fn reconcile_child_fibers(
    return_fiber: &FiberRef,
    current_first_child: Option<&FiberRef>,
    new_child: &ElementChildren,
) {
    match new_child {
        ElementChildren::Text(str) => {
            reconcile_single_text(return_fiber, current_first_child, str);
        }
        ElementChildren::Sequence(children) => match children.as_slice() {
            [ElementChild::Element(element)] => {
                reconcile_single_element(return_fiber, current_first_child, element);
            }
            _ => {
                reconcile_children_list(return_fiber, current_first_child, children);
            }
        },
        ElementChildren::None => {}
    }

    delete_remaining_children(return_fiber, current_first_child);
}

fn reconcile_children_list(
    return_fiber: &FiberRef,
    current: Option<&FiberRef>,
    new_children: &[ElementChild],
) {
    let mut result_first_child: Option<FiberRef> = None;
    let mut previous_new_fiber: Option<FiberRef> = None;

    let mut old_fiber = current.cloned();
    let mut last_placed_index = 0;
    let mut new_idx = 0;

    // First pass: handle updates and moves
    while old_fiber.is_some() && new_idx < new_children.len() {
        let old_fiber_ref = old_fiber.as_ref().unwrap();
        let new_child = &new_children[new_idx];

        let next_old_fiber = if old_fiber_ref.borrow().index > new_idx {
            old_fiber.clone()
        } else {
            old_fiber_ref.borrow().sibling.clone()
        };

        let new_fiber = update_slot(return_fiber, old_fiber.as_ref(), new_child, new_idx);

        if new_fiber.is_none() {
            if old_fiber.is_none() {
                old_fiber = next_old_fiber;
            }
            break;
        }

        let new_fiber = new_fiber.unwrap();

        if old_fiber.is_some() && new_fiber.borrow().alternate.is_none() {
            // This is a new fiber, delete the old one
            delete_child(return_fiber, old_fiber.as_ref().unwrap());
        }

        last_placed_index = place_child(&new_fiber, last_placed_index, new_idx);

        if result_first_child.is_none() {
            result_first_child = Some(new_fiber.clone());
        } else if let Some(ref prev) = previous_new_fiber {
            prev.borrow_mut().sibling = Some(new_fiber.clone());
        }

        previous_new_fiber = Some(new_fiber);
        old_fiber = next_old_fiber;
        new_idx += 1;
    }

    // If we've exhausted new children, delete remaining old children
    if new_idx == new_children.len() {
        delete_remaining_children(return_fiber, old_fiber.as_ref());
        return_fiber.borrow_mut().child = result_first_child;
        return;
    }

    // If we've exhausted old children, create remaining new children
    if old_fiber.is_none() {
        while new_idx < new_children.len() {
            let new_child = &new_children[new_idx];
            let new_fiber = create_child(return_fiber, new_child, new_idx);

            if let Some(new_fiber) = new_fiber {
                last_placed_index = place_child(&new_fiber, last_placed_index, new_idx);

                if result_first_child.is_none() {
                    result_first_child = Some(new_fiber.clone());
                } else if let Some(ref prev) = previous_new_fiber {
                    prev.borrow_mut().sibling = Some(new_fiber.clone());
                }

                previous_new_fiber = Some(new_fiber);
            }

            new_idx += 1;
        }

        return_fiber.borrow_mut().child = result_first_child;
        return;
    }

    // Create a map of remaining old children by key
    let existing_children = map_remaining_children(old_fiber.as_ref());

    // Handle remaining children with potential reordering
    while new_idx < new_children.len() {
        let new_child = &new_children[new_idx];
        let new_fiber = update_from_map(&existing_children, return_fiber, new_idx, new_child);

        if let Some(new_fiber) = new_fiber {
            if new_fiber.borrow().alternate.is_some() {
                // This fiber was reused from existing children
                let key = get_child_key(new_child);
                if let Some(key) = key {
                    existing_children.borrow_mut().remove(&key);
                }
            }

            last_placed_index = place_child(&new_fiber, last_placed_index, new_idx);

            if result_first_child.is_none() {
                result_first_child = Some(new_fiber.clone());
            } else if let Some(ref prev) = previous_new_fiber {
                prev.borrow_mut().sibling = Some(new_fiber.clone());
            }

            previous_new_fiber = Some(new_fiber);
        }

        new_idx += 1;
    }

    // Delete any remaining old children that weren't reused
    for (_, old_child) in existing_children.borrow().iter() {
        delete_child(return_fiber, old_child);
    }

    return_fiber.borrow_mut().child = result_first_child;
}

fn reconcile_single_text(return_fiber: &FiberRef, current: Option<&FiberRef>, text_content: &str) {
    todo!()
}

fn reconcile_single_element(
    return_fiber: &FiberRef,
    current_first_child: Option<&FiberRef>,
    element: &ElementRef,
) -> FiberRef {
    let mut child = current_first_child.cloned();
    let props = element.props.clone();
    let maybe_key = element.key.as_ref();

    while let Some(curr_child) = child {
        let curr_borrow = curr_child.borrow();

        if curr_borrow.key.as_ref() == maybe_key {
            if curr_borrow.kind == element.kind {
                delete_remaining_children(return_fiber, curr_borrow.sibling.as_ref());
                let existing = Fiber::use_other(&curr_child, props.clone());
                existing.borrow_mut().return_fiber = Some(return_fiber.clone());
                return existing;
            };

            delete_remaining_children(return_fiber, Some(&curr_child));
            break;
        } else {
            delete_child(return_fiber, &curr_child);
        }

        child = curr_borrow.sibling.clone();
    }

    let mut created = Fiber::from(element);
    created.return_fiber = Some(return_fiber.clone());

    created.into_ref()
}

// Helper functions for reconcile_children_list

fn get_child_key(child: &ElementChild) -> Option<String> {
    match child {
        ElementChild::Element(element) => element.key.clone(),
        ElementChild::Text(_) => None,
        ElementChild::Table(_) => None, // Tables don't have keys for reconciliation
    }
}

fn create_child(
    return_fiber: &FiberRef,
    new_child: &ElementChild,
    index: usize,
) -> Option<FiberRef> {
    match new_child {
        ElementChild::Element(element) => {
            let mut fiber = Fiber::from(element);
            fiber.index = index;
            fiber.return_fiber = Some(return_fiber.clone());
            Some(fiber.into_ref())
        }
        ElementChild::Text(text) => {
            let mut fiber = Fiber::new(FiberKind::Text, ElementProps::from(text.clone()));
            fiber.index = index;
            fiber.return_fiber = Some(return_fiber.clone());
            Some(fiber.into_ref())
        }
        ElementChild::Table(_) => {
            // Tables are not directly renderable, skip them for now
            // In a full implementation, you might want to convert them to elements first
            None
        }
    }
}

fn update_slot(
    _return_fiber: &FiberRef,
    old_fiber: Option<&FiberRef>,
    new_child: &ElementChild,
    index: usize,
) -> Option<FiberRef> {
    let key = get_child_key(new_child);

    if let Some(old_fiber) = old_fiber {
        let old_borrow = old_fiber.borrow();
        if old_borrow.key == key {
            match new_child {
                ElementChild::Element(element) => {
                    if old_borrow.kind == element.kind {
                        let existing = Fiber::use_other(old_fiber, element.props.clone());
                        existing.borrow_mut().index = index;
                        return Some(existing);
                    }
                }
                ElementChild::Text(text) => {
                    if matches!(old_borrow.kind, FiberKind::Text) {
                        let existing =
                            Fiber::use_other(old_fiber, ElementProps::from(text.clone()));
                        existing.borrow_mut().index = index;
                        return Some(existing);
                    }
                }
                ElementChild::Table(_) => {
                    // Tables are not directly comparable to fibers
                    return None;
                }
            }
        }
    }

    None
}

fn place_child(new_fiber: &FiberRef, last_placed_index: usize, new_index: usize) -> usize {
    let mut new_fiber_borrow = new_fiber.borrow_mut();
    new_fiber_borrow.index = new_index;

    if let Some(alternate) = &new_fiber_borrow.alternate {
        let old_index = alternate.borrow().index;
        if old_index < last_placed_index {
            // This is a move
            new_fiber_borrow.set_flags(Flag::PLACEMENT);
            last_placed_index
        } else {
            old_index
        }
    } else {
        // This is a new fiber
        new_fiber_borrow.set_flags(Flag::PLACEMENT);
        last_placed_index
    }
}

fn map_remaining_children(
    first_child: Option<&FiberRef>,
) -> Rc<RefCell<HashMap<String, FiberRef>>> {
    let map = Rc::new(RefCell::new(HashMap::new()));
    let mut child = first_child.cloned();

    while let Some(curr_child) = child {
        let curr_borrow = curr_child.borrow();
        if let Some(key) = &curr_borrow.key {
            map.borrow_mut().insert(key.clone(), curr_child.clone());
        }
        child = curr_borrow.sibling.clone();
    }

    map
}

fn update_from_map(
    existing_children: &Rc<RefCell<HashMap<String, FiberRef>>>,
    return_fiber: &FiberRef,
    new_idx: usize,
    new_child: &ElementChild,
) -> Option<FiberRef> {
    let key = get_child_key(new_child);

    if let Some(key) = key {
        if let Some(matching_fiber) = existing_children.borrow().get(&key).cloned() {
            let matching_borrow = matching_fiber.borrow();
            match new_child {
                ElementChild::Element(element) => {
                    if matching_borrow.kind == element.kind {
                        let existing = Fiber::use_other(&matching_fiber, element.props.clone());
                        existing.borrow_mut().return_fiber = Some(return_fiber.clone());
                        return Some(existing);
                    }
                }
                ElementChild::Text(text) => {
                    if matches!(matching_borrow.kind, FiberKind::Text) {
                        let existing =
                            Fiber::use_other(&matching_fiber, ElementProps::from(text.clone()));
                        existing.borrow_mut().return_fiber = Some(return_fiber.clone());
                        return Some(existing);
                    }
                }
                ElementChild::Table(_) => {
                    // Tables are not directly comparable to fibers
                    return None;
                }
            }
        }
    }

    // No matching fiber found, create new one
    create_child(return_fiber, new_child, new_idx)
}

fn delete_child(return_fiber: &FiberRef, child: &FiberRef) {
    let mut returnf_borrow_mut = return_fiber.borrow_mut();
    let deletions = returnf_borrow_mut.deletions.as_mut();

    if let Some(deletions) = deletions {
        deletions.push(child.clone());
        returnf_borrow_mut.set_flags(Flag::CHILD_DELETE);
    } else {
        returnf_borrow_mut.deletions = Some(vec![child.clone()]);
    }
}

fn delete_remaining_children(return_fiber: &FiberRef, current_first_child: Option<&FiberRef>) {
    let mut child = current_first_child.cloned();

    while let Some(curr_child) = child {
        delete_child(return_fiber, &curr_child);

        let curr_borrow = curr_child.borrow();
        child = curr_borrow.sibling.clone();
    }
}
