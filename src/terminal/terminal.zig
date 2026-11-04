//! The terminal below the editor container (⌘J). Each tab has its own,
//! kept while the tab is hidden and ended with it; with no tab open there is
//! one more. The shell starts in the opened folder the first time the panel
//! shows; `exit` closes the panel, and so does its × (keeping the shell).
//! Drag the divider above it to resize.

const std = @import("std");
const gooey = @import("gooey");
const theme = @import("../theme.zig");
const AppState = @import("../state.zig").AppState;
const Session = @import("term_session.zig").Session;
const term_keys = @import("term_keys.zig");
const term_wheel = @import("term_wheel.zig");
const term_select = @import("term_select.zig");
const view = @import("term_view.zig");

pub const Toggle = struct {};

pub const Slot = struct {
    session: ?*Session = null,
    open: bool = false,
};

/// The panel's state in `AppState.term`.
pub const Panel = struct {
    /// The terminal with no tab open (each tab has its own).
    bare: Slot = .{},
    /// Keys go to the shown terminal.
    focus: bool = false,
    height: f32 = 260,
    /// Where the terminal was drawn, and whether the gap above it is being dragged.
    rect: Rect = .{},
    drag: bool = false,
    /// A mouse selection is being dragged.
    selecting: bool = false,
};

pub const min_height: f32 = 80;
/// The editor keeps at least this much of the panel.
const min_editor: f32 = 120;

/// Where the panel was last drawn, in window points (for clicks and the wheel).
pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    fn contains(r: Rect, p: gooey.core.Point(f64)) bool {
        const x: f32 = @floatCast(p.x);
        const y: f32 = @floatCast(p.y);
        return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h;
    }
};

/// The window output is drawn in; the reader threads ask it to render.
var window: ?*gooey.Window = null;
/// Wheel deltas below a row, carried to the next event.
var scroll_rest: f32 = 0;

pub fn init(g: *gooey.Window) void {
    window = g;
}

/// The shown tab's slot.
pub fn slot(s: *AppState) *Slot {
    return if (s.tabs.active()) |t| &t.term else &s.term.bare;
}

/// The shown tab's terminal, while its panel is open.
pub fn shown(s: *AppState) ?*Session {
    const sl = slot(s);
    return if (sl.open) sl.session else null;
}

/// ⌘J: opens the panel and focuses it; focuses it if it is open but not
/// focused; else closes it and gives the editor the focus back.
pub fn toggle(s: *AppState, g: *gooey.Window) void {
    const sl = slot(s);
    if (sl.open and s.term.focus) {
        sl.open = false;
        blur(s);
    } else {
        sl.open = true;
        s.term.focus = true;
        g.blurAll();
    }
    g.requestRender();
}

/// The panel's ×: hides it like ⌘J; the shell keeps running.
pub fn close(s: *AppState, g: *gooey.Window) void {
    slot(s).open = false;
    blur(s);
    g.requestRender();
}

fn blur(s: *AppState) void {
    s.term.focus = false;
    s.tabs.focus = true;
}

pub fn end(sl: *Slot) void {
    if (sl.session) |t| t.end();
    sl.* = .{};
}

/// The shown terminal at `cols` × `rows`, started the first time; null once
/// its shell has exited (the panel then closes). Called by the view.
pub fn ensure(s: *AppState, g: *gooey.Window, cols: u16, rows: u16) ?*Session {
    const sl = slot(s);
    if (sl.session) |t| {
        if (t.exited.load(.acquire)) {
            end(sl);
            blur(s);
            g.requestRender();
            return null;
        }
        t.resize(cols, rows, @intFromFloat(s.cell_w), @intFromFloat(s.cell_h));
        return t;
    }
    const cwd = s.arena.dupeSentinel(u8, if (s.noFolder()) "." else s.paths[0], 0) catch return null;
    sl.session = Session.start(std.heap.smp_allocator, g.io, cwd, cols, rows, onOutput) catch null;
    return sl.session;
}

fn onOutput(_: *Session) void {
    if (window) |g| if (g.platform_window) |pw| pw.requestRender();
}

