//! Where a node ends up once the boxes that clip it had their say, for things
//! drawn over the buffer, such as images.

use super::Engine;
use super::inspect::Rect;
use super::style::Display;
use super::tree::{ClientId, Index, TreeError};

fn intersect(a: Rect, b: Rect) -> Option<Rect> {
    let left = a.x.max(b.x);
    let top = a.y.max(b.y);
    let right = (a.x + a.width).min(b.x + b.width);
    let bottom = (a.y + a.height).min(b.y + b.height);
    (right > left && bottom > top).then(|| Rect {
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
    })
}

impl Engine {
    /// The border box of a node, without its margin.
    fn box_rect(&self, index: Index) -> Rect {
        let node = self.tree().node(index);
        let (x, y) = self.origin(index);
        let style = &node.style;
        Rect {
            x: x + style.margin.left,
            y: y + style.margin.top,
            width: node.geometry.content.width + style.inner().horizontal(),
            height: node.geometry.content.height + style.inner().vertical(),
        }
    }

    /// The part of a node that clipping ancestors leave visible, and whether
    /// that is all of it. Nothing when they hide it entirely.
    pub fn visible_rect(&self, id: ClientId) -> Result<Option<(Rect, bool)>, TreeError> {
        let tree = self.tree();
        let index = tree.index_of(id)?;
        let own = self.box_rect(index);
        let mut visible = own;

        let mut parent = tree.node(index).parent;
        while let Some(ancestor) = parent {
            let node = tree.node(ancestor);
            if node.display != Display::Contents {
                let extra = node.style.extra();
                if extra.clip || extra.clip_x {
                    let bounds = self.box_rect(ancestor);
                    // Each kind of clip only cuts its own direction.
                    let limit = Rect {
                        x: if extra.clip_x { bounds.x } else { i32::MIN / 2 },
                        width: if extra.clip_x { bounds.width } else { i32::MAX },
                        y: if extra.clip { bounds.y } else { i32::MIN / 2 },
                        height: if extra.clip { bounds.height } else { i32::MAX },
                    };
                    match intersect(visible, limit) {
                        Some(rect) => visible = rect,
                        None => return Ok(None),
                    }
                }
            }
            parent = node.parent;
        }

        Ok(Some((visible, visible == own)))
    }
}

#[cfg(test)]
mod tests {
    use super::super::protocol::{Command, Side, StyleProperty};
    use super::super::style::{Display, Length, Overflow};
    use super::super::{Engine, ROOT};

    /// A block three rows tall inside one that clips at `height`.
    fn engine_with_clip(height: i32) -> Engine {
        let mut engine = Engine::new(20);
        engine
            .apply(Command::Create {
                id: 2,
                display: Display::Block,
            })
            .unwrap();
        engine
            .apply(Command::Insert {
                parent: ROOT,
                child: 2,
                before: None,
            })
            .unwrap();
        engine
            .apply(Command::SetStyle {
                id: 2,
                property: StyleProperty::OverflowY(Overflow::Clip),
            })
            .unwrap();
        engine
            .apply(Command::SetStyle {
                id: 2,
                property: StyleProperty::Height(Length::Cells(height)),
            })
            .unwrap();

        engine
            .apply(Command::Create {
                id: 3,
                display: Display::Block,
            })
            .unwrap();
        engine
            .apply(Command::Insert {
                parent: 2,
                child: 3,
                before: None,
            })
            .unwrap();
        engine
            .apply(Command::SetStyle {
                id: 3,
                property: StyleProperty::Height(Length::Cells(3)),
            })
            .unwrap();
        engine
            .apply(Command::SetStyle {
                id: 3,
                property: StyleProperty::Width(Length::Cells(4)),
            })
            .unwrap();
        engine
            .apply(Command::SetStyle {
                id: 3,
                property: StyleProperty::Margin(Side::Left, 2),
            })
            .unwrap();
        engine.render(|_, _| ());
        engine
    }

    #[test]
    fn a_node_with_room_is_all_there() {
        let engine = engine_with_clip(5);
        let (rect, full) = engine.visible_rect(3).unwrap().unwrap();
        assert_eq!((rect.x, rect.y, rect.width, rect.height), (2, 0, 4, 3));
        assert!(full);
    }

    #[test]
    fn a_clipping_parent_cuts_it() {
        let engine = engine_with_clip(1);
        let (rect, full) = engine.visible_rect(3).unwrap().unwrap();
        assert_eq!(rect.height, 1);
        assert!(!full);
    }

    #[test]
    fn a_closed_parent_hides_it() {
        let engine = engine_with_clip(0);
        assert_eq!(engine.visible_rect(3).unwrap(), None);
    }
}
