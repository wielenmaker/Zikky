//! The settings page's content: back/forward and the pane's title, then its
//! sections, each a title over a rounded group of rows (Rex's layout).

const gooey = @import("gooey");
const components = @import("gooey-components");
const theme = @import("../theme.zig");
const AppState = @import("../state.zig").AppState;
const settings_actions = @import("settings_actions.zig");
const font_actions = @import("../editor/font_actions.zig");
const panes = @import("settings_panes.zig");
const clickable = @import("../ui/clickable.zig");
const Toggle = @import("../ui/toggle.zig").Toggle;
const Stepper = @import("../ui/stepper.zig").Stepper;
const ThemeTiles = @import("theme_tiles.zig").ThemeTiles;
const SettingsPreview = @import("settings_preview.zig").SettingsPreview;
const FontButton = @import("font_button.zig").FontButton;
const ShortcutField = @import("shortcut_field.zig").ShortcutField;

const ui = gooey.ui;
const Cx = gooey.Cx;
const Svg = components.Svg;
const Lucide = components.Lucide;

pub const SettingsPane = struct {
    width: f32,
    height: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        const pane = &panes.panes[panes.shown(s.settings_pane, s.settings_query)];
        cx.render(ui.box(.{
            .width = self.width,
            .height = self.height,
            .background = theme.color.settings.content_bg,
            .padding = .{ .each = .{ .top = 7, .right = 20, .bottom = 20, .left = 8 } },
            .gap = 12,
        }, .{
            Header{ .title = pane.name },
            // Long panes (Keyboard) scroll under the header.
            ui.scroll("settings-scroll", .{
                .fill_width = true,
                .grow_height = true,
                .scrollbar_size = 6,
                .thumb_color = theme.color.scrollbar,
            }, .{Sections{ .pane = pane, .width = self.width - 28 }}),
        }));
    }
};

const Header = struct {
    title: []const u8,

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(ui.box(.{ .direction = .row, .alignment = .{ .cross = .center }, .gap = 8 }, .{
            ui.box(.{
                .height = 36,
                .corner_radius = 18,
                .background = theme.color.background.withAlpha(0.6),
                .border_width = .{ .all = 1 },
                .border_color = theme.color.settings.divider,
                .shadow = theme.shadow_xs,
                .direction = .row,
                .alignment = .{ .cross = .center },
                .padding = .{ .symmetric = .{ .x = 4, .y = 0 } },
            }, .{
                Nav{ .icon = Lucide.chevron_left, .on_click = cx.command(settings_actions.prevPane) },
                ui.box(.{ .width = 1, .height = 18, .background = theme.color.settings.divider }, .{}),
                Nav{ .icon = Lucide.chevron_right, .on_click = cx.command(settings_actions.nextPane) },
            }),
            ui.text(self.title, .{ .size = 15, .weight = .bold, .color = theme.color.settings.title }),
        }));
    }
};

const Nav = struct {
    icon: []const u8,
    on_click: ui.HandlerRef,

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(clickable.box(.{ .hover = theme.color.settings.selected, .on_click = self.on_click }, .{
            .width = 32,
            .height = 28,
            .corner_radius = 14,
            .alignment = .{ .main = .center, .cross = .center },
        }, .{
            Svg{ .path = self.icon, .size = 16, .no_fill = true, .stroke_color = theme.color.settings.label, .stroke_width = 1.6 },
        }));
    }
};

const Sections = struct {
    pane: *const panes.Pane,
    width: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        for (self.pane.sections) |*sec| cx.render(ui.box(.{
            .fill_width = true,
            .padding = .{ .each = .{ .top = 12, .right = 0, .bottom = 0, .left = 12 } },
            .gap = 10,
        }, .{
            ui.when(sec.title.len > 0, .{ui.box(.{ .padding = .{ .each = .{ .top = 0, .right = 0, .bottom = 0, .left = 10 } } }, .{
                ui.text(sec.title, .{ .size = theme.settings.text_size, .weight = .bold, .color = theme.color.settings.title }),
            })}),
            Group{ .rows = sec.rows, .width = self.width - 12 },
        }));
    }
};

/// A rounded box of rows with hairlines between them; the preview sits on
/// the editor container's background instead.
const Group = struct {
    rows: []const panes.Row,
    width: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        const c = theme.color;
        if (self.rows[0].control == .preview) return cx.render(ui.box(.{
            .fill_width = true,
            .corner_radius = 10,
            .background = c.background,
            .border_width = .{ .all = 1 },
            .border_color = c.border,
        }, .{SettingsPreview{ .width = self.width - 2 }}));
        cx.render(ui.box(.{
            .fill_width = true,
            .corner_radius = 10,
            .background = c.settings.group_bg,
            .padding = .{ .symmetric = .{ .x = 10, .y = 0 } },
        }, .{Rows{ .rows = self.rows }}));
    }
};

const Rows = struct {
    rows: []const panes.Row,

    pub fn render(self: @This(), cx: *Cx) void {
        for (self.rows, 0..) |*r, i| {
            if (i > 0) cx.render(ui.box(.{ .fill_width = true, .height = 1, .background = theme.color.settings.divider }, .{}));
            cx.render(Row{ .row = r });
        }
    }
};

const Row = struct {
    row: *const panes.Row,

    pub fn render(self: @This(), cx: *Cx) void {
        // The theme tiles: the label stays at the top, like Rex's.
        if (self.row.control == .theme) return cx.render(ui.box(.{
            .fill_width = true,
            .direction = .row,
            .padding = .{ .symmetric = .{ .x = 0, .y = 10 } },
            .gap = 12,
        }, .{
            ui.text(self.row.label, .{ .size = theme.settings.text_size, .color = theme.color.settings.label }),
            ui.box(.{ .grow_width = true }, .{}),
            ThemeTiles{},
        }));
        cx.render(ui.box(.{
            .fill_width = true,
            .height = 39,
            .direction = .row,
            .alignment = .{ .cross = .center },
            .gap = 12,
        }, .{
            ui.text(self.row.label, .{ .size = theme.settings.text_size, .color = theme.color.settings.label }),
            ui.box(.{ .grow_width = true }, .{}),
            Control{ .control = self.row.control },
        }));
    }
};

const Control = struct {
    control: panes.Control,

    pub fn render(self: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        switch (self.control) {
            .theme, .preview => {},
            .shortcut => |id| cx.render(ShortcutField{ .id = id }),
            .font => cx.render(FontButton{}),
            .toggle => |sw| cx.render(Toggle{ .on = s.settings.get(sw), .on_click = cx.commandWith(sw, settings_actions.flip) }),
            .font_size => cx.render(Stepper{
                .value = ui.textFmt("{d} pt", .{s.settings.font_size}, .{}).content,
                .on_down = cx.command(font_actions.zoomOut),
                .on_up = cx.command(font_actions.zoomIn),
            }),
            .exclude => cx.render(ui.input("settings-exclude", .{
                .bind = &s.exclude_edit,
                .on_blur_handler = cx.command(settings_actions.applyExclude),
                .width = 300,
                .height = 24,
                .padding = 4,
                .corner_radius = 5,
                .background = theme.color.settings.input_bg,
                .border_color = theme.color.settings.input_border,
                .border_color_focused = theme.color.settings.accent,
                .text_color = theme.color.settings.label,
                .cursor_color = theme.color.settings.accent,
            })),
        }
    }
};
