//! Syntax highlighting: a small lexer per language family (`syntax_code.zig`,
//! `syntax_markup.zig`) colors comments, strings, keywords, keys, tags,
//! headings… in the visible lines.
//!
//! The buffer is tokenized once and the spans are cached; each frame then
//! only picks the spans overlapping the visible lines. Re-lexing from the top
//! of the file every frame made the frame time grow with the scroll position
//! (a 530KB file cost ~65ms per frame three quarters down).

const std = @import("std");
const gooey = @import("gooey");
const theme = @import("theme.zig");
const code = @import("syntax_code.zig");
const markup = @import("syntax_markup.zig");

const CodeEditorState = gooey.widgets.CodeEditorState;
const Highlighter = gooey.widgets.code_editor_state.Highlighter;
const Hsla = gooey.scene.Hsla;
const Token = code.Token;
const Next = code.Next;

/// Exact file names first, then lowercase extensions.
const Lang = struct { names: []const []const u8 = &.{}, exts: []const []const u8 = &.{}, next: Next };

const langs = [_]Lang{
    .{ .exts = &.{ "zig", "zon" }, .next = code.zig },
    .{ .exts = &.{"rs"}, .next = code.rust },
    .{ .exts = &.{ "c", "h", "cc", "cpp", "cxx", "hh", "hpp", "hxx", "m", "mm", "go", "java", "kt", "kts", "swift", "cs", "php", "dart", "scala", "groovy", "gradle" }, .next = code.c_like },
    .{ .exts = &.{ "js", "mjs", "cjs", "ts", "mts", "cts", "jsx", "tsx" }, .next = code.js },
    .{ .exts = &.{ "py", "pyi", "pyw" }, .next = code.python },
    .{ .names = &.{ "Gemfile", "Rakefile" }, .exts = &.{ "rb", "lua", "erb" }, .next = code.ruby_lua },
    .{ .names = &.{ ".bashrc", ".zshrc", ".profile", ".bash_profile", ".zprofile" }, .exts = &.{ "sh", "bash", "zsh", "fish" }, .next = code.shell },
    .{ .exts = &.{ "json", "jsonc", "json5", "geojson", "ipynb" }, .next = code.json },
    .{ .names = &.{ ".clang-format", ".clangd" }, .exts = &.{ "yaml", "yml" }, .next = code.yaml },
    .{ .names = &.{ "Cargo.lock", "poetry.lock", "uv.lock" }, .exts = &.{"toml"}, .next = code.toml },
    .{ .names = &.{ ".env", ".editorconfig", ".gitconfig", ".npmrc", ".gitignore", ".gitattributes", ".dockerignore", ".gitmodules" }, .exts = &.{ "ini", "cfg", "conf", "env", "properties", "desktop", "service" }, .next = code.ini },
    .{ .exts = &.{ "tf", "tfvars", "hcl", "nomad" }, .next = code.hcl },
    .{ .exts = &.{"sql"}, .next = code.sql },
    .{ .names = &.{ "Dockerfile", "Containerfile" }, .exts = &.{"dockerfile"}, .next = code.dockerfile },
    .{ .names = &.{ "Makefile", "makefile", "GNUmakefile" }, .exts = &.{"mk"}, .next = code.make },
    .{ .names = &.{ "README", "CHANGELOG" }, .exts = &.{ "md", "markdown", "mdx", "mkd" }, .next = markup.markdown },
    .{ .exts = &.{ "html", "htm", "xhtml", "xml", "svg", "plist", "xsd", "xsl", "vue", "svelte", "astro", "csproj", "storyboard", "xib" }, .next = markup.html },
    .{ .exts = &.{ "css", "scss", "sass", "less" }, .next = markup.css },
    .{ .exts = &.{ "diff", "patch" }, .next = markup.diff },
};

/// One highlighter per language: a highlighter is a bare function pointer.
const highlighters = blk: {
    var hs: [langs.len]Highlighter = undefined;
    for (langs, 0..) |l, n| hs[n] = Driver(n + 1, l.next).highlight;
    break :blk hs;
};

/// The highlighter for a file name, or null for plain text.
pub fn forName(name: []const u8) ?Highlighter {
    return highlighters[langOf(name) orelse return null];
}

fn langOf(name: []const u8) ?usize {
    for (langs, 0..) |l, n| for (l.names) |exact| if (std.mem.eql(u8, exact, name)) return n;
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return null;
    const ext = name[dot + 1 ..];
    for (langs, 0..) |l, n| for (l.exts) |e| if (std.ascii.eqlIgnoreCase(e, ext)) return n;
    return null;
}

