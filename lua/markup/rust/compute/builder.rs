use crate::{
    compute::{InlineItem, TextChunk},
    node::Node,
};

#[derive(Clone)]
pub struct ComputedLineHighlight {
    pub col_start: usize,
    pub col_end: usize,
    pub highlight: String,
}

#[derive(Clone)]
pub struct ComputedLine {
    pub text: String,
    pub display_width: i32,
    pub highlights: Vec<ComputedLineHighlight>,
}

pub struct ComputedLinesBuilder {
    items: Vec<ComputedLine>,
    max_width: i32,
    max_line_width: i32, // compute the maximum width of the line

    current_line_width: i32,
    current_line_text: String,

    current_highlight: Option<String>,
    current_highlight_start: usize,

    highlights: Vec<ComputedLineHighlight>,
}

impl ComputedLinesBuilder {
    pub fn new(max_width: i32) -> Self {
        ComputedLinesBuilder {
            items: Vec::new(),
            max_width,
            current_line_width: 0,
            max_line_width: 0,
            current_line_text: String::new(),
            highlights: Vec::new(),
            current_highlight_start: 0,
            current_highlight: None,
        }
    }

    // 1. ("test", hl) "test"

    pub fn push_chunk(&mut self, chunk: &TextChunk, chunk_highlight: Option<&String>) {
        let display_width = chunk.display_width;
        let text = chunk.text_content.to_string();

        if self.current_highlight.is_some() && chunk_highlight.is_none() {
            // If we were in a highlight and now we are not, we need to close the highlight
            self.highlights.push(ComputedLineHighlight {
                col_start: self.current_highlight_start,
                col_end: self.current_line_width as usize,
                highlight: self.current_highlight.clone().unwrap(),
            });
            self.current_highlight = None;
        } else if chunk_highlight.is_some() {
            // If we are entering a highlight, we need to set the current highlight
            if self.current_highlight.is_none() {
                self.current_highlight_start = self.current_line_width as usize;
                self.current_highlight = Some(chunk_highlight.unwrap().clone());
            } else if self.current_highlight.as_ref().unwrap() != chunk_highlight.unwrap() {
                // If we are in a different highlight, we need to close the current one
                self.highlights.push(ComputedLineHighlight {
                    col_start: self.current_highlight_start,
                    col_end: self.current_line_width as usize,
                    highlight: self.current_highlight.clone().unwrap(),
                });
                self.current_highlight_start = self.current_line_width as usize;
                self.current_highlight = Some(chunk_highlight.unwrap().clone());
            }
        }

        if self.current_line_width == 0 {
            self.current_line_width = display_width;
        } else if self.current_line_width + display_width + 1 > self.max_width {
            // Start a new line
            if self.current_highlight.is_some()
                && self.current_highlight_start != self.current_line_width as usize
            {
                self.highlights.push(ComputedLineHighlight {
                    col_start: self.current_highlight_start,
                    col_end: self.current_line_width as usize,
                    highlight: self.current_highlight.clone().unwrap(),
                });
            };

            let computed_line = ComputedLine {
                text: self.current_line_text.clone(),
                display_width: self.current_line_width,
                highlights: self.highlights.clone(),
            };
            self.highlights.clear();
            self.items.push(computed_line);

            // Reset for new line
            self.current_line_text.clear();
            self.current_highlight_start = 0;
            self.current_line_width = display_width;
        } else {
            self.current_line_width += display_width + 1; // +1 for space
        }

        self.current_line_text += &text;
        self.max_line_width = self.max_line_width.max(self.current_line_width);
    }

    pub fn width(&self) -> i32 {
        self.max_line_width
    }

    pub fn height(&self) -> usize {
        self.items.len()
            + if !self.current_line_text.is_empty() {
                1
            } else {
                0
            }
    }
}
