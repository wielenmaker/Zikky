//! Selecting the terminal's text with the mouse, through Ghostty's gesture
//! (drag by cell, double-click words, triple-click lines), and ⌘C. A program
//! that asked for mouse reports keeps the plain mouse; ⇧ selects over it.

const std = @import("std");
const vt = @import("ghostty-vt");
const gooey = @import("gooey");
const Session = @import("term_session.zig").Session;

/// Where the pointer is, in points from the grid's top-left, and the grid.
pub const At = struct {
    x: f64,
    y: f64,
    cell_w: f32,
    cell_h: f32,

    fn cell(a: At, t: *const Session) vt.point.Coordinate {
        const col = std.math.clamp(@floor(a.x / a.cell_w), 0, @as(f64, @floatFromInt(t.cols - 1)));
        const row = std.math.clamp(@floor(a.y / a.cell_h), 0, @as(f64, @floatFromInt(t.rows - 1)));
        return .{ .x = @intFromFloat(col), .y = @intFromFloat(row) };
    }

    fn geometry(a: At, t: *const Session) vt.SelectionGesture.Drag.Geometry {
        return .{
            .columns = t.cols,
            .cell_width = @intFromFloat(@max(1, a.cell_w)),
            .padding_left = 0,
            .screen_height = @intFromFloat(@as(f32, @floatFromInt(t.rows)) * a.cell_h),
        };
    }
};

/// Ghostty's default word boundaries (`selection_codepoints.zig`).
const word_boundaries = [_]u21{ 0, ' ', '\t', '\'', '"', '│', '`', '|', ':', ';', ',', '(', ')', '[', ']', '{', '}', '<', '>', '$' };

/// Whether a press at this point selects rather than going to the program.
pub fn selects(t: *Session, shift: bool) bool {
    t.lock();
    defer t.unlock();
    return shift or t.terminal.flags.mouse_event == .none;
}

pub fn press(t: *Session, at: At) void {
    t.lock();
    defer t.unlock();
    const term = &t.terminal;
    const pin = term.screens.active.pages.pin(.{ .viewport = at.cell(t) }) orelse return;
    const sel = t.gesture.press(term, .{
        .time = std.Io.Timestamp.now(t.io, .awake),
        .pin = pin,
        .xpos = at.x,
        .ypos = at.y,
        .max_distance = at.cell_w,
        .repeat_interval = 500 * std.time.ns_per_ms,
        .word_boundary_codepoints = &word_boundaries,
    }) catch return;
    term.screens.active.select(sel) catch {};
}

/// Extends the selection to the pointer; above or below the grid, scrolls a row.
pub fn drag(t: *Session, at: At) void {
    t.lock();
    defer t.unlock();
    const term = &t.terminal;
    const pin = term.screens.active.pages.pin(.{ .viewport = at.cell(t) }) orelse return;
    var sel = t.gesture.drag(term, .{
        .pin = pin,
        .xpos = at.x,
        .ypos = at.y,
        .rectangle = false,
        .word_boundary_codepoints = &word_boundaries,
        .geometry = at.geometry(t),
    });
    if (t.gesture.left_drag_autoscroll != .none) sel = t.gesture.autoscrollTick(term, .{
        .viewport = at.cell(t),
        .xpos = at.x,
        .ypos = at.y,
        .rectangle = false,
        .word_boundary_codepoints = &word_boundaries,
        .geometry = at.geometry(t),
    }) orelse sel;
    if (sel) |s| term.screens.active.select(s) catch {};
}

pub fn release(t: *Session, at: At) void {
    t.lock();
    defer t.unlock();
    const pin = t.terminal.screens.active.pages.pin(.{ .viewport = at.cell(t) });
    t.gesture.release(&t.terminal, .{ .pin = pin });
}

/// ⌘C: the selected text to the clipboard; false with nothing selected.
pub fn copy(t: *Session) bool {
    const a = std.heap.page_allocator;
    t.lock();
    const screen = t.terminal.screens.active;
    const text = if (screen.selection) |sel| screen.selectionString(a, .{ .sel = sel }) catch null else null;
    t.unlock();
    const s = text orelse return false;
    defer a.free(s);
    _ = gooey.platform.macos.clipboard.setText(s);
    return true;
}

test "drag selects, copy reads it" {
    const gpa = std.testing.allocator;
    var term: vt.Terminal = try .init(std.testing.io, gpa, .{ .cols = 20, .rows = 3 });
    defer term.deinit(gpa);
    var stream: vt.TerminalStream = .init(.{ .allocator = gpa, .handler = term.vtHandler() });
    defer stream.deinit();
    stream.nextSlice("hello world\r\nsecond");

    var g: vt.SelectionGesture = .init;
    defer g.deinit(&term);
    const screen = term.screens.active;
    const geo: vt.SelectionGesture.Drag.Geometry = .{ .columns = 20, .cell_width = 10, .padding_left = 0, .screen_height = 60 };
    const start = screen.pages.pin(.{ .viewport = .{ .x = 6, .y = 0 } }).?;
    try screen.select(try g.press(&term, .{ .time = null, .pin = start, .xpos = 61, .ypos = 5, .max_distance = 10, .repeat_interval = 0, .word_boundary_codepoints = &word_boundaries }));
    const end = screen.pages.pin(.{ .viewport = .{ .x = 10, .y = 0 } }).?;
    try screen.select(g.drag(&term, .{ .pin = end, .xpos = 109, .ypos = 5, .rectangle = false, .word_boundary_codepoints = &word_boundaries, .geometry = geo }).?);
    const text = try screen.selectionString(gpa, .{ .sel = screen.selection.? });
    defer gpa.free(text);
    try std.testing.expectEqualStrings("world", text);
}
