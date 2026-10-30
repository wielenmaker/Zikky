//! A − value + control in Rex's segmented-control pill, for the font size.

const gooey = @import("gooey");
const components = @import("gooey-components");
const theme = @import("theme.zig");
const clickable = @import("clickable.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Svg = components.Svg;
const Lucide = components.Lucide;

pub const Stepper = struct {
    value: []const u8,
    on_down: ui.HandlerRef,
    on_up: ui.HandlerRef,

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(ui.box(.{
            .height = 26,
            .corner_radius = 13,
            .padding = .{ .all = 2 },
            .background = theme.color.settings.control_bg,
            .direction = .row,
            .alignment = .{ .cross = .center },
        }, .{
            Step{ .icon = Lucide.minus, .on_click = self.on_down },
            ui.box(.{
                .width = 56,
                .height = 22,
                .corner_radius = 11,
                .background = theme.color.settings.selected,
                .alignment = .{ .main = .center, .cross = .center },
            }, .{ui.text(self.value, .{ .size = theme.settings.text_size, .color = theme.color.settings.label })}),
            Step{ .icon = Lucide.plus, .on_click = self.on_up },
        }));
    }
};

const Step = struct {
    icon: []const u8,
    on_click: ui.HandlerRef,

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(clickable.box(.{ .hover = theme.color.settings.selected.withAlpha(0.6), .on_click = self.on_click }, .{
            .width = 28,
            .height = 22,
            .corner_radius = 11,
            .alignment = .{ .main = .center, .cross = .center },
        }, .{
            Svg{ .path = self.icon, .size = 12, .no_fill = true, .stroke_color = theme.color.settings.label, .stroke_width = 1.5 },
        }));
    }
};