fn colorOf(t: Token) Hsla {
    const s = theme.color.syntax;
    return Hsla.fromColor(switch (t) {
        .none => theme.color.foreground,
        inline else => |tag| @field(s, @tagName(tag)),
    });
}

/// Tokenized spans for a buffer, lexed once from the top and reused for every
/// frame; one per editor (the open file, the quick-open preview, the settings
/// preview). Opening another file (or editing) bumps `TextAreaState.revision`
/// and starts over.
const max_spans: usize = 1 << 18;

const Cache = struct {
    /// The editor these spans belong to.
    owner: usize = 0,
    valid: bool = false,
    revision: u64 = 0,
    ptr: usize = 0,
    len: usize = 0,
    lang_tag: usize = 0,
    count: usize = 0,
    /// Byte offset lexed through; resumption always starts at a token boundary.
    lexed: usize = 0,
    /// The lexer's context at `lexed` (inside a tag, a code fence…).
    state: u64 = 0,
    /// Hit `max_spans`: the rest of a pathologically dense file stays plain.
    capped: bool = false,
    starts: [max_spans]u32 = undefined,
    ends: [max_spans]u32 = undefined,
    tokens: [max_spans]Token = undefined,
};

var caches: [3]Cache = .{ .{}, .{}, .{} };
var next_cache: usize = 0;

/// The editor's cache, or the least recently claimed one if it is new.
fn cacheFor(editor: *CodeEditorState) *Cache {
    const id = @intFromPtr(editor);
    for (&caches) |*c| if (c.owner == id) return c;
    const c = &caches[next_cache];
    next_cache = (next_cache + 1) % caches.len;
    c.owner = id;
    c.valid = false;
    return c;
}

fn resetCache(cache: *Cache, editor: *CodeEditorState, text: []const u8, lang_tag: usize) void {
    cache.valid = true;
    cache.revision = editor.text_area.revision;
    cache.ptr = @intFromPtr(text.ptr);
    cache.len = text.len;
    cache.lang_tag = lang_tag;
    cache.count = 0;
    cache.lexed = 0;
    cache.state = 0;
    cache.capped = false;
}

fn cacheStale(cache: *const Cache, editor: *CodeEditorState, text: []const u8, lang_tag: usize) bool {
    return !cache.valid or cache.revision != editor.text_area.revision or
        cache.ptr != @intFromPtr(text.ptr) or cache.len != text.len or
        cache.lang_tag != lang_tag;
}

/// Lexes with `next` into the editor's cache and hands it the visible spans.
fn Driver(comptime lang_tag: usize, comptime next: Next) type {
    return struct {
        fn highlight(editor: *CodeEditorState, text: []const u8, start: usize, end: usize) void {
            const cache = cacheFor(editor);
            if (cacheStale(cache, editor, text, lang_tag)) resetCache(cache, editor, text, lang_tag);

            const through = @min(end, text.len);
            if (!cache.capped and cache.lexed < through) lexTo(cache, text, through);
            emit(cache, editor, start, through);
        }

        /// Lexes whole tokens until past `through`, appending their spans.
        fn lexTo(cache: *Cache, text: []const u8, through: usize) void {
            var i = cache.lexed;
            while (i < through) {
                const from = i;
                const t = next(text, &i, &cache.state);
                if (t == .none or i == from) continue;
                if (cache.count == max_spans) {
                    cache.capped = true;
                    break;
                }
                cache.starts[cache.count] = @intCast(from);
                cache.ends[cache.count] = @intCast(i);
                cache.tokens[cache.count] = t;
                cache.count += 1;
            }
            cache.lexed = i;
        }
    };
}

/// Hands the spans overlapping `[start, end)` to the editor, clipped to it.
fn emit(cache: *const Cache, editor: *CodeEditorState, start: usize, end: usize) void {
    // Spans are sorted and non-overlapping, so ends are sorted too.
    var lo: usize = 0;
    var hi = cache.count;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (cache.ends[mid] <= start) lo = mid + 1 else hi = mid;
    }
    var i = lo;
    while (i < cache.count and cache.starts[i] < end) : (i += 1) {
        const from = @max(cache.starts[i], start);
        const to = @min(cache.ends[i], end);
        if (to <= from) continue;
        if (!editor.addHighlight(from, to, colorOf(cache.tokens[i]))) return;
    }
}

