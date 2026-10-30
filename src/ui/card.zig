//! A floating rounded card (the command palette, quick open's two cards) and
//! the hairline between its sections.

const gooey = @import("gooey");
const theme = @import("../theme.zig");
const props = @import("props.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;

/// Like `ui.box`, starting from the card's fill, border, radius and shadow.
pub fn box(over: anytype, children: anytype) @TypeOf(ui.box(.{}, children)) {
    const c = theme.color;
    return ui.box(props.with(ui.Box{
        .background = c.background,
        .corner_radius = theme.radius_lg,
        .border_width = .{ .all = 1 },
        .border_color = c.border.withAlpha(0.8),
        .shadow = .{ .blur_radius = 24, .offset_y = 8, .color = c.card_shadow },
    }, over), children);
}

pub const Divider = struct {
    pub fn render(_: @This(), cx: *Cx) void {
        cx.render(ui.box(.{ .fill_width = true, .height = 1, .background = theme.color.border }, .{}));
    }
};
