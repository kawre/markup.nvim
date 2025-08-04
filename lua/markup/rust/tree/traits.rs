use taffy::{
    AbsoluteAxis, AvailableSpace, LayoutInput, LayoutOutput, LayoutPartialTree, Line, NodeId,
    RequestedAxis, RunMode, Size, SizingMode,
};

/// A private trait which allows us to add extra convenience methods to types which implement
/// LayoutTree without making those methods public.
pub trait LayoutPartialTreeExt: LayoutPartialTree {
    /// Compute the size of the node given the specified constraints
    #[inline(always)]
    #[allow(clippy::too_many_arguments)]
    fn measure_child_size(
        &mut self,
        node_id: NodeId,
        known_dimensions: Size<Option<f32>>,
        parent_size: Size<Option<f32>>,
        available_space: Size<AvailableSpace>,
        sizing_mode: SizingMode,
        axis: AbsoluteAxis,
        vertical_margins_are_collapsible: Line<bool>,
    ) -> f32 {
        self.compute_child_layout(
            node_id,
            LayoutInput {
                known_dimensions,
                parent_size,
                available_space,
                sizing_mode,
                axis: axis.into(),
                run_mode: RunMode::ComputeSize,
                vertical_margins_are_collapsible,
            },
        )
        .size
        .get_abs(axis)
    }

    /// Perform a full layout on the node given the specified constraints
    #[inline(always)]
    fn perform_child_layout(
        &mut self,
        node_id: NodeId,
        known_dimensions: Size<Option<f32>>,
        parent_size: Size<Option<f32>>,
        available_space: Size<AvailableSpace>,
        sizing_mode: SizingMode,
        vertical_margins_are_collapsible: Line<bool>,
    ) -> LayoutOutput {
        self.compute_child_layout(
            node_id,
            LayoutInput {
                known_dimensions,
                parent_size,
                available_space,
                sizing_mode,
                axis: RequestedAxis::Both,
                run_mode: RunMode::PerformLayout,
                vertical_margins_are_collapsible,
            },
        )
    }

    /// Alias to `resolve_calc_value` with a shorter function name
    #[inline(always)]
    // #[cfg(feature = "calc")]
    fn calc(&self, val: *const (), basis: f32) -> f32 {
        self.resolve_calc_value(val, basis)
    }

    // /// Alias to `resolve_calc_value` with a shorter function name
    // #[inline(always)]
    // #[cfg(not(feature = "calc"))]
    // fn calc(&self, _val: *const (), _basis: f32) -> f32 {
    //     0.0
    // }
}

impl<T: LayoutPartialTree> LayoutPartialTreeExt for T {}
