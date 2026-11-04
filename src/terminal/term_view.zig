//! The terminal panel: a rounded container like the editor's, a header with
//! its × on top, the shown tab's terminal drawn below as rows of styled text
//! runs in the editor's font. Each run is as wide as its cells, so the grid
//! stays aligned; selected cells are runs of their own.

const std = @import("std");
const gooey = @import("gooey");
const vt = @import("ghostty-vt");
const theme = @import("../theme.zig");
const AppState = @import("../state.zig").AppState;
const terminal = @import("terminal.zig");
const Session = @import("term_session.zig").Session;

const components = @import("gooey-components");
const IconButton = @import("../ui/icon_button.zig").IconButton;

const ui = gooey.ui;
const Cx = gooey.Cx;
const Color = gooey.Color;

const CursorShape = @FieldType(vt.RenderState.Cursor, "visual_style");

pub const pad_x: f32 = 12;
pub const pad_y: f32 = 8;
/// The header row above the grid.
pub const header_h: f32 = 30;
/// The grid's top-left from the panel's, inside its border and header.
pub const grid_x: f32 = 1 + pad_x;
pub const grid_y: f32 = 1 + header_h;

/// A row's stretch of cells in one style.
const Run = struct {
    text_start: u32,
    text_end: u32,
    cols: u16,
    fg: Color,
    bg: ?Color,
    underline: bool,
    strike: bool,
    selected: bool,
};

/// This frame's text and runs (one terminal is drawn at a time); the UI
/// borrows slices of them until the next frame.
var text: std.ArrayList(u8) = .empty;
var runs: std.ArrayList(Run) = .empty;
var row_ends: std.ArrayList(u32) = .empty;

pub const TermPanel = struct {
    width: f32,
    height: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        const c = theme.color;
        const cols: u16 = @intFromFloat(@max(2, @floor((self.width - 2 * pad_x - 2) / s.cell_w)));
        const rows: u16 = @intFromFloat(@max(1, @floor((self.height - header_h - pad_y - 2) / s.cell_h)));
        const t = terminal.ensure(s, cx.window(), cols, rows);
        if (t) |session| {
            session.snapshot();
            build(session) catch {};
        }
        const focused = s.term.focus;
        cx.render(ui.box(.{
            .width = self.width,
            .height = self.height,
            .background = c.background,
            .corner_radius = theme.radius_lg,
            .border_width = .{ .all = 1 },
            .border_color = if (focused) c.primary.withAlpha(0.35) else c.border.withAlpha(0.8),
            .shadow = theme.shadow_xs,
            .padding = .{ .each = .{ .top = 0, .right = pad_x - 6, .bottom = pad_y, .left = pad_x } },
        }, .{
            Header{},
            ui.when(t != null, .{Grid{ .session = t orelse undefined }}),
        }));
    }
};

/// "Terminal" and the × that closes the panel (the shell keeps running, like ⌘J).
const Header = struct {
    pub fn render(_: @This(), cx: *Cx) void {
        cx.render(ui.box(.{
            .height = header_h,
            .fill_width = true,
            .direction = .row,
            .alignment = .{ .main = .space_between, .cross = .center },
        }, .{
            ui.text("Terminal", .{ .size = 12, .color = theme.color.muted, .weight = .medium }),
            IconButton{ .icon = components.Lucide.x, .icon_size = 14, .on_click = cx.command(terminal.close) },
        }));
    }
};

const Grid = struct {
    session: *Session,

    pub fn render(self: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        // The I-beam over the text, which can be selected.
        cx.render(ui.box(.{ .cursor = .text }, .{Rows{}}));
        const cur = &self.session.render.cursor;
        if (cur.visible) if (cur.viewport) |v| cx.render(Cursor{
            .x = @as(f32, @floatFromInt(v.x - @intFromBool(v.wide_tail))) * s.cell_w,
            .y = @as(f32, @floatFromInt(v.y)) * s.cell_h,
            .cell_w = s.cell_w,
            .cell_h = s.cell_h,
            .style = cur.visual_style,
            .focused = s.term.focus,
        });
    }
};

const Rows = struct {
    pub fn render(_: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        var start: u32 = 0;
        for (row_ends.items) |end| {
            cx.render(Row{ .runs = runs.items[start..end], .cell_w = s.cell_w, .cell_h = s.cell_h, .size = s.settings.font_size });
            start = end;
        }
    }
};

const Row = struct {
    runs: []const Run,
    cell_w: f32,
    cell_h: f32,
    size: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(ui.box(.{ .direction = .row, .height = self.cell_h }, .{Runs{ .row = self }}));
    }
};

const Runs = struct {
    row: Row,

    pub fn render(self: @This(), cx: *Cx) void {
        const r = self.row;
        for (r.runs) |run| cx.render(ui.box(.{
            .width = @as(f32, @floatFromInt(run.cols)) * r.cell_w,
            .height = r.cell_h,
            .background = run.bg orelse Color.transparent,
            .alignment = .{ .cross = .center },
            .direction = .row,
        }, .{ui.text(text.items[run.text_start..run.text_end], .{
            .size = @intFromFloat(r.size),
            .color = run.fg,
            .mono = true,
            .underline = run.underline,
            .strikethrough = run.strike,
        })}));
    }
};

