//! The wheel over the terminal, the way Ghostty routes it: to a program that
//! asked for mouse reports as wheel buttons, to a full-screen program on the
//! alternate screen as ↑/↓ (mode 1007), else through the scrollback.

const std = @import("std");
const vt = @import("ghostty-vt");
const Session = @import("term_session.zig").Session;

const MouseSize = @FieldType(vt.input.MouseEncodeOptions, "size");

/// Most steps sent for one wheel event.
const max_steps = 32;

/// Scrolls `rows` (up is negative) over the cell at `col`, `row`.
pub fn scroll(t: *Session, rows: isize, col: u16, row: u16, mods: vt.input.KeyMods) void {
    var buf: [max_steps * 32]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    t.lock();
    encode(&t.terminal, &w, rows, col, row, mods) catch {};
    t.unlock();
    t.send(w.buffered());
}

/// Writes what the program gets for the wheel, or scrolls the scrollback
/// when it gets nothing. Called with the session locked.
fn encode(term: *vt.Terminal, w: *std.Io.Writer, rows: isize, col: u16, row: u16, mods: vt.input.KeyMods) !void {
    const steps = @min(@abs(rows), max_steps);
    if (term.flags.mouse_event != .none) {
        // Whole cells of a nominal size: only the cell matters to the encoder.
        const cw = 10;
        const ch = 20;
        const size: MouseSize = .{
            .screen = .{ .width = @as(u32, term.cols) * cw, .height = @as(u32, term.rows) * ch },
            .cell = .{ .width = cw, .height = ch },
            .padding = .{},
        };
        const event: vt.input.MouseEncodeEvent = .{
            .button = if (rows < 0) .four else .five,
            .mods = mods,
            .pos = .{ .x = @floatFromInt(@as(u32, col) * cw + cw / 2), .y = @floatFromInt(@as(u32, row) * ch + ch / 2) },
        };
        const opts = vt.input.MouseEncodeOptions.fromTerminal(term, size);
        for (0..steps) |_| try vt.input.encodeMouse(w, event, opts);
    } else if (term.screens.active_key == .alternate and term.modes.get(.mouse_alternate_scroll)) {
        const app = term.modes.get(.cursor_keys);
        const arrow: []const u8 = if (rows < 0)
            (if (app) "\x1bOA" else "\x1b[A")
        else
            (if (app) "\x1bOB" else "\x1b[B");
        for (0..steps) |_| try w.writeAll(arrow);
    } else term.scrollViewport(.{ .delta = rows });
}

test "wheel routing" {
    const gpa = std.testing.allocator;
    var term: vt.Terminal = try .init(std.testing.io, gpa, .{ .cols = 20, .rows = 5 });
    defer term.deinit(gpa);
    var stream: vt.TerminalStream = .init(.{ .allocator = gpa, .handler = term.vtHandler() });
    defer stream.deinit();
    var buf: [256]u8 = undefined;

    // Primary screen: the scrollback moves, nothing is sent.
    for (0..20) |_| stream.nextSlice("x\r\n");
    var w: std.Io.Writer = .fixed(&buf);
    try encode(&term, &w, -3, 0, 0, .{});
    try std.testing.expectEqualStrings("", w.buffered());
    try std.testing.expect(!term.screens.active.viewportIsBottom());

    // Alternate screen: arrows, application form under DECCKM.
    term.scrollViewport(.bottom);
    stream.nextSlice("\x1b[?1049h");
    w = .fixed(&buf);
    try encode(&term, &w, -2, 0, 0, .{});
    try std.testing.expectEqualStrings("\x1b[A\x1b[A", w.buffered());
    stream.nextSlice("\x1b[?1h");
    w = .fixed(&buf);
    try encode(&term, &w, 1, 0, 0, .{});
    try std.testing.expectEqualStrings("\x1bOB", w.buffered());

    // Mouse reporting (SGR): wheel buttons 64/65 at the 1-based cell.
    stream.nextSlice("\x1b[?1000h\x1b[?1006h");
    w = .fixed(&buf);
    try encode(&term, &w, -1, 4, 2, .{});
    try encode(&term, &w, 1, 4, 2, .{});
    try std.testing.expectEqualStrings("\x1b[<64;5;3M\x1b[<65;5;3M", w.buffered());
}
