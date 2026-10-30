//! The Appearance choice: System, Light and Dark as tiny Zikky windows (like
//! Onyx's theme tiles); System shows the light window with the dark one's
//! right half over it.

const gooey = @import("gooey");
const theme = @import("theme.zig");
const AppState = @import("state.zig").AppState;
const settings_actions = @import("settings_actions.zig");
const Mode = @import("settings.zig").Settings.Appearance;

const ui = gooey.ui;
const Cx = gooey.Cx;
const Color = gooey.Color;
const Palette = theme.Palette;

const thumb_w: f32 = 76;
const thumb_h: f32 = 50;

pub const ThemeTiles = struct {
    pub fn render(_: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        cx.render(ui.box(.{ .direction = .row, .gap = 12 }, .{
            Tile{ .mode = .system, .label = "System", .selected = s.settings.appearance == .system },
            Tile{ .mode = .light, .label = "Light", .selected = s.settings.appearance == .light },
            Tile{ .mode = .dark, .label = "Dark", .selected = s.settings.appearance == .dark },
        }));
    }
};

const Tile = struct {
    mode: Mode,
    label: []const u8,
    selected: bool,

    pub fn render(self: @This(), cx: *Cx) void {
        const c = theme.color;
        cx.render(ui.box(.{
            .alignment = .{ .cross = .center },
            .gap = 4,
            .on_click_handler = cx.commandWith(self.mode, settings_actions.setAppearance),
        }, .{
            ui.box(.{
                .padding = .{ .all = 2 },
                .corner_radius = 10,
                .border_width = .{ .all = 2 },
                .border_color = if (self.selected) c.settings.accent else Color.transparent,
                .hover_border_color = if (self.selected) null else c.settings.divider,
            }, .{ui.canvas(thumb_w, thumb_h, switch (self.mode) {
                .system => paintSystem,
                .light => paintLight,
                .dark => paintDark,
            })}),
            ui.text(self.label, .{
                .size = 11,
                .weight = if (self.selected) .semibold else .regular,
                .color = if (self.selected) c.settings.title else c.muted,
            }),
        }));
    }
};

fn paintLight(ctx: *ui.DrawContext) void {
    window(ctx, &theme.light);
}

fn paintDark(ctx: *ui.DrawContext) void {
    window(ctx, &theme.dark);
}

fn paintSystem(ctx: *ui.DrawContext) void {
    window(ctx, &theme.light);
    const saved = ctx.clip_bounds;
    defer ctx.clip_bounds = saved;
    const o = ctx.bounds.origin;
    ctx.clip_bounds = saved.intersect(.{ .x = o.x + thumb_w / 2, .y = o.y, .width = thumb_w / 2, .height = thumb_h });
    window(ctx, &theme.dark);
}

/// One code line in the thumbnail: widths of colored runs, 0 for a gap.
const Run = struct { f32, []const u8 };
const code_lines = [_][]const Run{
    &.{ .{ 7, "keyword" }, .{ 2, "" }, .{ 8, "call" } },
    &.{},
    &.{ .{ 16, "comment" } },
    &.{ .{ 5, "keyword" }, .{ 2, "" }, .{ 9, "type" }, .{ 2, "" }, .{ 6, "keyword" } },
    &.{ .{ 3, "" }, .{ 6, "key" }, .{ 2, "" }, .{ 12, "string" } },
    &.{ .{ 3, "" }, .{ 7, "key" }, .{ 2, "" }, .{ 3, "number" } },
};

/// A tiny Zikky window: traffic lights and tree rows on the window
/// background, the code in its rounded container.
fn window(ctx: *ui.DrawContext, p: *const Palette) void {
    ctx.fillRoundedRect(0, 0, thumb_w, thumb_h, 6, p.sidebar_bg);
    for ([_]u32{ 0xff5f57, 0xfebc2e, 0x28c840 }, 0..) |hex, i| {
        ctx.fillCircle(6 + @as(f32, @floatFromInt(i)) * 4.5, 6, 1.5, Color.hex(hex));
    }
    for ([_]f32{ 13, 10, 12, 9, 11 }, 0..) |w, i| {
        ctx.fillRoundedRect(4, 13 + @as(f32, @floatFromInt(i)) * 5, w, 2, 1, p.sidebar_fg.withAlpha(0.35));
    }
    const left: f32 = 22;
    ctx.fillRoundedRect(left, 3, thumb_w - left - 3, thumb_h - 6, 4, p.border);
    ctx.fillRoundedRect(left + 0.5, 3.5, thumb_w - left - 4, thumb_h - 7, 3.5, p.background);
    inline for (code_lines, 0..) |runs, row| {
        var x: f32 = left + 5;
        const y = 8 + @as(f32, @floatFromInt(row)) * 5.5;
        inline for (runs) |r| {
            if (r[1].len > 0) ctx.fillRoundedRect(x, y, r[0], 2, 1, @field(p.syntax, r[1]));
            x += r[0];
        }
    }
}
