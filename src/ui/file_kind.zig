//! File kinds for the tree: an icon and a color per type, and whether the
//! label is greyed. Popular languages and formats get their mark
//! (`file_marks.zig`); other kinds a Lucide outline in a muted color. Like
//! Onyx, files you don't edit (images, archives, lockfiles…) get a muted
//! label; text and code stay prominent.

const std = @import("std");
const Lucide = @import("gooey-components").Lucide;
const Color = @import("gooey").Color;
const marks = @import("file_marks.zig");

pub const Kind = struct {
    icon: []const u8,
    color: Color,
    /// `icon` is a filled mark on a 16-unit grid, not a Lucide outline.
    mark: bool = false,
    /// Grey the label, like Onyx does for files that aren't notes.
    dim: bool = false,
    /// Lowercase extensions (no dot) or exact file names.
    exts: []const []const u8 = &.{},
    names: []const []const u8 = &.{},
};

fn mark(m: marks.Mark, exts: []const []const u8, names: []const []const u8) Kind {
    return .{ .icon = m.path, .color = Color.hex(m.color), .mark = true, .exts = exts, .names = names };
}

const kinds = [_]Kind{
    mark(marks.zig, &.{ "zig", "zon" }, &.{}),
    mark(marks.rust, &.{"rs"}, &.{}),
    mark(marks.go, &.{"go"}, &.{ "go.mod", "go.sum", "go.work" }),
    mark(marks.python, &.{ "py", "pyi", "pyw" }, &.{}),
    mark(marks.javascript, &.{ "js", "mjs", "cjs" }, &.{}),
    mark(marks.typescript, &.{ "ts", "mts", "cts" }, &.{}),
    mark(marks.react, &.{ "jsx", "tsx" }, &.{}),
    mark(marks.vue, &.{"vue"}, &.{}),
    mark(marks.c, &.{ "c", "h" }, &.{}),
    mark(marks.cpp, &.{ "cc", "cpp", "cxx", "hh", "hpp", "hxx" }, &.{}),
    mark(marks.csharp, &.{"cs"}, &.{}),
    mark(marks.swift, &.{"swift"}, &.{}),
    mark(marks.java, &.{"java"}, &.{}),
    mark(marks.kotlin, &.{ "kt", "kts" }, &.{}),
    mark(marks.ruby, &.{ "rb", "erb" }, &.{ "Gemfile", "Rakefile" }),
    mark(marks.php, &.{"php"}, &.{}),
    mark(marks.lua, &.{"lua"}, &.{}),
    mark(marks.shell, &.{ "sh", "bash", "zsh", "fish" }, &.{}),
    mark(marks.html, &.{ "html", "htm" }, &.{}),
    mark(marks.css, &.{ "css", "scss", "sass", "less" }, &.{}),
    mark(marks.json, &.{ "json", "jsonc" }, &.{}),
    mark(marks.yaml, &.{ "yaml", "yml" }, &.{}),
    mark(marks.toml, &.{"toml"}, &.{}),
    mark(marks.markdown, &.{ "md", "markdown", "mdx" }, &.{}),
    mark(marks.sql, &.{"sql"}, &.{}),
    mark(marks.docker, &.{"dockerfile"}, &.{ "Dockerfile", "compose.yaml", "compose.yml", "docker-compose.yml", "docker-compose.yaml" }),
    mark(marks.git, &.{}, &.{ ".gitignore", ".gitattributes", ".gitmodules", ".gitkeep" }),
    .{ .icon = Lucide.file_code, .color = Color.hex(0x5b84c0), .exts = &.{ "m", "mm", "svelte" } },
    .{ .icon = Lucide.file_braces, .color = Color.hex(0xb38f3c), .exts = &.{ "xml", "plist" } },
    .{ .icon = Lucide.file_spreadsheet, .color = Color.hex(0x5c9a6c), .exts = &.{ "csv", "tsv" } },
    .{ .icon = Lucide.file_text, .color = Color.hex(0x7b6fd6), .exts = &.{ "txt", "rst" } },
    .{ .icon = Lucide.file_badge, .color = Color.hex(0xb38f3c), .names = &.{ "LICENSE", "LICENSE.txt", "LICENSE.md", "OFL.txt", "COPYING" } },
    .{ .icon = Lucide.file_cog, .color = Color.hex(0x8a8794), .exts = &.{ "ini", "conf", "cfg", "env" }, .names = &.{ "Makefile", "CMakeLists.txt" } },
    .{ .icon = Lucide.file_diff, .color = Color.hex(0x5c9a6c), .exts = &.{ "patch", "diff" } },
    .{ .icon = Lucide.file_lock, .color = Color.hex(0x8d8b97), .dim = true, .exts = &.{"lock"} },
    .{ .icon = Lucide.file_image, .color = Color.hex(0xb0699a), .dim = true, .exts = &.{ "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "ico", "icns" } },
    .{ .icon = Lucide.file_archive, .color = Color.hex(0x9a7a5a), .dim = true, .exts = &.{ "zip", "tar", "gz", "xz", "zst", "7z", "jar" } },
    .{ .icon = Lucide.file_type, .color = Color.hex(0x8a7fb8), .dim = true, .exts = &.{ "ttf", "otf", "woff", "woff2" } },
    .{ .icon = Lucide.file_music, .color = Color.hex(0x8a7fb8), .dim = true, .exts = &.{ "mp3", "wav", "flac", "ogg", "m4a" } },
    .{ .icon = Lucide.file_video_camera, .color = Color.hex(0x8a7fb8), .dim = true, .exts = &.{ "mp4", "mov", "mkv", "webm" } },
};

/// Any other file: plain icon in the tree's muted color.
pub const default = Kind{ .icon = Lucide.file, .color = Color.hex(0x76757f) };

pub fn of(name: []const u8) Kind {
    for (kinds) |k| for (k.names) |n| if (std.mem.eql(u8, n, name)) return k;
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return default;
    const ext = name[dot + 1 ..];
    for (kinds) |k| for (k.exts) |e| if (std.ascii.eqlIgnoreCase(e, ext)) return k;
    return default;
}

test "kinds" {
    try std.testing.expectEqual(marks.zig.path, of("main.zig").icon);
    try std.testing.expect(of("main.zig").mark);
    try std.testing.expectEqual(marks.typescript.path, of("api.D.TS").icon);
    try std.testing.expectEqual(marks.git.path, of(".gitignore").icon);
    try std.testing.expectEqual(marks.docker.path, of("Dockerfile").icon);
    try std.testing.expectEqual(marks.go.path, of("go.mod").icon);
    try std.testing.expectEqual(Lucide.file_badge, of("LICENSE").icon);
    try std.testing.expect(of("logo.PNG").dim);
    try std.testing.expect(!of("logo.png").mark);
    try std.testing.expectEqual(default.icon, of("README").icon);
    try std.testing.expectEqual(default.icon, of("archive.unknown").icon);
}
