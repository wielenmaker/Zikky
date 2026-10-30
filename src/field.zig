//! A text field drawn on its container's fill (no background or border):
//! the find bar, palette, quick open and settings search.

const gooey = @import("gooey");
const theme = @import("theme.zig");
const props = @import("props.zig");

const ui = gooey.ui;

/// `over` sets at least `.bind` and `.placeholder`.
pub fn bare(id: []const u8, over: anytype) ui.Input {
    const c = theme.color;
    return ui.input(id, props.with(ui.InputStyle{
        .fill_width = true,
        .height = 26,
        .padding = 2,
        .background = gooey.Color.transparent,
        .border_width = 0,
        .text_color = c.foreground,
        .placeholder_color = c.muted,
        .cursor_color = c.primary,
    }, over));
}
