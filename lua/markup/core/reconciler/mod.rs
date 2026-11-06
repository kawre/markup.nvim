mod fiber;

pub use fiber::*;

use crate::prelude::*;
use mlua::prelude::*;
use std::{
    cell::RefCell,
    collections::{HashMap, HashSet},
    rc::Rc,
};

#[derive(Default)]
pub struct Reconciler {
    pub current_root: Option<FiberRef>,
    pub work_in_progress_root: Option<FiberRef>,
    pub next_unit_of_work: Option<FiberRef>,
    pub current_fiber: Option<FiberRef>,
    pub work_stack: Vec<FiberRef>,
    pub work_stack_visited: HashSet<*const ()>,
    pub current_dom: Option<DomRef>,
}

impl Reconciler {
    pub fn new() -> Self {
        Reconciler {
            current_root: None,
            work_in_progress_root: None,
            next_unit_of_work: None,
            current_fiber: None,
            work_stack: Vec::new(),
            work_stack_visited: HashSet::new(),
            current_dom: None,
        }
    }
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

/// Main reconcile function - equivalent to M.call() in Lua
pub fn reconcile(lua: &Lua, root_fiber: FiberRef) -> FiberRef {
    with_reconciler(|rec| {
        rec.current_fiber = None;
        rec.work_stack.clear();
        rec.work_stack_visited.clear();
    });

    let new_root = work_loop(lua, root_fiber);
    commit(lua, &new_root);

    // Print the complete fiber tree structure
    // print_complete_fiber_tree(&new_root);

    new_root
}

/// Create a fresh work stack with root WIP fiber - equivalent to M.fresh_stack()
fn fresh_stack(lua: &Lua, root_fiber: FiberRef) -> FiberRef {
    with_reconciler(|rec| {
        rec.work_stack.clear();
        rec.work_stack.push(root_fiber.clone());
        rec.work_stack_visited.clear();
    });

    root_fiber
}

/// DFS reconciliation work loop - equivalent to M.work_loop()
fn work_loop(lua: &Lua, root_fiber: FiberRef) -> FiberRef {
    let mut unit = fresh_stack(lua, root_fiber);

    loop {
        let maybe_fiber = with_reconciler(|rec| rec.work_stack.pop());

        match maybe_fiber {
            Some(fiber_ref) => {
                unit = fiber_ref.clone();
                process_unit_of_work(lua, &fiber_ref);
            }
            None => break,
        }
    }

    unit
}

/// Process a single unit of work - equivalent to M.process_unit()
fn process_unit_of_work(lua: &Lua, unit: &FiberRef) {
    let raw_ptr = Rc::as_ptr(unit) as *const ();

    let is_visited = with_reconciler(|rec| rec.work_stack_visited.contains(&raw_ptr));
    if is_visited {
        complete_unit_of_work(lua, unit);
        return;
    }

    with_reconciler(|rec| rec.current_fiber = Some(unit.clone()));

    let alternate = unit.borrow().alternate.clone();
    let next = begin_work(lua, alternate.as_ref(), unit);

    with_reconciler(|rec| {
        rec.current_fiber = None;
        rec.work_stack.push(unit.clone());
        if let Some(next_unit) = next {
            rec.work_stack.push(next_unit);
        }
        rec.work_stack_visited.insert(raw_ptr);
    });
}

/// Begin work on a fiber - equivalent to M.begin_work()
fn begin_work(lua: &Lua, current: Option<&FiberRef>, wip: &FiberRef) -> Option<FiberRef> {
    // Check for bailout conditions
    if let Some(current) = current {
        if can_bailout(current, wip) {
            return bailout(current, wip);
        }
    }

    mark_flags(lua, current, wip);

    let child = {
        match &wip.borrow().kind {
            FiberKind::Element(e) => reconcile_children(lua, current, wip, &e.pending_props),
            FiberKind::Function(key) => {
                let func = lua
                    .registry_value::<LuaFunction>(key)
                    .expect("Failed to get function from registry");

                let children = func
                    .call::<LuaValue>(())
                    .expect("Failed to call function component");

                let nkey = lua
                    .create_registry_value(children)
                    .expect("Failed to create registry key for children");

                reconcile_children(lua, current, wip, &nkey)
            }
            FiberKind::Text(_) => None,
            FiberKind::Fragment(key) => reconcile_children(lua, current, wip, key),
            FiberKind::Root(r) => reconcile_children(lua, current, wip, &r.element),
            FiberKind::Context(_) => todo!(),
        }
    };

    wip.borrow_mut().child = child.clone();

    child
}

/// Complete work on a unit - equivalent to M.complete_unit()
fn complete_unit_of_work(lua: &Lua, unit: &FiberRef) {
    let (current, wip) = (unit.borrow().alternate.clone(), unit);

    let wip_borrow = wip.borrow();
    match &wip_borrow.kind {
        FiberKind::Element(el) => {
            if current.is_some() && el.state_node.is_some() {
                drop(wip_borrow);
                update_single_node(wip);
            } else {
                drop(wip_borrow);
                place_single_node(lua, wip);
                populate_state_node(wip);
            }
        }
        FiberKind::Text(text) => {}
        _ => {}
    };

    let sibling = unit.borrow().sibling.clone();
    if let Some(sibling) = sibling {
        with_reconciler(|rec| rec.work_stack.push(sibling));
    }
}

/// Check if we can bailout early - equivalent to bailout conditions in M.begin_work()
fn can_bailout(current: &FiberRef, wip: &FiberRef) -> bool {
    let current_borrow = current.borrow();
    let wip_borrow = wip.borrow();

    // Compare fiber types and props for bailout
    match (&current_borrow.kind, &wip_borrow.kind) {
        (FiberKind::Element(c), FiberKind::Element(w)) => {
            c.element_tag == w.element_tag && wip_borrow.check_flags(Flag::NONE)
        }
        (FiberKind::Text(c), FiberKind::Text(w)) => c == w && wip_borrow.check_flags(Flag::NONE),
        _ => false,
    }
}

/// Bailout by cloning child fibers - equivalent to M.bailout()
fn bailout(current: &FiberRef, wip: &FiberRef) -> Option<FiberRef> {
    clone_child_fibers(current, wip);
    wip.borrow().child.clone()
}

/// Clone child fibers - equivalent to M.clone_child_fibers()
fn clone_child_fibers(current: &FiberRef, wip: &FiberRef) {
    todo!()
}

/// Render function component with hooks - equivalent to M.render_with_hooks()
fn render_with_hooks(lua: &Lua, _current: Option<&FiberRef>, wip: &FiberRef) -> ElementChildren {
    if let FiberKind::Function(key) = &wip.borrow().kind {
        let func: LuaFunction = lua
            .registry_value(key)
            .expect("Failed to get function from registry");

        // Get props (simplified - in full implementation this would be more complex)
        let props = lua.create_table().unwrap();

        // Call the function component
        let result: ElementChildren = func.call(props).unwrap();

        // Return children (simplified)
        result
    } else {
        panic!("Expected Function kind for render_with_hooks");
    }
}

fn mark_flags(lua: &Lua, current: Option<&FiberRef>, wip: &FiberRef) {
    let mut wip_borrow = wip.borrow_mut();

    match &wip_borrow.kind {
        FiberKind::Element(e) => {
            if let Some(curr) = current {
                if e.state_node.is_some() {
                    if let FiberKind::Element(old_e) = &curr.borrow().kind {
                        if let Some(memo) = &old_e.memoized_props {
                            if registry_keys_equal(lua, memo, &e.pending_props) {
                                wip_borrow.set_flags(Flag::UPDATE);
                            }
                        }
                    }
                }
            } else {
                wip_borrow.set_flags(Flag::PLACEMENT);
            }
        }
        FiberKind::Function(_) => {}
        FiberKind::Text(new_text) => {
            if let Some(curr) = current {
                if matches!(&curr.borrow().kind, FiberKind::Text(old_text) if old_text == new_text)
                {
                    wip_borrow.set_flags(Flag::UPDATE);
                }
            } else {
                wip_borrow.set_flags(Flag::PLACEMENT);
            }
        }
        FiberKind::Fragment(_) => {}
        FiberKind::Root(key) => {}
        FiberKind::Context(_) => {}
    }
}

/// Reconcile children - equivalent to M.reconcile_children()
fn reconcile_children(
    lua: &Lua,
    current: Option<&FiberRef>,
    wip: &FiberRef,
    children: &LuaRegistryKey,
) -> Option<FiberRef> {
    // Get children and reconcile
    let children = lua
        .registry_value::<LuaTable>(children)
        .expect("Failed to get children from registry")
        .get::<ElementChildren>("children")
        .expect("Failed to get children from table");

    let current_first_child = current.and_then(|c| c.borrow().child.clone());
    reconcile_child_fibers(lua, wip, current_first_child, children)
}

/// Reconcile child fibers - equivalent to M.reconcile_child_fibers()
fn reconcile_child_fibers(
    lua: &Lua,
    return_fiber: &FiberRef,
    current_first_child: Option<FiberRef>,
    new_children: ElementChildren,
) -> Option<FiberRef> {
    match new_children {
        ElementChildren::Single(child) => {
            reconcile_single_element_child(lua, return_fiber, current_first_child, child)
        }
        ElementChildren::Sequence(seq) => {
            reconcile_children_list(lua, return_fiber, current_first_child, seq)
        }
    }
}

fn reconcile_single_element_child(
    lua: &Lua,
    return_fiber: &FiberRef,
    current_first_child: Option<FiberRef>,
    element_child: ElementChild,
) -> Option<FiberRef> {
    match &element_child {
        ElementChild::Text(_) => {
            if let Some(current) = &current_first_child {
                if let FiberKind::Text(_) = current.borrow().kind {
                    delete_remaining_children(return_fiber, Some(current.clone()));
                    let mut existing = Fiber::create_work_in_progress(lua, current, element_child);

                    existing.parent = Some(return_fiber.clone());

                    return Some(existing.into_ref());
                }
            }

            delete_remaining_children(return_fiber, current_first_child);
            let mut fiber = Fiber::from_child(lua, element_child);

            fiber.parent = Some(return_fiber.clone());
            fiber.set_flags(Flag::PLACEMENT);

            Some(fiber.into_ref())
        }
        ElementChild::Element(el) => {
            let element: Element = lua
                .registry_value(el)
                .expect("Failed to get element from registry");

            let mut child = current_first_child.clone();

            while let Some(current_child) = &child {
                let sibling = {
                    let curr_borrow = current_child.borrow();

                    if curr_borrow.key == element.key {
                        if element.kind == curr_borrow.kind {
                            delete_remaining_children(return_fiber, curr_borrow.sibling.clone());
                            let mut existing =
                                Fiber::create_work_in_progress(lua, current_child, element_child);

                            existing.parent = Some(return_fiber.clone());

                            return Some(existing.into_ref());
                        }

                        delete_remaining_children(return_fiber, None);
                        break;
                    } else {
                        delete_child(return_fiber, current_child);
                    }

                    curr_borrow.sibling.clone()
                };

                child = sibling;
            }

            let mut created = Fiber::from_child(lua, element_child);

            created.parent = Some(return_fiber.clone());

            Some(created.into_ref())
        }
        ElementChild::Table(_) => panic!("Unexpected table child in reconcile_child_fibers"),
    }
}

fn reconcile_children_list(
    lua: &Lua,
    return_fiber: &FiberRef,
    current_first_child: Option<FiberRef>,
    new_children: Vec<ElementChild>,
) -> Option<FiberRef> {
    let mut new_index = 0;
    let mut last_placed_index = 0;

    let mut old_fiber = current_first_child;
    let mut prev_new_fiber: Option<FiberRef> = None;
    let mut result_first_child: Option<FiberRef> = None;

    let mut children_iter = new_children.into_iter().peekable();

    // First pass: update existing fibers in place
    while let Some(current_old) = old_fiber.clone() {
        if children_iter.peek().is_none() || current_old.borrow().index > new_index {
            break;
        }

        // Now safely consume the child
        let child = children_iter.next().unwrap();

        let next_old_fiber = current_old.borrow().sibling.clone();

        let new_fiber = update_slot(lua, return_fiber, Some(&current_old), &child);

        if new_fiber.is_none() {
            if current_old.borrow().index == new_index {
                old_fiber = Some(current_old);
            }
            break;
        }

        let new_fiber = new_fiber.unwrap();

        if new_fiber.borrow().alternate.is_none() {
            delete_child(return_fiber, &current_old);
        }

        last_placed_index = place_child(&new_fiber, last_placed_index, new_index);

        if prev_new_fiber.is_none() {
            result_first_child = Some(new_fiber.clone());
        } else {
            prev_new_fiber.as_ref().unwrap().borrow_mut().sibling = Some(new_fiber.clone());
        }

        prev_new_fiber = Some(new_fiber);
        new_index += 1;
        old_fiber = next_old_fiber;
    }

    // All new children processed, delete remaining old fibers
    if children_iter.len() == 0 {
        delete_remaining_children(return_fiber, old_fiber);
        return result_first_child;
    }

    // If there are no more old fibers, create new ones for remaining children
    if old_fiber.is_none() {
        for child in children_iter {
            if let Some(new_fiber) = create_child(lua, return_fiber, child) {
                last_placed_index = place_child(&new_fiber, last_placed_index, new_index);

                if let Some(prev) = &prev_new_fiber {
                    prev.borrow_mut().sibling = Some(new_fiber.clone());
                } else {
                    result_first_child = Some(new_fiber.clone());
                }

                prev_new_fiber = Some(new_fiber);
            }

            new_index += 1;
        }

        return result_first_child;
    }

    // Create a map of remaining old fibers for efficient lookup
    let existing_children = map_remaining_children(old_fiber);

    // Process remaining new children using the map
    for child in children_iter {
        let new_fiber = update_from_map(lua, &existing_children, return_fiber, new_index, child);

        if let Some(new_fiber) = new_fiber {
            if new_fiber.borrow().alternate.is_some() {
                // Would normally remove from existing_children map here
            }

            last_placed_index = place_child(&new_fiber, last_placed_index, new_index);

            if let Some(prev) = &prev_new_fiber {
                prev.borrow_mut().sibling = Some(new_fiber.clone());
            } else {
                result_first_child = Some(new_fiber.clone());
            }

            prev_new_fiber = Some(new_fiber);
        }

        new_index += 1;
    }

    // Delete remaining children that weren't reused
    for fiber in existing_children.values() {
        delete_child(return_fiber, fiber);
    }

    result_first_child
}

// fn can_reuse_fiber(fiber: &FiberRef, element: &LuaValue) -> bool {
//     // Check if we can reuse the fiber for the given element
//     if let LuaValue::Table(table) = element {
//         if let Ok(kind) = table.get::<LuaValue>("kind") {
//             match (&fiber.borrow().kind, kind) {
//                 (FiberKind::Text(_), LuaValue::String(s)) if s.to_str().unwrap() == "text" => true,
//                 (FiberKind::Element(ef), LuaValue::String(s)) => {
//                     ef.element_tag == s.to_str().unwrap().to_string()
//                 }
//                 _ => false,
//             }
//         } else {
//             false
//         }
//     } else {
//         false
//     }
// }

fn update_slot(
    lua: &Lua,
    return_fiber: &FiberRef,
    old_fiber: Option<&FiberRef>,
    new_child: &ElementChild,
) -> Option<FiberRef> {
    let key = old_fiber.and_then(|f| f.borrow().key.clone());

    match new_child {
        ElementChild::Text(content) => {
            if key.is_some() {
                return None; // Text nodes can't have keys
            }
            update_text_node(lua, return_fiber, old_fiber, content)
        }
        ElementChild::Element(element_key) => {
            let element: Element = lua
                .registry_value(element_key)
                .expect("Failed to get element from registry");

            if element.key == key {
                update_element_node(lua, return_fiber, old_fiber, &element)
            } else {
                None
            }
        }
        ElementChild::Table(_) => {
            // For now, treat tables as fragments
            None
        }
    }
}

fn create_child(lua: &Lua, return_fiber: &FiberRef, child: ElementChild) -> Option<FiberRef> {
    Some(Fiber::from_child(lua, child).into_ref())
}

fn place_child(new_fiber: &FiberRef, last_placed_index: usize, new_index: usize) -> usize {
    new_fiber.borrow_mut().index = new_index;

    if let Some(alternate) = &new_fiber.borrow().alternate {
        let old_index = alternate.borrow().index;
        if old_index < last_placed_index {
            // This is a move
            new_fiber.borrow_mut().set_flags(Flag::PLACEMENT);
            last_placed_index
        } else {
            // This item can stay in place
            old_index
        }
    } else {
        // This is an insertion
        new_fiber.borrow_mut().set_flags(Flag::PLACEMENT);
        last_placed_index
    }
}

fn map_remaining_children(current_first_child: Option<FiberRef>) -> HashMap<String, FiberRef> {
    let mut existing = HashMap::new();

    let mut child = current_first_child;
    while let Some(fiber) = child {
        let key = if let Some(key) = &fiber.borrow().key {
            key.clone()
        } else {
            fiber.borrow().index.to_string()
        };

        let sibling = fiber.borrow().sibling.clone();
        existing.insert(key, fiber);
        child = sibling;
    }

    existing
}

fn update_from_map(
    lua: &Lua,
    existing_children: &HashMap<String, FiberRef>,
    return_fiber: &FiberRef,
    new_index: usize,
    new_child: ElementChild,
) -> Option<FiberRef> {
    let key = match new_child {
        ElementChild::Element(ref element_key) => {
            let element: Element = lua
                .registry_value(element_key)
                .expect("Failed to get element from registry");
            element.key.unwrap_or_else(|| new_index.to_string())
        }
        ElementChild::Text(_) => new_index.to_string(),
        ElementChild::Table(_) => new_index.to_string(),
    };

    if let Some(matched_fiber) = existing_children.get(&key) {
        update_slot(lua, return_fiber, Some(matched_fiber), &new_child)
    } else {
        create_child(lua, return_fiber, new_child)
    }
}

fn update_text_node(
    _lua: &Lua,
    return_fiber: &FiberRef,
    current: Option<&FiberRef>,
    content: &str,
) -> Option<FiberRef> {
    todo!()
    // if let Some(current_fiber) = current {
    //     if let FiberKind::Text(_) = &current_fiber.borrow().kind {
    //         // Reuse existing text fiber
    //         let new_fiber = create_work_in_progress_from_fiber(current_fiber);
    //         new_fiber.borrow_mut().kind = FiberKind::Text(content.to_string());
    //         new_fiber.borrow_mut().parent = Some(return_fiber.clone());
    //         Some(new_fiber)
    //     } else {
    //         // Can't reuse, create new
    //         let mut fiber = Fiber::new(FiberKind::Text(content.to_string()));
    //         fiber.parent = Some(return_fiber.clone());
    //         Some(fiber.into_ref())
    //     }
    // } else {
    //     // Create new text fiber
    //     let mut fiber = Fiber::new(FiberKind::Text(content.to_string()));
    //     fiber.parent = Some(return_fiber.clone());
    //     Some(fiber.into_ref())
    // }
}

fn update_element_node(
    _lua: &Lua,
    return_fiber: &FiberRef,
    current: Option<&FiberRef>,
    element: &Element,
) -> Option<FiberRef> {
    todo!()
    // if let Some(current_fiber) = current {
    //     if let FiberKind::Element(current_element) = &current_fiber.borrow().kind {
    //         // Check if we can reuse the element
    //         match &element.kind {
    //             ElementKind::Element(tag, _props) => {
    //                 if current_element.element_tag == *tag {
    //                     // Reuse existing element fiber - create WIP
    //                     let new_fiber = create_work_in_progress_from_fiber(current_fiber);
    //                     new_fiber.borrow_mut().parent = Some(return_fiber.clone());
    //                     // Note: In a full implementation, we'd update the pending props here
    //                     // but since we can't clone LuaRegistryKey, we skip this for now
    //                     Some(new_fiber)
    //                 } else {
    //                     // Can't reuse different tag, would need to create new
    //                     // but we can't easily do this without cloning registry keys
    //                     None
    //                 }
    //             }
    //             _ => {
    //                 // Different element type, would need to create new
    //                 None
    //             }
    //         }
    //     } else {
    //         // Can't reuse different fiber type
    //         None
    //     }
    // } else {
    //     // Would create new element fiber, but we can't easily do this
    //     // without being able to clone LuaRegistryKey
    //     None
    // }
}

fn use_fiber(old_fiber: &FiberRef, _new_element: &LuaValue) -> FiberRef {
    // For now, just return a reference to the old fiber
    // In a full implementation, this would update the fiber with new props
    old_fiber.clone()
}

fn set_return_pointer(child: &FiberRef, parent: &FiberRef) {
    child.borrow_mut().parent = Some(parent.clone());
}

fn delete_child(_return_fiber: &FiberRef, _child: &FiberRef) {
    // Mark child for deletion
}

fn delete_remaining_children(return_fiber: &FiberRef, mut current_first_child: Option<FiberRef>) {
    while let Some(child) = current_first_child {
        delete_child(return_fiber, &child);
        current_first_child = child.borrow().sibling.clone();
    }
}

fn place_single_node(lua: &Lua, wip: &FiberRef) {
    let dom = with_reconciler(|rec| rec.current_dom.clone()).expect("No current DOM found");

    let mut wip_borrow = wip.borrow_mut();
    let node = Node::try_from_fiber_kind(lua, &wip_borrow.kind)
        .expect("Failed to convert fiber kind to Node");
    let node_id = dom.borrow_mut().add_node(node);

    match &mut wip_borrow.kind {
        FiberKind::Element(el) => {
            el.state_node = Some(node_id);
        }
        FiberKind::Text(text) => {
            text.state_node = Some(node_id);
        }
        _ => panic!("Unsupported fiber kind for placement"),
    }
}

fn populate_state_node(_wip: &FiberRef) {
    // Populate the state node with children
}

fn update_single_node(_wip: &FiberRef) {
    // Update existing node
}

fn update_node_text(_wip: &FiberRef) {
    // Update text content of node
}

fn commit(_lua: &Lua, _root: &FiberRef) {
    // Commit phase - apply all changes to the actual DOM
}

fn registry_keys_equal(lua: &Lua, key1: &LuaRegistryKey, key2: &LuaRegistryKey) -> bool {
    // TODO maybe store raw pointers alongside keys to avoid this?

    let val1 = lua
        .registry_value::<mlua::Value>(key1)
        .expect("Failed to get value from registry");
    let val2 = lua
        .registry_value::<mlua::Value>(key2)
        .expect("Failed to get value from registry");

    val1 == val2
}
