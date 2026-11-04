//! Keeps the tree and the open tabs in step with the disk while other programs
//! (the terminal, an agent) change the opened folder. An FSEvents stream on the
//! folder flags what changed; the next frame rebuilds the tree when files came
//! or went, and reloads tabs whose file changed. A tab with unsaved edits keeps
//! them.

const std = @import("std");
const gooey = @import("gooey");
const AppState = @import("../state.zig").AppState;
const workspace = @import("workspace.zig");
const tabs = @import("../editor/tabs.zig");
const file_text = @import("../editor/file_text.zig");

/// Set on FSEvents' queue, taken on the main thread.
var tree_changed: std.atomic.Value(bool) = .init(false);
var files_changed: std.atomic.Value(bool) = .init(false);

var stream: ?FSEventStreamRef = null;
/// The folder watched, owned by `std.heap.page_allocator`.
var watched: []const u8 = "";
var window: ?*gooey.Window = null;

/// Each frame: watches the opened folder (again, after another was opened),
/// then applies what changed since the last frame.
pub fn sync(s: *AppState, g: *gooey.Window) void {
    window = g;
    const root: []const u8 = if (s.noFolder() or s.tree.node_count == 0) "" else s.paths[0];
    if (!std.mem.eql(u8, root, watched)) start(root);
    if (tree_changed.swap(false, .acq_rel)) workspace.refresh(s, g, "", "");
    if (files_changed.swap(false, .acq_rel)) reloadTabs(s, g);
}

fn start(root: []const u8) void {
    stop();
    const a = std.heap.page_allocator;
    watched = a.dupe(u8, root) catch return;
    if (root.len == 0) return;
    const path = a.dupeSentinel(u8, root, 0) catch return;
    defer a.free(path);
    const cf_path = CFStringCreateWithCString(null, path.ptr, kCFStringEncodingUTF8) orelse return;
    defer CFRelease(cf_path);
    var values = [_]?*const anyopaque{cf_path};
    const paths = CFArrayCreate(null, &values, 1, &kCFTypeArrayCallBacks) orelse return;
    defer CFRelease(paths);
    const s = FSEventStreamCreate(null, onEvents, null, paths, since_now, 0.15, flag_file_events | flag_no_defer) orelse return;
    FSEventStreamSetDispatchQueue(s, dispatch_get_global_queue(0, 0));
    if (!FSEventStreamStart(s)) {
        FSEventStreamInvalidate(s);
        FSEventStreamRelease(s);
        return;
    }
    stream = s;
}

fn stop() void {
    if (stream) |s| {
        FSEventStreamStop(s);
        FSEventStreamInvalidate(s);
        FSEventStreamRelease(s);
        stream = null;
    }
    if (watched.len > 0) std.heap.page_allocator.free(watched);
    watched = "";
}

/// On FSEvents' queue: what kind of change, then a frame to apply it.
fn onEvents(_: FSEventStreamRef, _: ?*anyopaque, n: usize, raw_paths: ?*anyopaque, flags: [*]const u32, _: [*]const u64) callconv(.c) void {
    const paths: [*]const [*:0]const u8 = @ptrCast(@alignCast(raw_paths orelse return));
    var any = false;
    for (0..n) |i| {
        if (ignored(std.mem.span(paths[i]))) continue;
        const f = flags[i];
        if (f & (item_created | item_removed | item_renamed | must_scan) != 0) tree_changed.store(true, .release);
        if (f & (item_modified | item_renamed | item_created | must_scan) != 0) files_changed.store(true, .release);
        any = true;
    }
    if (any) if (window) |g| if (g.platform_window) |pw| pw.requestRender();
}

/// Git's own bookkeeping changes on every command and never shows in the tree.
fn ignored(path: []const u8) bool {
    return std.mem.indexOf(u8, path, "/.git/") != null or std.mem.endsWith(u8, path, "/.git");
}

/// Tabs whose file changed on disk show its new text, keeping their cursor and
/// scroll; one with unsaved edits is left alone.
fn reloadTabs(s: *AppState, g: *gooey.Window) void {
    const a = std.heap.page_allocator;
    for (s.tabs.items()) |*t| {
        if (t.node == tabs.untitled or t.node >= s.tree.node_count or t.placeholder.len > 0) continue;
        const ce = tabs.editor(g, t.id());
        if (ce) |e| if (t.pending == null and !std.mem.eql(u8, e.getText(), t.file)) continue;
        const new = file_text.read(g.io, s.paths[t.node]);
        if (new.message.len > 0) continue;
        if (std.mem.eql(u8, new.bytes, t.file)) {
            a.free(new.bytes);
            continue;
        }
        const view: tabs.View = if (t.pending) |v| v else if (ce) |e| .{ .cursor = e.text_area.cursor_byte, .scroll_y = e.text_area.scroll_offset_y } else .{};
        if (t.file.len > 0) a.free(t.file);
        t.file = new.bytes;
        t.source = new.bytes;
        t.pending = view;
    }
    g.requestRender();
}

test "git bookkeeping is ignored" {
    try std.testing.expect(ignored("/p/.git/index.lock"));
    try std.testing.expect(ignored("/p/.git"));
    try std.testing.expect(!ignored("/p/src/main.zig"));
    try std.testing.expect(!ignored("/p/.gitignore"));
}

// FSEvents and the CoreFoundation it takes (CoreServices.framework).
const FSEventStreamRef = *opaque {};
const CFTypeRef = *const anyopaque;
const FSEventStreamCallback = *const fn (FSEventStreamRef, ?*anyopaque, usize, ?*anyopaque, [*]const u32, [*]const u64) callconv(.c) void;

const since_now: u64 = 0xFFFF_FFFF_FFFF_FFFF;
const kCFStringEncodingUTF8: u32 = 0x0800_0100;
const flag_no_defer: u32 = 0x02;
const flag_file_events: u32 = 0x10;
const must_scan: u32 = 0x01;
const item_created: u32 = 0x100;
const item_removed: u32 = 0x200;
const item_renamed: u32 = 0x800;
const item_modified: u32 = 0x1000;

extern const kCFTypeArrayCallBacks: anyopaque;
extern "c" fn CFStringCreateWithCString(alloc: ?*anyopaque, s: [*:0]const u8, encoding: u32) ?CFTypeRef;
extern "c" fn CFArrayCreate(alloc: ?*anyopaque, values: [*]?*const anyopaque, n: isize, callbacks: *const anyopaque) ?CFTypeRef;
extern "c" fn CFRelease(cf: CFTypeRef) void;
extern "c" fn FSEventStreamCreate(alloc: ?*anyopaque, cb: FSEventStreamCallback, ctx: ?*anyopaque, paths: CFTypeRef, since: u64, latency: f64, flags: u32) ?FSEventStreamRef;
extern "c" fn FSEventStreamSetDispatchQueue(s: FSEventStreamRef, q: ?*anyopaque) void;
extern "c" fn FSEventStreamStart(s: FSEventStreamRef) bool;
extern "c" fn FSEventStreamStop(s: FSEventStreamRef) void;
extern "c" fn FSEventStreamInvalidate(s: FSEventStreamRef) void;
extern "c" fn FSEventStreamRelease(s: FSEventStreamRef) void;
extern "c" fn dispatch_get_global_queue(identifier: isize, flags: usize) ?*anyopaque;
