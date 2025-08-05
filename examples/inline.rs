use markup::compute::TextContext;
use markup::{node::Node, tree::Tree, *};

fn main() {
    let mut tree = Tree::new();

    let root = Node::new_from_kind_str("inline".to_string(), Style::DEFAULT);
    let node1 = Node::new_from_str("i'm inline");
    let node2 = Node::new_from_str("ffffffff");
    let node3 = Node::new_from_str("also");
    let node4 = Node::new_from_kind_str("inline".to_string(), Style::DEFAULT);
    let node5 = Node::new_from_str("also");

    let root_id = tree.add_node(root);
    let node1_id = tree.add_node(node1);
    let node2_id = tree.add_node(node2);
    let node3_id = tree.add_node(node3);
    let node4_id = tree.add_node(node4);
    let node5_id = tree.add_node(node5);

    tree.append_child(root_id, node1_id);
    tree.append_child(root_id, node2_id);
    tree.append_child(root_id, node3_id);
    tree.append_child(root_id, node4_id);
    tree.append_child(node4_id, node5_id);

    let available_space = Size {
        width: AvailableSpace::Definite(100.0),
        height: AvailableSpace::MIN_CONTENT,
    };

    tree.compute_layout(root_id, available_space, true);

    tree.print_tree(root_id);
}