/// The tokens a file lexes to, as `text: token` pairs, for the tests.
fn expectTokens(name: []const u8, text: []const u8, expected: []const struct { []const u8, Token }) !void {
    const l = langs[langOf(name) orelse return error.NoLexer];
    var i: usize = 0;
    var state: u64 = 0;
    var n: usize = 0;
    while (i < text.len) {
        const from = i;
        const t = l.next(text, &i, &state);
        try std.testing.expect(i > from);
        if (t == .none) continue;
        if (n >= expected.len) {
            std.debug.print("extra token {s} \"{s}\"\n", .{ @tagName(t), text[from..i] });
            return error.TestUnexpectedResult;
        }
        std.testing.expectEqualStrings(expected[n][0], text[from..i]) catch |e| {
            std.debug.print("token {d}\n", .{n});
            return e;
        };
        std.testing.expectEqual(expected[n][1], t) catch |e| {
            std.debug.print("token {d} \"{s}\"\n", .{ n, text[from..i] });
            return e;
        };
        n += 1;
    }
    try std.testing.expectEqual(expected.len, n);
}

test "zig tokens" {
    var editor = CodeEditorState.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 100, .height = 100 });
    defer editor.deinit();
    const text = "const x: u8 = @max(1, \"a\"); // hi";
    forName("main.zig").?(&editor, text, 0, text.len);
    const spans = editor.getHighlights();
    const expect = [_][]const u8{ "const", "u8", "@max", "1", "\"a\"", "// hi" };
    try std.testing.expectEqual(expect.len, spans.len);
    for (expect, spans) |e, s| try std.testing.expectEqualStrings(e, text[s.start..s.end]);
}

test "rust lifetime is not a string" {
    var editor = CodeEditorState.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 100, .height = 100 });
    defer editor.deinit();
    const text = "fn f<'a>(c: char) { let q = 'x'; }";
    forName("lib.rs").?(&editor, text, 0, text.len);
    const spans = editor.getHighlights();
    try std.testing.expectEqualStrings("'x'", text[spans[spans.len - 1].start..spans[spans.len - 1].end]);
    try std.testing.expect(forName("notes.txt") == null);
}

test "yaml keys" {
    try expectTokens("config.yaml",
        \\# service
        \\name: slate-api
        \\replicas: 3
        \\url: http://x
        \\env:
        \\  - key: LOG_LEVEL
        \\    "quoted": 'debug'
    , &.{
        .{ "# service", .comment }, .{ "name", .key },     .{ "replicas", .key }, .{ "3", .number },
        .{ "url", .key },           .{ "env", .key },      .{ "key", .key },      .{ "\"quoted\"", .key },
        .{ "'debug'", .string },
    });
}

test "json keys" {
    try expectTokens("package.json", "{\"name\":\"slate\",\"n\": 1, \"ok\": true}", &.{
        .{ "\"name\"", .key }, .{ "\"slate\"", .string }, .{ "\"n\"", .key }, .{ "1", .number }, .{ "\"ok\"", .key }, .{ "true", .keyword },
    });
}

test "toml" {
    try expectTokens("Cargo.toml",
        \\[package]
        \\name = "slate"
        \\a.b-c = 1
        \\ok = true
    , &.{
        .{ "[package]", .heading }, .{ "name", .key }, .{ "\"slate\"", .string }, .{ "a.b-c", .key }, .{ "1", .number }, .{ "ok", .key }, .{ "true", .keyword },
    });
}

test "terraform" {
    try expectTokens("main.tf",
        \\# network
        \\resource "aws_vpc" "main" {
        \\  cidr_block = "10.0.0.0/16"
        \\  tags = { Name = var.name }
        \\  count = length(var.zones)
        \\}
    , &.{
        .{ "# network", .comment }, .{ "resource", .keyword },       .{ "\"aws_vpc\"", .string }, .{ "\"main\"", .string },
        .{ "cidr_block", .key },    .{ "\"10.0.0.0/16\"", .string }, .{ "tags", .key },           .{ "var", .keyword },
        .{ "count", .key },         .{ "length", .call },            .{ "var", .keyword },
    });
}

test "sql, dockerfile, makefile, env" {
    try expectTokens("q.sql", "SELECT id FROM users -- all\nWHERE name = 'x';", &.{
        .{ "SELECT", .keyword }, .{ "FROM", .keyword }, .{ "-- all", .comment }, .{ "WHERE", .keyword }, .{ "'x'", .string },
    });
    try expectTokens("Dockerfile", "FROM alpine\nRUN echo $HOME from\n", &.{
        .{ "FROM", .keyword }, .{ "RUN", .keyword }, .{ "$HOME", .variable },
    });
    try expectTokens("Makefile", "CC := cc\nall: build\n\t$(CC) -o x\n", &.{
        .{ "CC", .key }, .{ "all", .key }, .{ "$(CC)", .variable },
    });
    try expectTokens(".env", "# db\nDB_URL=postgres://x\n", &.{
        .{ "# db", .comment }, .{ "DB_URL", .key },
    });
}

