//! One terminal: a login shell on a pty and Ghostty's terminal state
//! (libghostty-vt), which a reader thread feeds with the shell's output.
//! The state is shared with rendering under `mutex`; replies the terminal
//! owes the shell (cursor reports, device attributes…) go straight back.

const std = @import("std");
const vt = @import("ghostty-vt");
const Pty = @import("pty.zig").Pty;

const c = std.c;

pub const Session = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    pty: Pty,
    terminal: vt.Terminal,
    stream: vt.TerminalStream,
    mutex: std.Io.Mutex = .init,
    thread: std.Thread = undefined,
    /// Written to wake the reader thread when the session closes.
    wake: [2]c_int = .{ -1, -1 },
    /// The shell has exited (or its pty closed).
    exited: std.atomic.Value(bool) = .init(false),
    /// Called (on the reader thread) after output changed the terminal.
    on_output: *const fn (*Session) void,
    cols: u16,
    rows: u16,
    /// What the view draws; updated from `terminal` while rendering.
    render: vt.RenderState = .empty,

    /// Starts a shell in `cwd`. The session is heap-allocated: the reader
    /// thread and the terminal's write-back callback point into it.
    pub fn start(gpa: std.mem.Allocator, io: std.Io, cwd: [:0]const u8, cols: u16, rows: u16, on_output: *const fn (*Session) void) !*Session {
        const self = try gpa.create(Session);
        errdefer gpa.destroy(self);
        self.* = .{
            .gpa = gpa,
            .io = io,
            .pty = undefined,
            .terminal = try .init(io, gpa, .{ .cols = cols, .rows = rows, .max_scrollback_bytes = 8 << 20 }),
            .stream = undefined,
            .on_output = on_output,
            .cols = cols,
            .rows = rows,
        };
        errdefer self.terminal.deinit(gpa);
        var handler = self.terminal.vtHandler();
        handler.effects.write_pty = writePty;
        self.stream = .init(.{ .allocator = gpa, .handler = handler });
        errdefer self.stream.deinit();
        if (c.pipe(&self.wake) != 0) return error.PipeFailed;
        self.pty = try Pty.spawn(cwd, cols, rows);
        self.thread = try std.Thread.spawn(.{}, readLoop, .{self});
        return self;
    }

    /// Hangs up on the shell, stops the reader and frees everything.
    pub fn end(self: *Session) void {
        _ = c.write(self.wake[1], "x", 1);
        self.thread.join();
        self.pty.hangUp();
        _ = closeFd(self.wake[0]);
        _ = closeFd(self.wake[1]);
        self.render.deinit(self.gpa);
        self.stream.deinit();
        self.terminal.deinit(self.gpa);
        self.gpa.destroy(self);
    }

    /// Keys and pastes for the shell.
    pub fn write(self: *Session, bytes: []const u8) void {
        if (self.exited.load(.acquire)) return;
        // Typing brings a scrolled-back view to the bottom, like Ghostty.
        self.lock();
        self.terminal.scrollViewport(.bottom);
        self.unlock();
        self.pty.write(bytes);
    }

    pub fn resize(self: *Session, cols: u16, rows: u16, cell_w: u16, cell_h: u16) void {
        if (cols == self.cols and rows == self.rows) return;
        self.cols = cols;
        self.rows = rows;
        self.lock();
        self.terminal.resize(self.gpa, .{ .cols = cols, .rows = rows, .cell_size_px = .{ .width = cell_w, .height = cell_h } }) catch {};
        self.unlock();
        self.pty.resize(cols, rows, cell_w, cell_h);
    }

    /// Scrolls through the scrollback by `rows` (up is negative).
    pub fn scroll(self: *Session, rows: isize) void {
        self.lock();
        defer self.unlock();
        self.terminal.scrollViewport(.{ .delta = rows });
    }

    /// Brings `render` up to date with the terminal.
    pub fn snapshot(self: *Session) void {
        self.lock();
        defer self.unlock();
        self.render.update(self.gpa, &self.terminal) catch {};
    }

    pub fn lock(self: *Session) void {
        self.mutex.lockUncancelable(self.io);
    }

    pub fn unlock(self: *Session) void {
        self.mutex.unlock(self.io);
    }

    fn readLoop(self: *Session) void {
        var buf: [16 * 1024]u8 = undefined;
        while (true) {
            var fds = [_]c.pollfd{
                .{ .fd = self.pty.fd, .events = c.POLL.IN, .revents = 0 },
                .{ .fd = self.wake[0], .events = c.POLL.IN, .revents = 0 },
            };
            if (c.poll(&fds, fds.len, -1) < 0) continue;
            if (fds[1].revents != 0) return;
            const n = self.pty.read(&buf);
            if (n == 0) break;
            self.lock();
            self.stream.nextSlice(buf[0..n]);
            self.unlock();
            self.on_output(self);
        }
        self.exited.store(true, .release);
        self.on_output(self);
    }

    /// The terminal's replies to the shell (`Handler.effects.write_pty`),
    /// written from the reader thread while it holds the lock.
    fn writePty(handler: *vt.TerminalStream.Handler, bytes: []const u8) void {
        const stream: *vt.TerminalStream = @fieldParentPtr("handler", handler);
        const self: *Session = @fieldParentPtr("stream", stream);
        self.pty.write(bytes);
    }
};

extern "c" fn close(fd: c_int) c_int;

fn closeFd(fd: c_int) c_int {
    return close(fd);
}
