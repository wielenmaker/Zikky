//! The command palette's commands: a title, the shortcut shown beside it, and
//! either an action or a list of commands to show in its place (a submenu).

const gooey = @import("gooey");
const AppState = @import("../state.zig").AppState;
const workspace = @import("../tree/workspace.zig");
const terminal = @import("../terminal/terminal.zig");
const tab_actions = @import("../editor/tab_actions.zig");
const settings_actions = @import("../settings/settings_actions.zig");
const picker = @import("picker.zig");
const font_actions = @import("../editor/font_actions.zig");
const Settings = @import("../settings/settings.zig").Settings;
const find = @import("../editor/find.zig");
const save = @import("../editor/save.zig");
const settings_window = @import("../settings/settings_window.zig");
const shortcuts = @import("../shortcuts/shortcuts.zig");

const Run = *const fn (*AppState, *gooey.Window) void;

pub const Command = struct {
    title: []const u8,
    shortcut: ?shortcuts.Id = null,
    run: ?Run = null,
    children: []const Command = &.{},
};

pub const root = [_]Command{
    .{ .title = "Find File…", .shortcut = .quick_open, .run = picker.open },
    .{ .title = "Open File…", .shortcut = .open_file, .run = workspace.openFile },
    .{ .title = "Open Folder…", .shortcut = .open_folder, .run = workspace.openFolder },
    .{ .title = "Save", .shortcut = .save, .run = save.run },
    .{ .title = "Close Tab", .shortcut = .close_tab, .run = tab_actions.closeShown },
    .{ .title = "Find in File", .shortcut = .find, .run = find.open },
    .{ .title = "Find Next", .shortcut = .find_next, .run = find.next },
    .{ .title = "Find Previous", .shortcut = .find_prev, .run = find.prev },
    .{ .title = "Toggle Sidebar", .shortcut = .sidebar, .run = AppState.toggleSidebar },
    .{ .title = "Toggle Terminal", .shortcut = .terminal, .run = terminal.toggle },
    .{ .title = "Zoom In", .shortcut = .zoom_in, .run = font_actions.zoomIn },
    .{ .title = "Zoom Out", .shortcut = .zoom_out, .run = font_actions.zoomOut },
    .{ .title = "Actual Size", .shortcut = .zoom_reset, .run = font_actions.zoomReset },
    .{ .title = "Settings…", .shortcut = .settings, .run = settings_window.open },
    .{ .title = "Appearance", .children = &.{
        .{ .title = "System", .run = appearance(.system) },
        .{ .title = "Light", .run = appearance(.light) },
        .{ .title = "Dark", .run = appearance(.dark) },
    } },
    .{ .title = "Toggle Vim Mode", .run = flip(.vim_mode) },
    .{ .title = "Toggle Word Wrap", .run = flip(.soft_wrap) },
    .{ .title = "Toggle Line Numbers", .run = flip(.line_numbers) },
};

fn flip(comptime sw: Settings.Switch) Run {
    return struct {
        fn run(s: *AppState, g: *gooey.Window) void {
            settings_actions.flip(s, g, sw);
        }
    }.run;
}

fn appearance(comptime mode: Settings.Appearance) Run {
    return struct {
        fn run(s: *AppState, g: *gooey.Window) void {
            settings_actions.setAppearance(s, g, mode);
        }
    }.run;
}
