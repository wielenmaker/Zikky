//! Opening, showing and closing tabs, as the tree, quick open and the tab
//! bar ask for them.

const gooey = @import("gooey");
const tabs = @import("tabs.zig");
const save = @import("save.zig");
const AppState = @import("state.zig").AppState;

/// Opens a file node in the current tab (or shows its tab if it has one).
pub fn open(s: *AppState, g: *gooey.Window, node: u32) void {
    if (s.tabs.find(node)) |i| return select(s, g, i);
    s.tabs.adopt(g);
    const t = s.tabs.active() orelse return openNew(s, g, node);
    // A tab with unsaved text keeps it: the file opens beside it.
    if (t.node == tabs.untitled or save.unsaved(s, g)) return openNew(s, g, node);
    s.tabs.leave(g);
    tabs.load(t, g, node, s.paths[node]);
}

/// Opens a file node in a tab of its own (the current one when all are taken).
pub fn openNew(s: *AppState, g: *gooey.Window, node: u32) void {
    if (s.tabs.find(node)) |i| return select(s, g, i);
    s.tabs.adopt(g);
    s.tabs.leave(g);
    if (s.tabs.add(g, node, s.paths[node])) |i| s.tabs.current = i else tabs.load(s.tabs.active().?, g, node, s.paths[node]);
}

pub fn select(s: *AppState, g: *gooey.Window, i: u8) void {
    if (i == s.tabs.current or i >= s.tabs.count) return;
    s.tabs.leave(g);
    s.tabs.current = i;
}

/// A tab's ×.
pub fn close(s: *AppState, g: *gooey.Window, i: u8) void {
    save.close(s, g, i);
}

/// ⌘W: closes the shown tab.
pub fn closeShown(s: *AppState, g: *gooey.Window) void {
    if (s.tabs.count > 0) close(s, g, s.tabs.current);
}

/// Removes a tab without asking about unsaved text.
pub fn drop(s: *AppState, g: *gooey.Window, i: u8) void {
    if (i == s.tabs.current) s.tabs.leave(g);
    s.tabs.remove(g, i);
}
