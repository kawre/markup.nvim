mod fiber;

pub use fiber::*;

use crate::prelude::*;
use std::{cell::RefCell, collections::HashSet, rc::Rc};

#[derive(Default)]
pub struct Reconciler {
    current_fiber: Option<FiberRef>,
    work_stack: Vec<FiberRef>,
    work_stack_visited: HashSet<*const ()>,
}

thread_local! {
    static RECONCILER: RefCell<Reconciler> = RefCell::new(Reconciler::default());
}

// Functions that access the global reconciler
fn with_reconciler<F, R>(f: F) -> R
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

        let new_root = work_loop(rec, &root_fiber);
        // commit(&rec, &new_root);
        new_root
    })
}

fn prepare_stack(rec: &mut Reconciler, root_fiber: &FiberRef) {
    let props = root_fiber.borrow().pending_props.clone();
    let work_in_progress = Fiber::create_work_in_progress(root_fiber, props);

    rec.work_stack.push(work_in_progress.clone());
}

fn work_loop(rec: &mut Reconciler, root_fiber: &FiberRef) -> FiberRef {
    prepare_stack(rec, root_fiber);

    let mut unit: Option<FiberRef> = None;
    while let Some(fiber_ref) = rec.work_stack.pop() {
        unit = Some(fiber_ref.clone());
        process_unit_of_work(rec, &fiber_ref);
    }

    unit.expect("No unit of work processed")
}

fn process_unit_of_work(rec: &mut Reconciler, unit: &FiberRef) {
    let raw_ptr = Rc::as_ptr(&unit) as *const ();

    if rec.work_stack_visited.contains(&raw_ptr) {
        complete_unit_of_work(rec, &unit);
        return;
    }

    rec.current_fiber = Some(unit.clone());
    let next = begin_work(rec, unit.borrow().alternate.clone(), unit);
    rec.current_fiber = None;

    unit.borrow_mut().memoized_props = next.borrow().pending_props.clone();

    rec.work_stack.push(unit.clone());
    rec.work_stack.push(next.clone());

    rec.work_stack_visited.insert(raw_ptr);
}

fn complete_unit_of_work(rec: &mut Reconciler, unit: &FiberRef) -> FiberRef {
    todo!()
}

fn begin_work(
    rec: &mut Reconciler,
    current: Option<FiberRef>,
    work_in_progress: &FiberRef,
) -> FiberRef {
    let current_ref = current.as_ref();
    if check_early_bailout(current_ref, work_in_progress) {
        return {
            // early bailout
            clone_child_fibers(current_ref, work_in_progress);
            work_in_progress.clone()
        };
    }

    let wip_borrow = work_in_progress.borrow();
    match wip_borrow.tag {
        FiberTag::Function => update_function_component(rec, current.as_ref(), work_in_progress),
        FiberTag::Element => update_element_component(rec, current.as_ref(), work_in_progress),
        FiberTag::Text => update_text_component(rec, current.as_ref(), work_in_progress),
        FiberTag::Root => update_root_component(rec, current.as_ref(), work_in_progress),
        FiberTag::Context => update_context_component(rec, current.as_ref(), work_in_progress),
        FiberTag::Fragment => update_fragment_component(rec, current.as_ref(), work_in_progress),
    };

    todo!()
}

fn check_early_bailout(current: Option<&FiberRef>, work_in_progress: &FiberRef) -> bool {
    if let Some(current) = current {
        let current_borrow = current.borrow();
        let wip_borrow = work_in_progress.borrow();
        let old_props_ref = current_borrow.pending_props.as_ref();
        let new_props_ref = wip_borrow.pending_props.as_ref();

        if current_borrow.tag == wip_borrow.tag {
            if let (Some(old_props), Some(new_props)) = (old_props_ref, new_props_ref) {
                if old_props == new_props && wip_borrow.check_flags(Flag::NONE) {
                    return true;
                }
            }
        };
    }
    false
}

fn update_element_component(
    rec: &mut Reconciler,
    current: Option<&FiberRef>,
    work_in_progress: &FiberRef,
) -> FiberRef {
    todo!()
}

fn update_text_component(
    rec: &mut Reconciler,
    current: Option<&FiberRef>,
    work_in_progress: &FiberRef,
) -> FiberRef {
    todo!()
}

fn update_function_component(
    rec: &mut Reconciler,
    current: Option<&FiberRef>,
    work_in_progress: &FiberRef,
) -> FiberRef {
    todo!()
}

fn update_root_component(
    rec: &mut Reconciler,
    current: Option<&FiberRef>,
    work_in_progress: &FiberRef,
) -> FiberRef {
    todo!()
}

fn update_context_component(
    rec: &mut Reconciler,
    current: Option<&FiberRef>,
    work_in_progress: &FiberRef,
) -> FiberRef {
    todo!()
}

fn update_fragment_component(
    rec: &mut Reconciler,
    current: Option<&FiberRef>,
    work_in_progress: &FiberRef,
) -> FiberRef {
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
