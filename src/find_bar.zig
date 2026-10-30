//! The find bar: a pill floating at the top centre of the editor container,
//! with the query, the match count, ↑ / ↓ and ×.

const gooey = @import("gooey");
const components = @import("gooey-components");
const theme = @import("theme.zig");
const AppState = @import("state.zig").AppState;
const find = @import("find.zig");
const clickable = @import("clickable.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Color = gooey.Color;
const Svg = components.Svg;
const Lucide = components.Lucide;

const width: f32 = 320;
const height: f32 = 34;
const count_width: f32 = 40;
/// What the padding (14 + 6), border, gaps (5 × 4), count, divider and three buttons leave.
const query_width: f32 = width - 20 - 2 - 20 - count_width - 1 - 3 * 24;

pub const FindBar = struct {
    pub fn render(_: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        const f = &s.find;
        find.refresh(s, cx.window());
        const c = theme.color;
        const any = f.count > 0;
        cx.render(ui.box(.{
            .width = width,
            .height = height,
            .corner_radius = height / 2,
            .background = c.background,
            .border_width = .{ .all = 1 },
            .border_color = c.border,
            .shadow = .{ .blur_radius = 12, .offset_y = 4, .color = c.card_shadow.withAlpha(c.card_shadow.a * 0.6) },
            .direction = .row,
            .alignment = .{ .cross = .center },
            .padding = .{ .each = .{ .top = 0, .right = 6, .bottom = 0, .left = 14 } },
            .gap = 4,
            .floating = .{ .element_anchor = .center_top, .parent_anchor = .center_top, .offset_y = 10, .z_index = 10 },
        }, .{
            ui.input(find.query_id, .{
                .bind = &f.query,
                .placeholder = "Find",
                .width = query_width,
                .height = 24,
                .padding = 2,
                .background = Color.transparent,
                .border_width = 0,
                .text_color = c.foreground,
                .placeholder_color = c.muted,
                .cursor_color = c.primary,
            }),
            ui.box(.{ .width = count_width, .alignment = .{ .main = .end }, .direction = .row }, .{
                ui.when(f.query.len > 0, .{ui.textFmt("{d}/{d}", .{ if (f.current) |i| i + 1 else 0, f.count }, .{ .size = 12, .color = c.muted })}),
            }),
            ui.box(.{ .width = 1, .height = 16, .background = c.border }, .{}),
            Button{ .icon = Lucide.chevron_up, .enabled = any, .on_click = cx.command(find.prev) },
            Button{ .icon = Lucide.chevron_down, .enabled = any, .on_click = cx.command(find.next) },
            Button{ .icon = Lucide.x, .enabled = true, .on_click = cx.command(find.close) },
        }));
        if (f.focus_query) {
            f.focus_query = false;
            cx.window().focusWidget(find.query_id);
        }
    }
};

const Button = struct {
    icon: []const u8,
    enabled: bool,
    on_click: ui.HandlerRef,

    pub fn render(self: @This(), cx: *Cx) void {
        const c = theme.color;
        cx.render(clickable.box(.{
            .hover = if (self.enabled) c.sidebar_accent else null,
            .on_click = if (self.enabled) self.on_click else null,
        }, .{
            .width = 24,
            .height = 24,
            .corner_radius = 12,
            .alignment = .{ .main = .center, .cross = .center },
        }, .{
            Svg{ .path = self.icon, .size = 15, .no_fill = true, .stroke_color = if (self.enabled) c.muted else c.muted.withAlpha(0.4), .stroke_width = 1.6 },
        }));
    }
};