/// The divider above the panel, which resizes it.
pub fn divider(s: *const AppState) Rect {
    const r = s.term.rect;
    return .{ .x = r.x, .y = r.y - theme.inset, .w = r.w, .h = theme.inset };
}

/// The pointer from the grid's top-left.
fn at(s: *const AppState, p: gooey.core.Point(f64)) term_select.At {
    const r = s.term.rect;
    return .{ .x = p.x - r.x - view.grid_x, .y = p.y - r.y - view.grid_y, .cell_w = s.cell_w, .cell_h = s.cell_h };
}

/// Its part of `Window.key_capture`: a click in the panel focuses it (one
/// elsewhere blurs it) and a drag selects (`term_select`), the divider above it
/// resizes it, the wheel scrolls (`term_wheel`), and while focused the keys go
/// to the shell (⌘ shortcuts pass but ⌘C copies, ⌘V pastes, and ⌘⌫ ⌘← ⌘→ edit
/// the line as in Terminal.app).
pub fn capture(s: *AppState, g: *gooey.Window, event: gooey.input.InputEvent) bool {
    const r = s.term.rect;
    const open = shown(s) != null;
    switch (event) {
        .mouse_down => |m| {
            if (open and divider(s).contains(m.position)) {
                s.term.drag = true;
                return true;
            }
            if (open and r.contains(m.position)) {
                s.term.focus = true;
                g.blurAll();
                g.requestRender();
                // The header's × takes its own click.
                if (m.position.y < r.y + view.grid_y) return false;
                const t = shown(s).?;
                if (m.button == .left and term_select.selects(t, m.modifiers.shift)) {
                    term_select.press(t, at(s, m.position));
                    s.term.selecting = true;
                }
                return true;
            }
            if (s.term.focus) blur(s);
            return false;
        },
        .mouse_dragged => |m| {
            if (s.term.drag) {
                const bottom = r.y + r.h;
                const top = theme.titlebar_height + min_editor + theme.inset;
                s.term.height = std.math.clamp(bottom - @as(f32, @floatCast(m.position.y)), min_height, @max(min_height, bottom - top));
                g.requestRender();
                return true;
            }
            if (s.term.selecting) if (shown(s)) |t| {
                term_select.drag(t, at(s, m.position));
                g.requestRender();
                return true;
            };
        },
        .mouse_up => |m| {
            if (s.term.drag) {
                s.term.drag = false;
                return true;
            }
            if (s.term.selecting) {
                s.term.selecting = false;
                if (shown(s)) |t| term_select.release(t, at(s, m.position));
                g.requestRender();
                return true;
            }
        },
        .scroll => |e| if (open and r.contains(e.position)) {
            scroll_rest -= @as(f32, @floatCast(e.delta.y)) / s.cell_h;
            const rows: isize = @intFromFloat(scroll_rest);
            scroll_rest -= @floatFromInt(rows);
            if (rows != 0) {
                // The cell under the pointer, inside the border and padding.
                const p = at(s, e.position);
                const col = @as(f32, @floatCast(p.x)) / s.cell_w;
                const row = @as(f32, @floatCast(p.y)) / s.cell_h;
                const m = e.modifiers;
                term_wheel.scroll(shown(s).?, rows, @intFromFloat(@max(0, col)), @intFromFloat(@max(0, row)), .{ .shift = m.shift, .ctrl = m.ctrl, .alt = m.alt });
            }
            g.requestRender();
            return true;
        },
        .key_down => |k| if (s.term.focus) if (shown(s)) |t| {
            if (k.key == .j and k.modifiers.cmd) {
                toggle(s, g);
                return true;
            }
            if (k.modifiers.cmd) {
                switch (k.key) {
                    .v => term_keys.paste(t),
                    .c => if (!term_select.copy(t)) return false,
                    // The line editing Terminal.app and Ghostty give ⌘: kill to
                    // the line's start, go to its start or end.
                    .delete => t.write("\x15"),
                    .left => t.write("\x01"),
                    .right => t.write("\x05"),
                    else => return false,
                }
                g.requestRender();
                return true;
            }
            term_keys.press(t, k);
            return true;
        },
        .text_input => |ti| if (s.term.focus) if (shown(s)) |t| {
            t.write(ti.text);
            return true;
        },
        else => {},
    }
    return false;
}