test "markdown" {
    try expectTokens("README.md",
        \\# Slate
        \\A **small** editor with `code`, [a link](https://x.y) and snake_case_name.
        \\
        \\- item
        \\1. first
        \\
        \\```zig
        \\const x = 1;
        \\```
        \\> quote
    , &.{
        .{ "# Slate", .heading },          .{ "**small**", .emphasis }, .{ "`code`", .code },
        .{ "[a link](https://x.y)", .link }, .{ "-", .punct },          .{ "1.", .punct },
        .{ "```zig\n", .punct },           .{ "const", .keyword },      .{ "1", .number },
        .{ "```", .punct },                .{ ">", .punct },
    });
}

test "html with script and style" {
    try expectTokens("index.html",
        \\<!doctype html>
        \\<!-- c -->
        \\<body class="main" hidden>
        \\<p>Hi &amp; bye</p>
        \\<script>const a = "s";</script>
        \\<style>p { color: red; }</style>
    , &.{
        .{ "<!doctype html>", .keyword }, .{ "<!-- c -->", .comment }, .{ "<body", .tag },    .{ "class", .attr },
        .{ "\"main\"", .string },         .{ "hidden", .attr },        .{ ">", .tag },        .{ "<p", .tag },
        .{ ">", .tag },                   .{ "&amp;", .number },       .{ "</p", .tag },      .{ ">", .tag },
        .{ "<script", .tag },             .{ ">", .tag },              .{ "const", .keyword }, .{ "\"s\"", .string },
        .{ "</script", .tag },            .{ ">", .tag },              .{ "<style", .tag },   .{ ">", .tag },
        .{ "p", .tag },                   .{ "color", .key },          .{ "</style", .tag },  .{ ">", .tag },
    });
}

test "css" {
    try expectTokens("app.scss",
        \\/* c */
        \\.card:hover, #id > a {
        \\  --gap: 4px;
        \\  margin: -2px auto !important;
        \\  color: rgb(0 0 0);
        \\  &:focus { outline: none; }
        \\}
        \\@media (width < 600px) {}
    , &.{
        .{ "/* c */", .comment }, .{ ".card", .type },      .{ ":hover", .keyword },   .{ "#id", .type },
        .{ "a", .tag },           .{ "--gap", .key },       .{ "4px", .number },       .{ "margin", .key },
        .{ "-2px", .number },     .{ "!important", .keyword }, .{ "color", .key },     .{ "rgb", .call },
        .{ "0", .number },        .{ "0", .number },        .{ "0", .number },         .{ ":focus", .keyword },
        .{ "outline", .key },     .{ "@media", .keyword },  .{ "width", .tag },        .{ "600px", .number },
    });
}

test "diff" {
    try expectTokens("x.patch", "diff --git a b\n--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new\n same\n", &.{
        .{ "diff --git a b", .comment }, .{ "--- a", .heading }, .{ "+++ b", .heading }, .{ "@@ -1 +1 @@", .keyword }, .{ "-old", .removed }, .{ "+new", .added },
    });
}

test "later viewport reuses the lexed prefix" {
    var text: []const u8 =
        "const before = 1;\n" ++
        "/* a block comment\n" ++
        "   that spans lines */\n" ++
        "const after = \"text\";\n" ++
        "// tail\n";
    var editor = CodeEditorState.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 200, .height = 200 });
    defer editor.deinit();
    // C-like: block comments span lines (Zig only has `//`).
    const highlight = forName("main.c").?;

    // First frame at the top lexes and caches the head of the buffer.
    highlight(&editor, text, 0, 18);
    try std.testing.expect(editor.getHighlights().len > 0);

    // Scrolling down: the block comment started above the viewport but still
    // colors the visible lines, and no span is lost to the earlier range.
    editor.clearHighlights();
    const start = std.mem.indexOf(u8, text, "   that").?;
    const end = std.mem.indexOf(u8, text, "const after").? + 12;
    highlight(&editor, text, start, end);
    const spans = editor.getHighlights();
    try std.testing.expect(spans.len >= 2);
    try std.testing.expectEqualStrings("   that spans lines */", text[spans[0].start..spans[0].end]);
    try std.testing.expectEqualStrings("const", text[spans[1].start..spans[1].end]);

    // Editing invalidates the cache and re-lexes the new text.
    text = "// one line\nconst fresh = 2;";
    try editor.setText(text);
    editor.clearHighlights();
    highlight(&editor, text, 0, text.len);
    const edited = editor.getHighlights();
    try std.testing.expectEqualStrings("// one line", text[edited[0].start..edited[0].end]);
    try std.testing.expectEqualStrings("const", text[edited[1].start..edited[1].end]);
}
