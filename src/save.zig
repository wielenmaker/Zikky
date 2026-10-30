//! ⌘S and the Unsaved badge. A tab is unsaved once its editor's text differs
//! from its file; the scratch editor (no tab open) once it has any text, and
//! saving that asks where, then opens the new file in a tab.

const std = @import("std");
const gooey = @import("gooey");
const tabs = @import("tabs.zig");
const session = @import("session.zig");
const AppState = @import("state.zig").AppState;

const ui = gooey.ui;
const Cx = gooey.Cx;

const red = gooey.Color.hex(0xe5484d);

fn dirty(g: *gooey.Window, t: *const tabs.Tab) bool {
    const ce = tabs.editor(g, t.id()) orelse return false;
    return t.pending == null and !std.mem.eql(u8, ce.getText(), t.file);
}

pub fn unsaved(s: *AppState, g: *gooey.Window) bool {
    if (s.tabs.active()) |t| return dirty(g, t);
    return if (s.editor(g)) |ce| ce.getText().len > 0 else false;
}

/// ⌘S.
pub fn run(s: *AppState, g: *gooey.Window) void {
    const t = s.tabs.active() orelse return g.deferCommand(saveScratch);
    if (t.node == tabs.untitled) g.deferCommand(saveUntitled) else _ = saveTab(s, g, t);
}

/// Writes the tab's text to its file, or asks where when it has none; false if nothing was saved.
fn saveTab(s: *AppState, g: *gooey.Window, t: *tabs.Tab) bool {
    const text = (tabs.editor(g, t.id()) orelse return false).getText();
    if (t.node == tabs.untitled) {
        t.node = createFile(s, g, text) orelse return false;
    } else {
        if (t.pending != null or t.placeholder.len > 0) return false;
        std.Io.Dir.writeFile(.cwd(), g.io, .{ .sub_path = s.paths[t.node], .data = text }) catch return false;
    }
    const a = std.heap.page_allocator;
    const copy = a.dupe(u8, text) catch return false;
    if (t.file.len > 0 and t.file.ptr != t.source.ptr) a.free(t.file);
    t.file = copy;
    return true;
}

/// Asks where to save `text`, writes it and returns the new file's node (null if
/// cancelled, or saved outside the opened folder).
fn createFile(s: *AppState, g: *gooey.Window, text: []const u8) ?u32 {
    if (s.tree.node_count == 0) return null;
    const path = gooey.file_dialog.promptForNewPath(s.arena, .{ .directory = s.paths[0], .suggested_name = "untitled.txt", .prompt = "Save" }) orelse return null;
    std.Io.Dir.writeFile(.cwd(), g.io, .{ .sub_path = path, .data = text }) catch return null;
    s.refreshTree(g, "", "");
    const root = s.paths[0];
    if (!std.mem.startsWith(u8, path, root)) return null;
    return session.find(s, std.mem.trimStart(u8, path[root.len..], "/"));
}

/// A tab's × or ⌘W: closes it, asking first when it has unsaved changes.
pub fn close(s: *AppState, g: *gooey.Window, i: u8) void {
    if (!dirty(g, &s.tabs.list[i])) return s.dropTab(g, i);
    g.deferCommandWith(i, confirmClose);
}

/// Deferred: the alert runs a nested event loop.
fn confirmClose(s: *AppState, g: *gooey.Window, i: u8) void {
    const t = &s.tabs.list[i];
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const message = std.fmt.bufPrintSentinel(&buf, "Do you want to save the changes you made to {s}?", .{s.tabName(t)}, 0) catch return;
    switch (gooey.platform.macos.alert.ask(message, "Your changes will be lost if you don't save them.", &.{ "Save", "Don't Save", "Cancel" }) orelse return) {
        0 => if (saveTab(s, g, t)) s.dropTab(g, i),
        1 => s.dropTab(g, i),
        else => {},
    }
}

/// Deferred: the save panel runs a nested event loop.
fn saveUntitled(s: *AppState, g: *gooey.Window) void {
    _ = saveTab(s, g, s.tabs.active() orelse return);
}

/// Deferred, like `saveUntitled`: ⌘S with no tab open; the new file opens in a tab.
fn saveScratch(s: *AppState, g: *gooey.Window) void {
    const ce = s.editor(g) orelse return;
    if (ce.getText().len == 0) return;
    const node = createFile(s, g, ce.getText()) orelse return;
    ce.clear();
    tabs.scratch = "";
    s.openInNewTab(g, node);
}

pub const Badge = struct {
    pub fn render(_: @This(), cx: *Cx) void {
        cx.render(ui.box(.{
            .direction = .row,
            .gap = 6,
            .alignment = .{ .cross = .center },
            .floating = .{ .element_anchor = .left_bottom, .parent_anchor = .left_bottom, .offset_x = 14, .offset_y = -2, .z_index = 10 },
        }, .{
            ui.box(.{ .width = 6, .height = 6, .corner_radius = 3, .background = red }, .{}),
            ui.text("Unsaved", .{ .size = 11, .color = red }),
        }));
    }
};
