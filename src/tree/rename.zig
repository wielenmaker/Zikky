//! Renaming a tree row in place (the row menu's Rename): its label becomes a
//! field with the name (less the extension) selected. Enter renames the file
//! on disk; Esc or clicking away cancels.

const std = @import("std");
const gooey = @import("gooey");
const AppState = @import("../state.zig").AppState;
const workspace = @import("workspace.zig");
const session = @import("../session.zig");
const tab_actions = @import("../editor/tab_actions.zig");

pub const input_id = "rename-input";

/// The row being renamed, and the field's text.
pub var node: ?u32 = null;
pub var text: []const u8 = "";
/// The row is a file New File just made: naming it opens it, cancelling removes it.
pub var created = false;
/// Focus the field and select the name once it is drawn.
var focus = false;

pub fn start(s: *AppState, g: *gooey.Window, row: u32) void {
    node = row;
    text = s.names[row];
    focus = true;
    g.requestRender();
}

pub fn cancel(s: *AppState, g: *gooey.Window) void {
    const row = node orelse return;
    node = null;
    s.tabs.focus = true;
    g.requestRender();
    if (!created) return;
    created = false;
    std.Io.Dir.deleteFile(.cwd(), g.io, s.paths[row]) catch return;
    workspace.refresh(s, g, "", "");
}

fn commit(s: *AppState, g: *gooey.Window) void {
    const row = node orelse return;
    const opens = created;
    created = false;
    const name = std.mem.trim(u8, text, " ");
    cancel(s, g);
    if (name.len == 0 or std.mem.eql(u8, name, s.names[row]) or std.mem.indexOfScalar(u8, name, '/') != null) return;
    const old = s.paths[row];
    const new = std.fs.path.join(s.arena, &.{ std.fs.path.dirname(old) orelse ".", name }) catch return;
    // A case-only change finds the file itself on a case-insensitive disk.
    if (std.Io.Dir.access(.cwd(), g.io, new, .{})) |_| {
        if (!std.ascii.eqlIgnoreCase(name, s.names[row])) return;
    } else |_| {}
    std.Io.Dir.rename(.cwd(), old, .cwd(), new, g.io) catch return;
    const from = s.relativePath(row);
    const to = if (std.fs.path.dirname(from)) |dir| std.fs.path.join(s.arena, &.{ dir, name }) catch return else name;
    workspace.refresh(s, g, from, to);
    if (opens) tab_actions.open(s, g, session.find(s, g.io, to) orelse return);
}

/// While the field is focused: Enter commits, Esc cancels.
pub fn capture(g: *gooey.Window, event: gooey.input.InputEvent) bool {
    const k = switch (event) {
        .key_down => |k| k,
        else => return false,
    };
    const s = g.getRootState(AppState) orelse return false;
    if (node == null or !g.focus.isFocusedByName(input_id)) return false;
    switch (k.key) {
        .@"return" => commit(s, g),
        .escape => cancel(s, g),
        else => return false,
    }
    return true;
}

/// Once the field exists: focuses it and selects the name.
pub fn focusField(g: *gooey.Window) void {
    if (!focus) return;
    const field = g.widgetState(gooey.widgets.TextInputState, input_id) orelse return g.requestRender();
    // A new field gets the name only when drawn, so the cursor waits a frame.
    if (field.getText().len != text.len) return g.requestRender();
    focus = false;
    g.focusWidget(input_id);
    const dot = std.mem.lastIndexOfScalar(u8, text, '.') orelse 0;
    field.selection_anchor = 0;
    field.cursor_byte = if (dot > 0) dot else text.len;
}
