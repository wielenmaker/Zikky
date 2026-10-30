//! The settings window's content (⌘,), like Rex's settings window: a light
//! sidebar with search and panes, then the pane.

const gooey = @import("gooey");
const theme = @import("../theme.zig");
const SettingsNav = @import("settings_nav.zig").SettingsNav;
const SettingsPane = @import("settings_pane.zig").SettingsPane;

const ui = gooey.ui;
const Cx = gooey.Cx;

pub const SettingsPage = struct {
    width: f32,
    height: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(ui.box(.{ .width = self.width, .height = self.height, .direction = .row }, .{
            SettingsNav{ .height = self.height },
            SettingsPane{ .width = self.width - theme.settings.sidebar_width, .height = self.height },
        }));
    }
};
