//! A login shell on a pseudo-terminal: `forkpty`, its size, reads and writes.

const std = @import("std");
const c = std.c;

extern "c" fn forkpty(master: *c_int, name: ?[*]u8, termp: ?*anyopaque, winp: ?*const std.posix.winsize) c_int;
extern "c" fn ioctl(fd: c_int, request: c_int, ...) c_int;
extern "c" fn close(fd: c_int) c_int;

/// `TIOCSWINSZ` on macOS.
const set_window_size: c_int = @bitCast(@as(u32, 0x80087467));

pub const Pty = struct {
    fd: c_int,
    pid: c.pid_t,

    /// Starts `$SHELL` (else zsh) as a login shell in `cwd`, with TERM set
    /// for Ghostty's xterm-compatible terminal.
    pub fn spawn(cwd: [:0]const u8, cols: u16, rows: u16) !Pty {
        // Everything the child needs is built before the fork: only
        // async-signal-safe calls (chdir, execve, _exit) may follow it.
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const shell: [*:0]const u8 = c.getenv("SHELL") orelse "/bin/zsh";
        const base = std.fs.path.basename(std.mem.span(shell));
        const argv0 = try std.fmt.allocPrintSentinel(a, "-{s}", .{base}, 0);
        const argv = [_:null]?[*:0]const u8{argv0};

        var env: std.ArrayList(?[*:0]const u8) = .empty;
        const set = [_][:0]const u8{ "TERM=xterm-256color", "COLORTERM=truecolor", "TERM_PROGRAM=Slate" };
        var i: usize = 0;
        while (c.environ[i]) |entry| : (i += 1) {
            const e = std.mem.span(entry);
            const replaced = for (set) |s| {
                const name = s[0 .. std.mem.indexOfScalar(u8, s, '=').? + 1];
                if (std.mem.startsWith(u8, e, name)) break true;
            } else false;
            if (!replaced) try env.append(a, entry);
        }
        for (set) |s| try env.append(a, s.ptr);
        try env.append(a, null);
        const envp: [*:null]const ?[*:0]const u8 = @ptrCast(env.items.ptr);

        var size = std.posix.winsize{ .row = rows, .col = cols, .xpixel = 0, .ypixel = 0 };
        var fd: c_int = -1;
        const pid = forkpty(&fd, null, null, &size);
        if (pid < 0) return error.ForkPtyFailed;
        if (pid == 0) {
            _ = c.chdir(cwd.ptr);
            _ = c.execve(shell, &argv, envp);
            c._exit(127);
        }
        return .{ .fd = fd, .pid = pid };
    }

    /// Bytes from the shell; 0 once it has exited.
    pub fn read(self: Pty, buf: []u8) usize {
        while (true) {
            const n = c.read(self.fd, buf.ptr, buf.len);
            if (n >= 0) return @intCast(n);
            if (std.posix.errno(n) != .INTR) return 0;
        }
    }

    pub fn write(self: Pty, bytes: []const u8) void {
        var rest = bytes;
        while (rest.len > 0) {
            const n = c.write(self.fd, rest.ptr, rest.len);
            if (n < 0) {
                if (std.posix.errno(n) == .INTR or std.posix.errno(n) == .AGAIN) continue;
                return;
            }
            rest = rest[@intCast(n)..];
        }
    }

    pub fn resize(self: Pty, cols: u16, rows: u16, cell_w: u16, cell_h: u16) void {
        const size = std.posix.winsize{ .row = rows, .col = cols, .xpixel = cols *| cell_w, .ypixel = rows *| cell_h };
        _ = ioctl(self.fd, set_window_size, &size);
    }

    /// Hangs up on the shell (killing it if it lingers) and reaps it.
    pub fn hangUp(self: Pty) void {
        _ = c.kill(self.pid, .HUP);
        _ = close(self.fd);
        if (c.waitpid(self.pid, null, 1) == 0) { // WNOHANG
            _ = c.kill(self.pid, .KILL);
            _ = c.waitpid(self.pid, null, 0);
        }
    }
};
