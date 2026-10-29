//! Open files, one tab each. Every tab has its own editor (text, cursor,
//! scroll, undo), kept while the tab is hidden; closing the tab frees it.

const std = @import("std");
const gooey = @import("gooey");
const file_text = @import("file_text.zig");
const terminal = @import("terminal.zig");

const CodeEditorState = gooey.widgets.CodeEditorState;

pub const max = 16;

/// Editor widget ids, one per slot; a tab keeps its slot while it is open.
const ids = blk: {
    var a: [max][]const u8 = undefined;
    for (&a, 0..) |*id, i| id.* = std.fmt.comptimePrint("editor{d}", .{i});
    break :blk a;
};

pub const View = struct { cursor: usize = 0, scroll_y: f32 = 0 };

pub const Tab = struct {
    node: u32,
    slot: u8,
    /// The file's bytes, owned by `std.heap.page_allocator`.
    file: []const u8 = "",
    /// Editor text; the editor rebinds it to its own buffer as you type.
    source: []const u8 = "",
    placeholder: []const u8 = "",
    /// The cursor and scroll the editor starts at, once it exists (it takes
    /// the text then too; it is created while drawing).
    pending: ?View = .{},
    /// Its terminal (⌘J), which outlives the files shown in the tab.
    term: terminal.Slot = .{},

    pub fn id(self: *const Tab) []const u8 {
        return ids[self.slot];
    }
};

pub const Tabs = struct {
    list: [max]Tab = undefined,
    count: u8 = 0,
    current: u8 = 0,
    /// Focus the shown editor once it is drawn (after a switch or an open).
    focus: bool = false,

    pub fn items(self: *Tabs) []Tab {
        return self.list[0..self.count];
    }

    pub fn active(self: *Tabs) ?*Tab {
        return if (self.count == 0) null else &self.list[self.current];
    }

    pub fn find(self: *Tabs, node: u32) ?u8 {
        for (self.items(), 0..) |t, i| if (t.node == node) return @intCast(i);
        return null;
    }

    /// Opens `node` in a new tab after the current one; null when full.
    pub fn add(self: *Tabs, g: *gooey.Window, node: u32, path: []const u8) ?u8 {
        if (self.count == max) return null;
        var used: [max]bool = @splat(false);
        for (self.items()) |t| used[t.slot] = true;
        const slot: u8 = @intCast(std.mem.indexOfScalar(bool, &used, false).?);
        const at: u8 = if (self.count == 0) 0 else self.current + 1;
        std.mem.copyBackwards(Tab, self.list[at + 1 .. self.count + 1], self.list[at..self.count]);
        self.count += 1;
        self.list[at] = .{ .node = node, .slot = slot };
        load(&self.list[at], g, node, path);
        return at;
    }

    pub fn remove(self: *Tabs, g: *gooey.Window, i: u8) void {
        free(&self.list[i], g);
        terminal.end(&self.list[i].term);
        std.mem.copyForwards(Tab, self.list[i .. self.count - 1], self.list[i + 1 .. self.count]);
        self.count -= 1;
        if (i < self.current or self.current == self.count) self.current -|= 1;
    }

    /// Hides the current editor; the shown one takes the focus.
    pub fn leave(self: *Tabs, g: *gooey.Window) void {
        g.blurAll();
        self.focus = true;
    }
};

/// The editor shown when no file is open.
pub const empty_id = "editor";

pub fn editor(g: *gooey.Window, id: []const u8) ?*CodeEditorState {
    return g.widgetState(CodeEditorState, id);
}

/// Shows `node` in `tab`; the old editor is dropped, so the file starts at the
/// top with its own undo history.
pub fn load(tab: *Tab, g: *gooey.Window, node: u32, path: []const u8) void {
    free(tab, g);
    const t = file_text.read(g.io, path);
    tab.* = .{ .node = node, .slot = tab.slot, .file = t.bytes, .source = t.bytes, .placeholder = t.message, .term = tab.term };
}

fn free(tab: *Tab, g: *gooey.Window) void {
    if (tab.file.len > 0) std.heap.page_allocator.free(tab.file);
    tab.file = "";
    // The focus manager keeps a pointer to the focused editor.
    if (editor(g, tab.id())) |ce| if (ce.isFocused()) g.blurAll();
    _ = g.element_states.remove(CodeEditorState, gooey.layout.LayoutId.fromString(tab.id()).id);
}
