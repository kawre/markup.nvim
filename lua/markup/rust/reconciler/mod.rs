mod fiber;

pub use fiber::*;

use crate::{dom, prelude::*};
use std::{cell::RefCell, collections::HashSet, ops::Deref, rc::Rc};

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

fn complete_unit_of_work(unit: &FiberRef) {
    // todo!()
}

fn begin_work(current: Option<&FiberRef>, work_in_progress: &FiberRef) -> Option<FiberRef> {
    // let current_ref = current;
    // if check_early_bailout(current_ref, work_in_progress) {
    //     return {
    //         // early bailout
    //         clone_child_fibers(current_ref, work_in_progress);
    //         work_in_progress.clone()
    //     };
    // }

    let kind = work_in_progress.borrow().kind.clone(); // or copy if enum is Copy

    match kind {
        FiberKind::Function(_) => update_function_component(current, work_in_progress),
        FiberKind::Element => update_element_component(current, work_in_progress),
        FiberKind::Text => update_text_component(current, work_in_progress),
        FiberKind::Root => update_root_component(current, work_in_progress),
        FiberKind::Context => update_context_component(current, work_in_progress),
        FiberKind::Fragment => update_fragment_component(current, work_in_progress),
    }
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

    work_in_progress.borrow().child.clone()
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

    None
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
    todo!()
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
