//! The app's light/dark appearance (NSApp.appearance), which windows, menus
//! and panels inherit, and whether it is dark.
//!
//! `isDark` is read while rendering, off the main thread, so it is kept in an
//! atomic: `set` and views told their appearance changed
//! (`viewDidChangeEffectiveAppearance`, which also re-renders) update it on
//! the main thread. An app following the system thus sees a switch at once.

const std = @import("std");
const objc = @import("objc");

var dark = std.atomic.Value(bool).init(false);

/// Forces light (false) or dark (true); null follows the system. Main thread.
pub fn set(mode: ?bool) void {
    const value: ?*anyopaque = if (mode) |d| named(if (d) "NSAppearanceNameDarkAqua" else "NSAppearanceNameAqua") else null;
    app().msgSend(void, "setAppearance:", .{value});
    update(app());
}

/// The app's effective appearance is dark (the system's while `set(null)`).
pub fn isDark() bool {
    return dark.load(.monotonic);
}

/// Re-reads `object`'s effective appearance (NSApp, or a view); main thread.
pub fn update(object: objc.Object) void {
    dark.store(readDark(object), .monotonic);
}

fn readDark(object: objc.Object) bool {
    const appearance = object.msgSend(?*anyopaque, "effectiveAppearance", .{}) orelse return false;
    const name = objc.Object.fromId(appearance).msgSend(?*anyopaque, "name", .{}) orelse return false;
    const utf8 = objc.Object.fromId(name).msgSend(?[*:0]const u8, "UTF8String", .{}) orelse return false;
    return std.mem.indexOf(u8, std.mem.span(utf8), "Dark") != null;
}

fn named(name: [:0]const u8) ?*anyopaque {
    const NSAppearance = objc.getClass("NSAppearance") orelse return null;
    const NSString = objc.getClass("NSString") orelse return null;
    const ns_name = NSString.msgSend(objc.Object, "stringWithUTF8String:", .{name.ptr});
    return NSAppearance.msgSend(?*anyopaque, "appearanceNamed:", .{ns_name.value});
}

fn app() objc.Object {
    const NSApplication = objc.getClass("NSApplication").?;
    return NSApplication.msgSend(objc.Object, "sharedApplication", .{});
}
