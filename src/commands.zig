//! The command palette's commands: a title, the shortcut shown beside it, and
//! either an action or a list of commands to show in its place (a submenu).

const gooey = @import("gooey");
const AppState = @import("state.zig").AppState;
const workspace = @import("workspace.zig");
const terminal = @import("terminal.zig");
const tab_actions = @import("tab_actions.zig");
const settings_actions = @import("settings_actions.zig");
const picker = @import("picker.zig");
const font_actions = @import("font_actions.zig");
const Settings = @import("settings.zig").Settings;
const find = @import("find.zig");
const save = @import("save.zig");
const settings_window = @import("settings_window.zig");

const Run = *const fn (*AppState, *gooey.Window) void;

pub const Command = struct {
    title: []const u8,
    keys: []const u8 = "",
    run: ?Run = null,
    children: []const Command = &.{},
};

pub const root = [_]Command{
    .{ .title = "Find File…", .keys = "⌘O", .run = picker.open },
    .{ .title = "Open Folder…", .keys = "⇧⌘O", .run = workspace.openFolder },
    .{ .title = "Save", .keys = "⌘S", .run = save.run },
    .{ .title = "Close Tab", .keys = "⌘W", .run = tab_actions.closeShown },
    .{ .title = "Find in File", .keys = "⌘F", .run = find.open },
    .{ .title = "Find Next", .keys = "⌘G", .run = find.next },
    .{ .title = "Find Previous", .keys = "⇧⌘G", .run = find.prev },
    .{ .title = "Toggle Sidebar", .keys = "⌘\\", .run = AppState.toggleSidebar },
    .{ .title = "Toggle Terminal", .keys = "⌘J", .run = terminal.toggle },
    .{ .title = "Zoom In", .keys = "⌘+", .run = font_actions.zoomIn },
    .{ .title = "Zoom Out", .keys = "⌘−", .run = font_actions.zoomOut },
    .{ .title = "Actual Size", .keys = "⌘0", .run = font_actions.zoomReset },
    .{ .title = "Settings…", .keys = "⌘,", .run = settings_window.open },
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
