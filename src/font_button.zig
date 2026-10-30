//! The font control: the editor font's name in a pill with up/down chevrons,
//! which opens a menu of the families (`font_actions.pick`).

const gooey = @import("gooey");
const components = @import("gooey-components");
const theme = @import("theme.zig");
const AppState = @import("state.zig").AppState;
const font_actions = @import("font_actions.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Svg = components.Svg;
const Lucide = components.Lucide;

pub const FontButton = struct {
    pub fn render(_: @This(), cx: *Cx) void {
        const t = theme.color.settings;
        cx.render(ui.box(.{
            .height = 24,
            .corner_radius = 6,
            .background = t.input_bg,
            .border_width = .{ .all = 1 },
            .border_color = t.input_border,
            .hover_background = t.selected,
            .direction = .row,
            .alignment = .{ .cross = .center },
            .padding = .{ .each = .{ .top = 0, .right = 6, .bottom = 0, .left = 10 } },
            .gap = 6,
            .on_click_handler = cx.command(font_actions.pick),
        }, .{
            ui.text(cx.state(AppState).settings.font, .{ .size = theme.settings.text_size, .color = t.label }),
            Svg{ .path = Lucide.chevrons_up_down, .size = 12, .no_fill = true, .stroke_color = theme.color.muted, .stroke_width = 1.6 },
        }));
    }
};