const Cursor = struct {
    x: f32,
    y: f32,
    cell_w: f32,
    cell_h: f32,
    style: CursorShape,
    focused: bool,

    pub fn render(self: @This(), cx: *Cx) void {
        const color = theme.color.primary;
        const block = self.style == .block or self.style == .block_hollow;
        const hollow = !self.focused or self.style == .block_hollow;
        cx.render(ui.box(.{
            .width = if (self.style == .bar) 2 else self.cell_w,
            .height = if (self.style == .underline) 2 else self.cell_h,
            .background = if (block and hollow) Color.transparent else color.withAlpha(if (block) 0.45 else 1),
            .border_width = .{ .all = if (block and hollow) 1 else 0 },
            .border_color = color,
            .pointer_events = .none,
            // Offsets count from the container's edge, not inside its padding.
            .floating = .{
                .offset_x = grid_x + self.x,
                .offset_y = grid_y + self.y + if (self.style == .underline) self.cell_h - 2 else 0,
                .z_index = 1,
            },
        }, .{}));
    }
};

/// Splits each row of the session's render state into runs of one style.
fn build(t: *Session) !void {
    const a = std.heap.page_allocator;
    const rs = &t.render;
    text.clearRetainingCapacity();
    runs.clearRetainingCapacity();
    row_ends.clearRetainingCapacity();
    // Reserved up front: the UI holds slices of `text`, which must not move.
    try text.ensureTotalCapacity(a, @as(usize, rs.rows) * rs.cols * 8 + 64);
    try runs.ensureTotalCapacity(a, @as(usize, rs.rows) * rs.cols);
    try row_ends.ensureTotalCapacity(a, rs.rows);

    const rows = rs.row_data.slice();
    const all_cells = rows.items(.cells);
    const all_sels = rows.items(.selection);
    for (0..rs.rows) |y| {
        const cells = all_cells[y].slice();
        const raws = cells.items(.raw);
        const styles = cells.items(.style);
        const graphemes = cells.items(.grapheme);
        const sel = all_sels[y];
        var current: ?Run = null;
        for (raws, styles, graphemes, 0..) |raw, cell_style, cell_extra, x| {
            if (raw.wide == .spacer_tail or raw.wide == .spacer_head) continue;
            // Both are undefined unless the cell has a style or a grapheme.
            const style: vt.Style = if (raw.style_id != 0) cell_style else .{};
            const extra: []const u21 = if (raw.content_tag == .codepoint_grapheme) cell_extra else &.{};
            const selected = if (sel) |r| x >= r[0] and x <= r[1] else false;
            var colors = cellColors(&style, &raw, rs);
            if (selected) colors.bg = theme.color.primary.withAlpha(0.28);
            const width: u16 = if (raw.wide == .wide) 2 else 1;
            if (current) |*run| {
                if (run.selected != selected or !sameLook(run.*, colors, style)) {
                    runs.appendAssumeCapacity(run.*);
                    current = null;
                }
            }
            if (current == null) current = .{
                .text_start = @intCast(text.items.len),
                .text_end = @intCast(text.items.len),
                .cols = 0,
                .fg = colors.fg,
                .bg = colors.bg,
                .underline = style.flags.underline != .none,
                .strike = style.flags.strikethrough,
                .selected = selected,
            };
            const run = &current.?;
            const cp = raw.codepoint();
            appendCodepoint(if (cp == 0 or style.flags.invisible) ' ' else cp);
            if (!style.flags.invisible) for (extra) |e| appendCodepoint(e);
            run.cols += width;
            run.text_end = @intCast(text.items.len);
        }
        if (current) |run| runs.appendAssumeCapacity(run);
        row_ends.appendAssumeCapacity(@intCast(runs.items.len));
    }
}

fn appendCodepoint(cp: u21) void {
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &buf) catch return;
    text.appendSliceAssumeCapacity(buf[0..n]);
}

fn sameLook(run: Run, colors: Colors, style: vt.Style) bool {
    return eql(run.fg, colors.fg) and
        (run.bg == null) == (colors.bg == null) and (run.bg == null or eql(run.bg.?, colors.bg.?)) and
        run.underline == (style.flags.underline != .none) and run.strike == style.flags.strikethrough;
}

fn eql(a: Color, b: Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

const Colors = struct { fg: Color, bg: ?Color };

/// The cell's colors: palette entries 0–15 from the theme (readable on its
/// background), the rest as the terminal has them; inverse swaps, faint dims.
fn cellColors(style: *const vt.Style, raw: *const vt.Cell, rs: *const vt.RenderState) Colors {
    const c = theme.color;
    var fg: Color = switch (style.fg_color) {
        .none => c.foreground,
        .palette => |i| paletteColor(i, rs),
        .rgb => |v| rgb(v),
    };
    var bg: ?Color = switch (raw.content_tag) {
        .bg_color_palette => paletteColor(raw.content.color_palette.data, rs),
        .bg_color_rgb => rgb(.{ .r = raw.content.color_rgb.r, .g = raw.content.color_rgb.g, .b = raw.content.color_rgb.b }),
        else => switch (style.bg_color) {
            .none => null,
            .palette => |i| paletteColor(i, rs),
            .rgb => |v| rgb(v),
        },
    };
    if (style.flags.inverse) {
        const back = bg orelse c.background;
        bg = fg;
        fg = back;
    }
    if (style.flags.faint) fg = fg.withAlpha(0.55);
    return .{ .fg = fg, .bg = bg };
}

fn paletteColor(i: u8, rs: *const vt.RenderState) Color {
    if (i < 16) return theme.color.ansi[i];
    return rgb(rs.colors.palette[i]);
}

fn rgb(v: vt.color.RGB) Color {
    return Color.rgba(@as(f32, @floatFromInt(v.r)) / 255, @as(f32, @floatFromInt(v.g)) / 255, @as(f32, @floatFromInt(v.b)) / 255, 1);
}
