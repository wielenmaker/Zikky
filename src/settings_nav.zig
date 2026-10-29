//! The settings page's sidebar: a search field, then one row per pane.

const gooey = @import("gooey");
const components = @import("gooey-components");
const theme = @import("theme.zig");
const AppState = @import("state.zig").AppState;
const panes = @import("settings_panes.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Svg = components.Svg;
const Lucide = components.Lucide;

pub const SettingsNav = struct {
    height: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        cx.render(ui.box(.{
            .width = theme.settings.sidebar_width,
            .height = self.height,
            .background = theme.color.settings.sidebar_bg,
            .padding = .{ .each = .{ .top = 64, .right = 10, .bottom = 10, .left = 10 } },
            .gap = 2,
        }, .{
            Search{ .s = s },
            ui.box(.{ .height = 10 }, .{}),
            Items{ .s = s },
        }));
    }
};

/// The panes the search keeps.
const Items = struct {
    s: *const AppState,

    pub fn render(self: @This(), cx: *Cx) void {
        const shown = panes.shown(self.s.settings_pane, self.s.settings_query);
        for (&panes.panes, 0..) |*p, i| {
            if (p.matches(self.s.settings_query)) cx.render(Item{ .pane = p, .index = @intCast(i), .selected = i == shown });
        }
    }
};

const Search = struct {
    s: *AppState,

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(ui.box(.{
            .fill_width = true,
            .height = 28,
            .corner_radius = 14,
            .background = theme.color.settings.search_bg,
            .direction = .row,
            .alignment = .{ .cross = .center },
            .padding = .{ .each = .{ .top = 0, .right = 8, .bottom = 0, .left = 9 } },
            .gap = 4,
        }, .{
            Svg{ .path = Lucide.search, .size = 14, .no_fill = true, .stroke_color = theme.color.muted, .stroke_width = 1.6 },
            ui.input("settings-search", .{
                .bind = &self.s.settings_query,
                .placeholder = "Search Settings",
                .fill_width = true,
                .height = 24,
                .padding = 2,
                .background = gooey.Color.transparent,
                .border_width = 0,
                .text_color = theme.color.settings.label,
                .placeholder_color = theme.color.muted,
                .cursor_color = theme.color.settings.accent,
            }),
        }));
    }
};

const Item = struct {
    pane: *const panes.Pane,
    index: u8,
    selected: bool,

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(ui.box(.{
            .fill_width = true,
            .height = 32,
            .corner_radius = 8,
            .background = if (self.selected) theme.color.settings.selected else gooey.Color.transparent,
            .direction = .row,
            .alignment = .{ .cross = .center },
            .padding = .{ .each = .{ .top = 0, .right = 8, .bottom = 0, .left = 6 } },
            .gap = 8,
            .on_click_handler = cx.commandWith(self.index, AppState.selectPane),
        }, .{
            ui.box(.{
                .width = 20,
                .height = 20,
                .corner_radius = 5,
                .background = self.pane.tint,
                .alignment = .{ .main = .center, .cross = .center },
            }, .{
                Svg{ .path = self.pane.icon, .size = 12, .no_fill = true, .stroke_color = gooey.Color.white, .stroke_width = 2 },
            }),
            ui.text(self.pane.name, .{
                .size = theme.settings.text_size,
                .color = theme.color.settings.title,
                .weight = if (self.selected) .semibold else .regular,
            }),
        }));
    }
};
