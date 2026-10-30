//! A switch like Rex's settings toggles: a pill track, its knob a wider pill.

const gooey = @import("gooey");
const theme = @import("../theme.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;

pub const Toggle = struct {
    on: bool,
    on_click: ui.HandlerRef,

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(ui.box(.{
            .width = 36,
            .height = 16,
            .corner_radius = 8,
            .padding = .{ .all = 2 },
            .background = if (self.on) theme.color.settings.accent else theme.color.settings.toggle_off,
            .direction = .row,
            .alignment = .{ .main = if (self.on) .end else .start, .cross = .center },
            .on_click_handler = self.on_click,
        }, .{
            ui.box(.{ .width = 20, .height = 12, .corner_radius = 6, .background = gooey.Color.white, .shadow = theme.shadow_xs }, .{}),
        }));
    }
};
