//! Debug Tools
//!
//! Debugging and performance monitoring utilities.
//!
//! - `Debugger` - UI inspector/profiler overlay (toggle with Cmd/Ctrl+Shift+I)
//! - `RenderStats` - Per-frame render statistics (draw calls, primitives, culling)

const std = @import("std");

// =============================================================================
// Debugger / Inspector
// =============================================================================

pub const debugger = @import("debugger.zig");

pub const Debugger = debugger.Debugger;
pub const DebugMode = debugger.DebugMode;
pub const FrameSnapshot = debugger.FrameSnapshot;
pub const ElementInfo = debugger.ElementInfo;

// =============================================================================
// Render Statistics
// =============================================================================

pub const render_stats = @import("render_stats.zig");

pub const RenderStats = render_stats.RenderStats;
pub const frame_stats = &render_stats.frame_stats;
pub const beginFrame = render_stats.beginFrame;
pub const getStats = render_stats.getStats;

// =============================================================================
// Tests
// =============================================================================

test {
    std.testing.refAllDecls(@This());
}
