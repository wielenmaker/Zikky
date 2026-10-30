//! Shortcuts the user can change (Settings › Keyboard): each one's title,
//! default keys and keymap action, the user's keys from settings.json, and
//! binding them in the keymap and the menu bar.

const std = @import("std");
const gooey = @import("gooey");
const AppState = @import("../state.zig").AppState;
const Settings = @import("../settings/settings.zig").Settings;
const store = @import("../store.zig");
const combo = @import("combo.zig");
const app_menu = @import("../app_menu.zig");
const find = @import("../editor/find.zig");
const editor_font = @import("../editor/editor_font.zig");
const palette = @import("../overlays/palette.zig");
const sidebar = @import("../tree/sidebar.zig");
const terminal = @import("../terminal/terminal.zig");

const actionTypeId = gooey.input.actionTypeId;

pub const Id = enum { quick_open, open_file, open_folder, save, close_tab, find, find_next, find_prev, sidebar, terminal, palette, zoom_in, zoom_out, zoom_reset, settings };

const Shortcut = struct { title: []const u8, keys: []const u8 };

pub const all = std.enums.EnumArray(Id, Shortcut).init(.{
    .quick_open = .{ .title = "Find File…", .keys = "cmd-p" },
    .open_file = .{ .title = "Open File…", .keys = "cmd-o" },
    .open_folder = .{ .title = "Open Folder…", .keys = "shift-cmd-o" },
    .save = .{ .title = "Save", .keys = "cmd-s" },
    .close_tab = .{ .title = "Close Tab", .keys = "cmd-w" },
    .find = .{ .title = "Find in File", .keys = "cmd-f" },
    .find_next = .{ .title = "Find Next", .keys = "cmd-g" },
    .find_prev = .{ .title = "Find Previous", .keys = "shift-cmd-g" },
    .sidebar = .{ .title = "Toggle Sidebar", .keys = "cmd-backslash" },
    .terminal = .{ .title = "Toggle Terminal", .keys = "cmd-j" },
    .palette = .{ .title = "Command Palette…", .keys = "shift-cmd-p" },
    // ⇧⌘= is ⌘+ on US layouts.
    .zoom_in = .{ .title = "Zoom In", .keys = "cmd-equal shift-cmd-equal" },
    .zoom_out = .{ .title = "Zoom Out", .keys = "cmd-minus" },
    .zoom_reset = .{ .title = "Actual Size", .keys = "cmd-0" },
    .settings = .{ .title = "Settings…", .keys = "cmd-comma" },
});

/// The keys `id` runs on: the user's, else the default.
pub fn keys(settings: *const Settings, id: Id) []const u8 {
    for (settings.shortcuts) |o| if (std.mem.eql(u8, o.id, @tagName(id))) return o.keys;
    return all.get(id).keys;
}

pub fn isDefault(settings: *const Settings, id: Id) bool {
    return std.mem.eql(u8, keys(settings, id), all.get(id).keys);
}

/// Gives `id` the keys `k` (in `s.arena`), taking each from any other
/// shortcut, then saves and rebinds.
pub fn assign(s: *AppState, id: Id, k: []const u8) void {
    var it = std.mem.tokenizeScalar(u8, k, ' ');
    while (it.next()) |c| for (std.enums.values(Id)) |other| {
        if (other != id and combo.contains(keys(&s.settings, other), c)) put(s, other, "");
    };
    put(s, id, k);
    store.save(s.main.io, Settings.file, s.settings);
    apply(s, s.main);
}

pub fn reset(s: *AppState, _: *gooey.Window, id: Id) void {
    assign(s, id, all.get(id).keys);
}

/// Keeps only keys that differ from the default in settings.json.
fn put(s: *AppState, id: Id, k: []const u8) void {
    const old = s.settings.shortcuts;
    const list = s.arena.alloc(Settings.Shortcut, old.len + 1) catch return;
    var n: usize = 0;
    for (old) |o| if (!std.mem.eql(u8, o.id, @tagName(id))) {
        list[n] = o;
        n += 1;
    };
    if (!std.mem.eql(u8, k, all.get(id).keys)) {
        list[n] = .{ .id = @tagName(id), .keys = k };
        n += 1;
    }
    s.settings.shortcuts = list[0..n];
}

/// Binds every shortcut's keys in the keymap and shows them in the menu bar.
pub fn apply(s: *AppState, g: *gooey.Window) void {
    const km = g.keymap();
    var i: usize = 0;
    while (i < km.bindings.items.len) {
        if (ours(km.bindings.items[i].action_type)) _ = km.bindings.orderedRemove(i) else i += 1;
    }
    for (std.enums.values(Id)) |id| {
        var it = std.mem.tokenizeScalar(u8, keys(&s.settings, id), ' ');
        while (it.next()) |c| if (gooey.input.Keystroke.parse(c)) |ks| {
            km.bindings.append(km.allocator, .{ .keystroke = ks, .action_type = action(id), .context = null }) catch {};
        };
    }
    app_menu.install(&s.settings);
}

fn ours(a: gooey.input.ActionTypeId) bool {
    for (std.enums.values(Id)) |id| if (action(id) == a) return true;
    return false;
}

/// The keymap action `id` dispatches; handlers are registered in `main`.
fn action(id: Id) gooey.input.ActionTypeId {
    return switch (id) {
        .quick_open => actionTypeId(app_menu.QuickOpen),
        .open_file => actionTypeId(app_menu.OpenFile),
        .open_folder => actionTypeId(app_menu.OpenFolder),
        .save => actionTypeId(app_menu.Save),
        .close_tab => actionTypeId(app_menu.CloseFile),
        .find => actionTypeId(find.Open),
        .find_next => actionTypeId(find.Next),
        .find_prev => actionTypeId(find.Prev),
        .sidebar => actionTypeId(sidebar.ToggleSidebar),
        .terminal => actionTypeId(terminal.Toggle),
        .palette => actionTypeId(palette.Open),
        .zoom_in => actionTypeId(editor_font.ZoomIn),
        .zoom_out => actionTypeId(editor_font.ZoomOut),
        .zoom_reset => actionTypeId(editor_font.ZoomReset),
        .settings => actionTypeId(app_menu.OpenSettings),
    };
}
