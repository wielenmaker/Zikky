//! The last session, kept in session.json: the folder, its expanded folders,
//! the open tabs with their cursor and scroll, and the sidebar. AppKit keeps
//! the window frame itself (`autosaveFrame`).

const std = @import("std");
const gooey = @import("gooey");
const store = @import("store.zig");
const AppState = @import("state.zig").AppState;
const tab_actions = @import("editor/tab_actions.zig");
const tabs = @import("editor/tabs.zig");

pub const Session = struct {
    folder: []const u8 = "",
    /// Paths relative to `folder`.
    expanded: []const []const u8 = &.{},
    tabs: []const Tab = &.{},
    /// The shown tab.
    current: usize = 0,
    sidebar_open: bool = true,

    pub const file_name = "session.json";
    pub const Tab = struct { file: []const u8 = "", cursor: usize = 0, scroll_y: f32 = 0 };
};

pub fn save(s: *AppState, g: *gooey.Window) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var expanded: std.ArrayList([]const u8) = .empty;
    for (1..@max(1, s.tree.node_count)) |n| {
        const node: u32 = @intCast(n);
        if (s.tree.nodes[node].is_folder and s.tree.isExpanded(node)) expanded.append(arena.allocator(), s.relativePath(node)) catch return;
    }
    var open: [tabs.max]Session.Tab = undefined;
    var n: usize = 0;
    var current: usize = 0;
    for (s.tabs.items(), 0..) |*t, i| {
        // An Untitled tab has no file to reopen.
        if (t.node == tabs.untitled) continue;
        if (i == s.tabs.current) current = n;
        // A tab never shown since the restore has no editor yet.
        const v: tabs.View = if (tabs.editor(g, t.id())) |e| .{ .cursor = e.text_area.cursor_byte, .scroll_y = e.text_area.scroll_offset_y } else t.pending orelse .{};
        open[n] = .{ .file = s.relativePath(t.node), .cursor = v.cursor, .scroll_y = v.scroll_y };
        n += 1;
    }
    store.save(g.io, Session.file_name, Session{
        .folder = if (s.tree.node_count > 0) s.paths[0] else "",
        .expanded = expanded.items,
        .tabs = open[0..n],
        .current = current,
        .sidebar_open = s.sidebar_open,
    });
}

/// Expands the saved folders and reopens the tabs; each one's cursor and
/// scroll are applied once its editor exists (`Tab.pending`).
pub fn restore(s: *AppState, g: *gooey.Window, ses: Session) void {
    s.sidebar_open = ses.sidebar_open;
    for (1..s.tree.node_count) |n| {
        const node: u32 = @intCast(n);
        for (ses.expanded) |e| if (std.mem.eql(u8, e, s.relativePath(node))) s.tree.expandNode(node);
    }
    s.tree.rebuild();
    var current: u8 = 0;
    for (ses.tabs, 0..) |saved, i| {
        const node = find(s, saved.file) orelse continue;
        tab_actions.openNew(s, g, node);
        s.tabs.active().?.pending = .{ .cursor = saved.cursor, .scroll_y = saved.scroll_y };
        if (i == ses.current) current = s.tabs.current;
    }
    tab_actions.select(s, g, current);
}

pub fn find(s: *AppState, rel: []const u8) ?u32 {
    for (1..s.tree.node_count) |n| {
        const node: u32 = @intCast(n);
        if (!s.tree.nodes[node].is_folder and std.mem.eql(u8, rel, s.relativePath(node))) return node;
    }
    return null;
}
