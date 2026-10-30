//! Builds the file tree from a directory on disk, ordered like Onyx:
//! folders first, then files, each in natural case-insensitive order.

const std = @import("std");
const AppState = @import("../state.zig").AppState;

const Entry = struct {
    name: []const u8,
    is_dir: bool,

    fn lessThan(_: void, a: Entry, b: Entry) bool {
        if (a.is_dir != b.is_dir) return a.is_dir;
        return naturalLess(a.name, b.name);
    }
};

/// Adds `path`'s children under `parent` (null = roots), recursing into folders.
pub fn addDir(s: *AppState, io: std.Io, path: []const u8, parent: ?u32) void {
    var dir = std.Io.Dir.openDir(.cwd(), io, path, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var entries: std.ArrayList(Entry) = .empty;
    var it = dir.iterate();
    while (it.next(io) catch null) |e| {
        if ((e.name[0] == '.' and !s.settings.show_hidden) or s.settings.excludes(e.name)) continue;
        const name = s.arena.dupe(u8, e.name) catch return;
        entries.append(s.arena, .{ .name = name, .is_dir = e.kind == .directory }) catch return;
    }
    std.mem.sort(Entry, entries.items, {}, Entry.lessThan);

    // Siblings first: the tree finds a node's children as a run of consecutive indices.
    const first = s.tree.node_count;
    for (entries.items) |e| {
        const child = std.fs.path.join(s.arena, &.{ path, e.name }) catch return;
        _ = s.add(parent, e.name, child, e.is_dir) orelse return;
    }
    for (entries.items, first..) |e, idx| {
        if (e.is_dir) addDir(s, io, s.paths[idx], @intCast(idx));
    }
}

/// Onyx's `natural_cmp`: digit runs compare by value, the rest case-insensitively.
fn naturalLess(a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len and j < b.len) {
        if (std.ascii.isDigit(a[i]) and std.ascii.isDigit(b[j])) {
            const na = digits(a[i..]);
            const nb = digits(b[j..]);
            const ta = std.mem.trimStart(u8, na, "0");
            const tb = std.mem.trimStart(u8, nb, "0");
            if (ta.len != tb.len) return ta.len < tb.len;
            switch (std.mem.order(u8, na, nb)) {
                .lt => return true,
                .gt => return false,
                .eq => {},
            }
            i += na.len;
            j += nb.len;
            continue;
        }
        const x = std.ascii.toLower(a[i]);
        const y = std.ascii.toLower(b[j]);
        if (x != y) return x < y;
        i += 1;
        j += 1;
    }
    return a.len - i < b.len - j;
}

fn digits(s: []const u8) []const u8 {
    var n: usize = 0;
    while (n < s.len and std.ascii.isDigit(s[n])) n += 1;
    return s[0..n];
}

test "natural order" {
    try std.testing.expect(naturalLess("Note 2", "Note 10"));
    try std.testing.expect(naturalLess("apple", "Banana"));
    try std.testing.expect(!naturalLess("b", "A"));
}
