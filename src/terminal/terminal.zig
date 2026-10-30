//! The terminal below the editor container (⌘J). Each tab has its own,
//! kept while the tab is hidden and ended with it; with no tab open there is
//! one more. The shell starts in the opened folder the first time the panel
//! shows; `exit` closes the panel. Drag the gap above it to resize.

const std = @import("std");
const gooey = @import("gooey");
const theme = @import("../theme.zig");
const AppState = @import("../state.zig").AppState;
const Session = @import("term_session.zig").Session;
const term_keys = @import("term_keys.zig");

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

pub fn bindKeys(g: *gooey.Window) void {
    window = g;
    g.keymap().bind(Toggle, "cmd-j", null);
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
    const cwd = s.arena.dupeSentinel(u8, s.paths[0], 0) catch return null;
    sl.session = Session.start(std.heap.smp_allocator, g.io, cwd, cols, rows, onOutput) catch null;
    return sl.session;
}

fn onOutput(_: *Session) void {
    if (window) |g| if (g.platform_window) |pw| pw.requestRender();
}

/// Its part of `Window.key_capture`: a click in the panel focuses it (one
/// elsewhere blurs it), the gap above it resizes it, the wheel scrolls
/// back, and while focused the keys go to the shell (⌘ shortcuts pass, ⌘V
/// pastes).
pub fn capture(s: *AppState, g: *gooey.Window, event: gooey.input.InputEvent) bool {
    const r = s.term.rect;
    const open = shown(s) != null;
    switch (event) {
        .mouse_down => |m| {
            const divider = Rect{ .x = r.x, .y = r.y - theme.inset, .w = r.w, .h = theme.inset };
            if (open and divider.contains(m.position)) {
                s.term.drag = true;
                return true;
            }
            if (open and r.contains(m.position)) {
                s.term.focus = true;
                g.blurAll();
                g.requestRender();
                return true;
            }
            if (s.term.focus) blur(s);
            return false;
        },
        .mouse_dragged => |m| if (s.term.drag) {
            const bottom = r.y + r.h;
            const top = theme.titlebar_height + min_editor + theme.inset;
            s.term.height = std.math.clamp(bottom - @as(f32, @floatCast(m.position.y)), min_height, @max(min_height, bottom - top));
            g.requestRender();
            return true;
        },
        .mouse_up => if (s.term.drag) {
            s.term.drag = false;
            return true;
        },
        .scroll => |e| if (open and r.contains(e.position)) {
            scroll_rest -= @as(f32, @floatCast(e.delta.y)) / s.cell_h;
            const rows: isize = @intFromFloat(scroll_rest);
            scroll_rest -= @floatFromInt(rows);
            if (rows != 0) shown(s).?.scroll(rows);
            g.requestRender();
            return true;
        },
        .key_down => |k| if (s.term.focus) if (shown(s)) |t| {
            if (k.key == .j and k.modifiers.cmd) {
                toggle(s, g);
                return true;
            }
            if (k.modifiers.cmd) {
                if (k.key != .v) return false;
                term_keys.paste(t);
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
