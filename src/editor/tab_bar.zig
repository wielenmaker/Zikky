//! The row above the editor container, level with the traffic lights: a tab
//! per open file (the shown one a pill like Rex's), and the show button when
//! the sidebar is hidden.

const gooey = @import("gooey");
const components = @import("gooey-components");
const theme = @import("../theme.zig");
const titlebar = @import("../titlebar.zig");
const AppState = @import("../state.zig").AppState;
const tab_actions = @import("tab_actions.zig");
const file_kind = @import("../ui/file_kind.zig");
const IconButton = @import("../ui/icon_button.zig").IconButton;
const FileIcon = @import("../ui/file_icon.zig").FileIcon;
const fade_label = @import("../ui/fade_label.zig");
const clickable = @import("../ui/clickable.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Color = gooey.Color;
const Lucide = components.Lucide;

const height: f32 = 30;
/// Long names are cut to this width and fade out; the other tabs share what
/// the shown one leaves, and below `min_label` show only their logo.
const max_label: f32 = 152;
const min_label: f32 = 48;
/// A tab's width besides its label: padding, logo, gaps and ×.
const chrome: f32 = 81;
const gap: f32 = 4;

pub const TabBar = struct {
    width: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        // Hidden sidebar: the show button takes the hide button's place.
        const left = titlebar.left(cx.window());
        cx.render(ui.box(.{
            .fill_width = true,
            .height = theme.titlebar_height,
            .direction = .row,
            .gap = gap,
            .alignment = .{ .cross = .center },
            .padding = .{ .each = .{ .top = 0, .right = 0, .bottom = 0, .left = if (s.sidebar_open) 0 else left } },
        }, .{
            ui.when(!s.sidebar_open, .{IconButton{ .icon = Lucide.panel_left_open, .on_click = cx.command(AppState.toggleSidebar) }}),
            Tabs{ .width = self.width - if (s.sidebar_open) 0 else left + 24 + gap },
        }));
    }
};

const Tabs = struct {
    width: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        const others: f32 = @floatFromInt(s.tabs.count -| 1);
        const rest = self.width - theme.inset - chrome - max_label - gap * (others + 1);
        const label = @min(rest / @max(others, 1) - chrome, max_label);
        for (s.tabs.items(), 0..) |t, i| {
            const index: u8 = @intCast(i);
            const shown = index == s.tabs.current;
            cx.render(Tab{ .name = s.tabName(&t), .index = index, .shown = shown, .max_label = if (shown) max_label else if (label < min_label) 0 else label });
        }
    }
};

const Tab = struct {
    name: []const u8,
    index: u8,
    shown: bool,
    /// 0: only the logo.
    max_label: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        const kind = file_kind.of(self.name);
        cx.render(clickable.box(.{
            .fill = if (self.shown) theme.color.tab_bg else Color.transparent,
            .on_click = cx.commandWith(self.index, tab_actions.select),
        }, .{
            .height = height,
            .direction = .row,
            .gap = 9,
            .alignment = .{ .cross = .center },
            .padding = .{ .each = .{ .top = 0, .right = if (self.max_label == 0) 10 else 4, .bottom = 0, .left = 10 } },
            .corner_radius = height / 2,
        }, .{
            // The file kind's logo, white on its color, in Rex's white ring.
            ui.box(.{
                .padding = .{ .all = 2 },
                .corner_radius = 6,
                .background = theme.color.background,
                .border_width = .{ .all = 0.5 },
                .border_color = theme.color.tab_ring,
            }, .{ui.box(.{
                .width = 21,
                .height = 16,
                .corner_radius = 4,
                .background = kind.color,
                .alignment = .{ .main = .center, .cross = .center },
            }, .{
                FileIcon{ .kind = kind, .size = 11, .color = Color.white },
            })}),
            ui.when(self.max_label > 0, .{
                fade_label.FadeLabel{
                    .text = self.name,
                    .max_width = self.max_label,
                    .color = if (self.shown) theme.color.tab_fg else theme.color.muted,
                    .paint = if (self.shown) fade_label.fadeTo("tab_bg") else fade_label.fadeTo("sidebar_bg"),
                },
                IconButton{ .icon = Lucide.x, .icon_size = 14, .on_click = cx.commandWith(self.index, tab_actions.close) },
            }),
        }));
    }
};
