use std::collections::BTreeMap;

use mlua::prelude::*;
use taffy::{NodeId, TraversePartialTree};

use crate::{
    compute::{ComputedLine, ComputedLineHighlight, ComputedLinesBuilder},
    node::NodeKind,
    tree::Tree,
};

pub struct HighlightRange {
    col_start: usize,
    col_end: usize,
    line: usize,
    highlight: String,
}

impl IntoLua for HighlightRange {
    fn into_lua(self, lua: &Lua) -> LuaResult<LuaValue> {
        let table = lua.create_table()?;
        table.set("col_start", self.col_start)?;
        table.set("col_end", self.col_end)?;
        table.set("line", self.line)?;
        table.set("highlight", self.highlight)?;
        Ok(LuaValue::Table(table))
    }
}

struct RenderLine<'a> {
    line: &'a ComputedLine,
    x: f32,
}

pub struct LineRenderer<'a> {
    pub highlights: Vec<HighlightRange>,
    screen_width: usize,
    lines_map: BTreeMap<i32, Vec<RenderLine<'a>>>,
}

impl<'a> LineRenderer<'a> {
    pub fn new(screen_width: usize) -> Self {
        LineRenderer {
            highlights: Vec::new(),
            screen_width,
            lines_map: BTreeMap::new(),
        }
    }

    pub fn add_line(&mut self, x: f32, y: f32, computed_line: &'a ComputedLine) {
        self.lines_map
            .entry(y as i32)
            .or_insert_with(Vec::new)
            .push(RenderLine {
                line: computed_line,
                x,
            });

        for highlight in &computed_line.highlights {
            self.highlights.push(HighlightRange {
                col_start: (x as usize) + highlight.col_start,
                col_end: (x as usize) + highlight.col_end,
                line: y as usize,
                highlight: highlight.highlight.clone(),
            });
        }
    }

    fn traverse_tree(&mut self, tree: &'a Tree, node_id: NodeId, zindex: usize) {
        let node = tree.node_from_id(node_id);

        match node.kind {
            // If the node is a text node, we can render it directly
            NodeKind::Inline => {
                let final_layout = node.final_layout;
                let x = final_layout.location.x;
                let y = final_layout.location.y;
                let computed_lines = node.computed_lines.as_ref().unwrap();

                for i in 0..computed_lines.len() {
                    let computed_line = &computed_lines[i];
                    self.add_line(x, y + i as f32, computed_line);
                }
            }
            _ => {
                for child_id in tree.child_ids(node_id) {
                    self.traverse_tree(tree, child_id, zindex + 1);
                }
            }
        }
    }

    pub fn render(
        &mut self,
        tree: &'a Tree,
        root_id: NodeId,
    ) -> (Vec<String>, Vec<HighlightRange>) {
        self.traverse_tree(tree, root_id, 1);
        let mut result_lines = Vec::new();

        for (_, render_line) in self.lines_map.iter_mut() {
            render_line.sort_by_key(|c| c.x as i32);

            let mut line = String::new();
            let mut current_pos = 0;

            for rline in render_line {
                let cline = rline.line;
                let x = rline.x as usize;

                if x > current_pos {
                    let gap = x - current_pos;
                    line.push_str(&" ".repeat(gap));
                    current_pos += gap;
                }

                line.push_str(&cline.text);
                current_pos += cline.display_width as usize;
            }

            if self.screen_width > current_pos {
                let fill = self.screen_width - current_pos;
                line.push_str(&" ".repeat(fill));
            }

            result_lines.push(line);
        }

        (result_lines, std::mem::take(&mut self.highlights))
    }
}
