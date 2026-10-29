//! A small ghost icon button, like gpui-kit's `Button::ghost().small().icon(…)`.

const gooey = @import("gooey");
const components = @import("gooey-components");
const theme = @import("theme.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Svg = components.Svg;

const size: f32 = 24;
pub const IconButton = struct {
    icon: []const u8,
    on_click: ui.HandlerRef,
    icon_size: f32 = 16,

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(ui.box(.{
            .width = size,
            .height = size,
            .corner_radius = 6,
            .alignment = .{ .main = .center, .cross = .center },
            .hover_background = theme.color.sidebar_accent,
            .on_click_handler = self.on_click,
        }, .{
            Svg{ .path = self.icon, .size = self.icon_size, .no_fill = true, .stroke_color = theme.color.muted, .stroke_width = self.icon_size / 12 },
        }));
    }
};
