//! Moves a file or folder to the Trash.

const objc = @import("objc");

/// True once `path` is in the Trash (Finder's Put Back keeps working).
pub fn move(path: [:0]const u8) bool {
    const NSString = objc.getClass("NSString") orelse return false;
    const NSURL = objc.getClass("NSURL") orelse return false;
    const NSFileManager = objc.getClass("NSFileManager") orelse return false;
    const string = NSString.msgSend(objc.c.id, "stringWithUTF8String:", .{path.ptr});
    const url = NSURL.msgSend(objc.c.id, "fileURLWithPath:", .{string});
    const manager = NSFileManager.msgSend(objc.Object, "defaultManager", .{});
    return manager.msgSend(bool, "trashItemAtURL:resultingItemURL:error:", .{ url, @as(?*anyopaque, null), @as(?*anyopaque, null) });
}
