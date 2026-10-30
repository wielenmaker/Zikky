//! Fills the file tree from disk a folder at a time, ordered like Onyx:
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

/// Reads folder `node`'s children into the tree, not theirs: folders load when
/// first shown, so a big folder elsewhere can't fill the tree. Added together,
/// they are the run of consecutive indices the tree finds children by.
pub fn load(s: *AppState, io: std.Io, node: u32) void {
    const n = s.tree.nodes[node];
    if (!n.is_folder or n.child_count > 0) return;
    // The opened folder's children keep `root`'s spelling, for `relativePath`.
    const path = if (node == 0) s.root else s.paths[node];
    var dir = std.Io.Dir.openDir(.cwd(), io, path, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var entries: std.ArrayList(Entry) = .empty;
    var it = dir.iterate();
    while (it.next(io) catch null) |e| {
        if (skips(s, e.name)) continue;
        const name = s.arena.dupe(u8, e.name) catch return;
        entries.append(s.arena, .{ .name = name, .is_dir = e.kind == .directory }) catch return;
    }
    std.mem.sort(Entry, entries.items, {}, Entry.lessThan);

    for (entries.items) |e| {
        const full = std.fs.path.join(s.arena, &.{ path, e.name }) catch return;
        _ = s.add(node, e.name, full, e.is_dir) orelse return;
    }
}

/// Loads and expands folder `node`.
pub fn expand(s: *AppState, io: std.Io, node: u32) void {
    load(s, io, node);
    s.tree.expandNode(node);
}

/// The node at `rel` (a path from the opened folder), loading the folders on the way.
pub fn find(s: *AppState, io: std.Io, rel: []const u8) ?u32 {
    var node: u32 = 0;
    var it = std.mem.tokenizeScalar(u8, rel, '/');
    while (it.next()) |name| {
        load(s, io, node);
        node = child(s, node, name) orelse return null;
    }
    return node;
}

fn child(s: *const AppState, parent: u32, name: []const u8) ?u32 {
    const p = s.tree.nodes[parent];
    const first = p.first_child orelse return null;
    for (first..first + p.child_count) |i| if (std.mem.eql(u8, s.names[i], name)) return @intCast(i);
    return null;
}

/// Hidden or excluded names stay out of the tree and quick open.
pub fn skips(s: *const AppState, name: []const u8) bool {
    return (name[0] == '.' and !s.settings.show_hidden) or s.settings.excludes(name);
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
