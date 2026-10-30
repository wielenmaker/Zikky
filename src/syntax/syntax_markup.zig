//! Lexers for markup and styles: Markdown (fenced code highlighted in its
//! language), HTML/XML (with `<script>` / `<style>` content), CSS and diffs.

const std = @import("std");
const code = @import("syntax_code.zig");

const Token = code.Token;
const Next = code.Next;
const toLineEnd = code.toLineEnd;
const until = code.until;
const atLineStart = code.atLineStart;

/// Languages a Markdown fence can name (` ```zig `), by index in `fence_langs`.
const fence_langs = [_]struct { names: []const []const u8, next: Next }{
    .{ .names = &.{ "zig", "zon" }, .next = code.zig },
    .{ .names = &.{ "rust", "rs" }, .next = code.rust },
    .{ .names = &.{ "c", "h", "cpp", "c++", "cc", "go", "golang", "java", "kotlin", "kt", "swift", "cs", "csharp", "objc" }, .next = code.c_like },
    .{ .names = &.{ "js", "javascript", "jsx", "ts", "typescript", "tsx", "mjs" }, .next = code.js },
    .{ .names = &.{ "py", "python", "python3" }, .next = code.python },
    .{ .names = &.{ "rb", "ruby", "lua" }, .next = code.ruby_lua },
    .{ .names = &.{ "sh", "bash", "zsh", "shell", "fish", "console", "shellsession" }, .next = code.shell },
    .{ .names = &.{ "json", "jsonc", "json5" }, .next = code.json },
    .{ .names = &.{ "yaml", "yml" }, .next = code.yaml },
    .{ .names = &.{"toml"}, .next = code.toml },
    .{ .names = &.{ "ini", "conf", "env", "dotenv" }, .next = code.ini },
    .{ .names = &.{ "hcl", "tf", "terraform" }, .next = code.hcl },
    .{ .names = &.{ "sql", "postgres", "postgresql", "mysql", "sqlite" }, .next = code.sql },
    .{ .names = &.{ "dockerfile", "docker" }, .next = code.dockerfile },
    .{ .names = &.{ "make", "makefile", "mk" }, .next = code.make },
    .{ .names = &.{ "diff", "patch" }, .next = diff },
};

// ---------------------------------------------------------------------------
// Markdown. State: bit 0 = inside a fence; bits 8–15 = its language + 1;
// bits 32–63 = where the closing fence line starts.

pub fn markdown(text: []const u8, i: *usize, state: *u64) Token {
    const from = i.*;
    if (state.* & 1 != 0) {
        const end: usize = @intCast(state.* >> 32);
        if (from >= end) {
            state.* = 0;
            return toLineEnd(text, i, .punct);
        }
        const lang = (state.* >> 8) & 0xff;
        if (lang == 0) {
            i.* = @min(end, std.mem.indexOfScalarPos(u8, text, from, '\n') orelse text.len);
            if (i.* == from) i.* += 1;
            return .code;
        }
        var sub: u64 = 0;
        return fence_langs[lang - 1].next(text[0..end], i, &sub);
    }
    const c = text[from];
    if (std.mem.indexOfScalar(u8, "#>-*+_`~0123456789", c) != null and atLineStart(text, from)) {
        if (block(text, i, state)) |t| return t;
    }
    return inline_(text, i);
}

/// A construct that starts a line: heading, fence, quote, list marker, rule.
fn block(text: []const u8, i: *usize, state: *u64) ?Token {
    const from = i.*;
    const rest = text[from..];
    const eol = std.mem.indexOfScalarPos(u8, text, from, '\n') orelse text.len;
    const line = text[from..eol];
    if (std.mem.startsWith(u8, rest, "```") or std.mem.startsWith(u8, rest, "~~~")) {
        const info = std.mem.trim(u8, line[3..], " \t`~");
        const word = info[0 .. std.mem.indexOfAny(u8, info, " \t{,") orelse info.len];
        var lang: u64 = 0;
        for (fence_langs, 1..) |f, n| for (f.names) |name| {
            if (std.ascii.eqlIgnoreCase(name, word)) lang = n;
        };
        var close: [4]u8 = .{ '\n', rest[0], rest[0], rest[0] };
        const end = if (eol < text.len) (if (std.mem.indexOfPos(u8, text, eol, &close)) |p| p + 1 else text.len) else text.len;
        state.* = 1 | lang << 8 | @as(u64, end) << 32;
        i.* = @min(eol + 1, text.len);
        return .punct;
    }
    if (rest[0] == '#') {
        var n: usize = 0;
        while (n < line.len and line[n] == '#') n += 1;
        if (n <= 6 and (n == line.len or line[n] == ' ' or line[n] == '\t')) return toLineEnd(text, i, .heading);
        return null;
    }
    if (rest[0] == '>') {
        i.* += 1;
        return .punct;
    }
    // A thematic break: three or more of one of `-`, `*`, `_` (spaces allowed).
    if (rest[0] == '-' or rest[0] == '*' or rest[0] == '_') {
        var count: usize = 0;
        for (line) |ch| {
            if (ch == rest[0]) count += 1 else if (ch != ' ' and ch != '\t' and ch != '\r') break;
        } else if (count >= 3) return toLineEnd(text, i, .punct);
    }
    if ((rest[0] == '-' or rest[0] == '*' or rest[0] == '+') and line.len > 1 and line[1] == ' ') {
        // A task box `- [ ]` / `- [x]` goes with its marker.
        i.* += if (line.len >= 5 and line[2] == '[' and line[4] == ']') 5 else 1;
        return .punct;
    }
    if (std.ascii.isDigit(rest[0])) {
        var n: usize = 0;
        while (n < line.len and std.ascii.isDigit(line[n])) n += 1;
        if (n < line.len and (line[n] == '.' or line[n] == ')') and (n + 1 == line.len or line[n + 1] == ' ')) {
            i.* += n + 1;
            return .punct;
        }
    }
    return null;
}

/// Code spans, emphasis, links and autolinks within a line.
fn inline_(text: []const u8, i: *usize) Token {
    const from = i.*;
    const rest = text[from..];
    const eol = std.mem.indexOfScalarPos(u8, text, from, '\n') orelse text.len;
    switch (rest[0]) {
        '\\' => {
            i.* = @min(text.len, from + 2);
            return .none;
        },
        '`' => {
            var n: usize = 0;
            while (n < rest.len and rest[n] == '`') n += 1;
            if (std.mem.indexOfPos(u8, text[0..eol], from + n, rest[0..n])) |close| {
                i.* = close + n;
                return .code;
            }
            i.* += n;
            return .none;
        },
        '*', '_' => {
            const ch = rest[0];
            // `_` inside a word (snake_case) is not emphasis.
            if (ch == '_' and from > 0 and code.isIdent(text[from - 1])) {
                i.* += 1;
                return .none;
            }
            const n: usize = if (rest.len > 1 and rest[1] == ch) 2 else 1;
            if (rest.len > n and rest[n] != ' ' and rest[n] != ch) {
                if (std.mem.indexOfPos(u8, text[0..eol], from + n + 1, rest[0..n])) |close| {
                    if (text[close - 1] != ' ' and (ch == '*' or close + n >= text.len or !code.isIdent(text[close + n]))) {
                        i.* = close + n;
                        return .emphasis;
                    }
                }
            }
            i.* += n;
            return .none;
        },
        '[', '!' => {
            const open = if (rest[0] == '!') from + 1 else from;
            if (open < eol and text[open] == '[') {
                if (std.mem.indexOfScalarPos(u8, text[0..eol], open + 1, ']')) |close| {
                    if (close + 1 < eol and (text[close + 1] == '(' or text[close + 1] == '[')) {
                        const want: u8 = if (text[close + 1] == '(') ')' else ']';
                        if (std.mem.indexOfScalarPos(u8, text[0..eol], close + 2, want)) |end| {
                            i.* = end + 1;
                            return .link;
                        }
                    }
                }
            }
            i.* += 1;
            return .none;
        },
        '<' => {
            if (std.mem.startsWith(u8, rest, "<http") or std.mem.startsWith(u8, rest, "<mailto:")) {
                if (std.mem.indexOfScalarPos(u8, text[0..eol], from, '>')) |close| {
                    i.* = close + 1;
                    return .link;
                }
            }
            if (std.mem.startsWith(u8, rest, "<!--")) return until(text, i, 4, "-->", .comment);
            if (rest.len > 1 and (std.ascii.isAlphabetic(rest[1]) or rest[1] == '/')) {
                if (std.mem.indexOfScalarPos(u8, text[0..eol], from, '>')) |close| {
                    i.* = close + 1;
                    return .tag;
                }
            }
            i.* += 1;
            return .none;
        },
        'h' => {
            if ((from == 0 or !code.isIdent(text[from - 1])) and
                (std.mem.startsWith(u8, rest, "https://") or std.mem.startsWith(u8, rest, "http://")))
            {
                i.* = std.mem.indexOfAnyPos(u8, text[0..eol], from, " \t)>") orelse eol;
                return .link;
            }
            i.* += 1;
            return .none;
        },
        else => {
            i.* += 1;
            return .none;
        },
    }
}

// ---------------------------------------------------------------------------
// HTML / XML. State: bits 0–3 = mode; bits 4–7 = the open tag's raw kind;
// bits 8–31 = the CSS state inside `<style>`; bits 32–63 = where raw text ends.

const text_mode = 0;
const tag_mode = 1;
const script_mode = 2;
const style_mode = 3;

pub fn html(text: []const u8, i: *usize, state: *u64) Token {
    const from = i.*;
    const rest = text[from..];
    const mode = state.* & 0xf;
    if (mode == script_mode or mode == style_mode) {
        const end: usize = @intCast(state.* >> 32);
        if (from < end) {
            if (mode == script_mode) {
                var sub: u64 = 0;
                return code.js(text[0..end], i, &sub);
            }
            var sub = (state.* >> 8) & 0xffffff;
            const t = css(text[0..end], i, &sub);
            state.* = (state.* & ~@as(u64, 0xffffff00)) | sub << 8;
            return t;
        }
        state.* = text_mode;
    }
    if (mode == tag_mode) {
        const c = rest[0];
        if (c == '>' or std.mem.startsWith(u8, rest, "/>")) {
            const self_closing = c == '/';
            i.* += if (self_closing) 2 else 1;
            const raw = (state.* >> 4) & 0xf;
            state.* = text_mode;
            if (!self_closing and raw != 0) {
                const close = if (raw == script_mode) "</script" else "</style";
                const end = indexOfIgnoreCase(text, i.*, close) orelse text.len;
                state.* = raw | @as(u64, end) << 32;
            }
            return .tag;
        }
        if (c == '"' or c == '\'') {
            const end = std.mem.indexOfScalarPos(u8, text, from + 1, c);
            i.* = if (end) |e| e + 1 else text.len;
            return .string;
        }
        if (std.ascii.isAlphabetic(c) or c == '_' or c == ':' or c == '@' or c == '#') {
            i.* += 1;
            while (i.* < text.len and isNameChar(text[i.*])) i.* += 1;
            return .attr;
        }
        i.* += 1;
        return .none;
    }
    if (std.mem.startsWith(u8, rest, "<!--")) return until(text, i, 4, "-->", .comment);
    if (std.mem.startsWith(u8, rest, "<![CDATA[")) return until(text, i, 9, "]]>", .string);
    if (std.mem.startsWith(u8, rest, "<!") or std.mem.startsWith(u8, rest, "<?")) return until(text, i, 2, ">", .keyword);
    if (rest[0] == '<' and rest.len > 1 and (std.ascii.isAlphabetic(rest[1]) or rest[1] == '/')) {
        const name_start = from + @as(usize, if (rest[1] == '/') 2 else 1);
        i.* = name_start;
        while (i.* < text.len and isNameChar(text[i.*])) i.* += 1;
        const name = text[name_start..i.*];
        const raw: u64 = if (rest[1] == '/') 0 else if (std.ascii.eqlIgnoreCase(name, "script")) script_mode else if (std.ascii.eqlIgnoreCase(name, "style")) style_mode else 0;
        state.* = tag_mode | raw << 4;
        return .tag;
    }
    if (rest[0] == '&') {
        var n: usize = 1;
        while (n < @min(rest.len, 12) and (std.ascii.isAlphanumeric(rest[n]) or rest[n] == '#')) n += 1;
        if (n > 1 and n < rest.len and rest[n] == ';') {
            i.* += n + 1;
            return .number;
        }
    }
    // Skip plain text up to the next tag or entity.
    i.* = std.mem.indexOfAnyPos(u8, text, from + 1, "<&") orelse text.len;
    return .none;
}

fn isNameChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == ':' or c == '.' or c == '@';
}

fn indexOfIgnoreCase(text: []const u8, from: usize, needle: []const u8) ?usize {
    var j = from;
    while (std.mem.indexOfScalarPos(u8, text, j, '<')) |p| : (j = p + 1) {
        if (text.len - p >= needle.len and std.ascii.eqlIgnoreCase(text[p..][0..needle.len], needle)) return p;
    }
    return null;
}

// ---------------------------------------------------------------------------
// CSS, SCSS, Less. State: bits 0–15 = brace depth; bit 16 = in a declaration's value.

const in_value: u64 = 1 << 16;

pub fn css(text: []const u8, i: *usize, state: *u64) Token {
    const from = i.*;
    const rest = text[from..];
    const c = rest[0];
    const depth = state.* & 0xffff;
    const value = state.* & in_value != 0;
    if (std.mem.startsWith(u8, rest, "/*")) return until(text, i, 2, "*/", .comment);
    // SCSS / Less line comments, but not `url(http://…)`.
    if (std.mem.startsWith(u8, rest, "//") and (from == 0 or text[from - 1] == ' ' or text[from - 1] == '\t' or text[from - 1] == '\n')) return toLineEnd(text, i, .comment);
    i.* += 1;
    switch (c) {
        '"', '\'' => {
            i.* = from;
            return code.quoted(text, i, c);
        },
        '{' => {
            state.* = @min(depth + 1, 0xffff);
            return .none;
        },
        '}' => {
            state.* = depth -| 1;
            return .none;
        },
        ';' => {
            state.* = depth;
            return .none;
        },
        '@' => {
            i.* = nameEnd(text, i.*);
            return .keyword;
        },
        '$' => {
            i.* = nameEnd(text, i.*);
            return .variable;
        },
        '!' => {
            if (std.ascii.startsWithIgnoreCase(rest, "!important")) {
                i.* = from + 10;
                return .keyword;
            }
            return .none;
        },
        '#' => {
            i.* = nameEnd(text, i.*);
            return if (value) .number else .type;
        },
        '.' => {
            if (value or (rest.len > 1 and std.ascii.isDigit(rest[1]))) return number(text, i, from);
            i.* = nameEnd(text, i.*);
            return if (i.* > from + 1) .type else .none;
        },
        ':' => {
            if (value or depth > 0 and !selectorAhead(text, from)) return .none;
            // Pseudo-classes and elements: `:hover`, `::before`.
            if (i.* < text.len and text[i.*] == ':') i.* += 1;
            i.* = nameEnd(text, i.*);
            return .keyword;
        },
        else => {},
    }
    if (std.ascii.isDigit(c) or (c == '-' and rest.len > 1 and (std.ascii.isDigit(rest[1]) or rest[1] == '.'))) return number(text, i, from);
    if (std.ascii.isAlphabetic(c) or c == '-' or c == '_') {
        i.* = nameEnd(text, from);
        if (i.* < text.len and text[i.*] == '(') return .call;
        if (value) return if (std.mem.startsWith(u8, rest, "--")) .variable else .none;
        if (depth > 0 and !selectorAhead(text, from)) {
            state.* = depth | in_value;
            return .key;
        }
        return .tag;
    }
    return .none;
}

fn number(text: []const u8, i: *usize, from: usize) Token {
    i.* = from + 1;
    while (i.* < text.len and (std.ascii.isAlphanumeric(text[i.*]) or text[i.*] == '.' or text[i.*] == '%')) i.* += 1;
    return .number;
}

fn nameEnd(text: []const u8, from: usize) usize {
    var j = from;
    while (j < text.len and (std.ascii.isAlphanumeric(text[j]) or text[j] == '-' or text[j] == '_')) j += 1;
    return j;
}

/// Inside a block, a selector (nested rule) reaches `{` before `;` or `}`;
/// a declaration doesn't.
fn selectorAhead(text: []const u8, from: usize) bool {
    const stop = std.mem.indexOfAnyPos(u8, text, from, "{;}") orelse return false;
    return text[stop] == '{';
}

// ---------------------------------------------------------------------------
// Diffs and patches: each line by its first character.

pub fn diff(text: []const u8, i: *usize, _: *u64) Token {
    const from = i.*;
    const eol = std.mem.indexOfScalarPos(u8, text, from, '\n') orelse text.len;
    const line = text[from..eol];
    if (line.len == 0 or !atLineStart(text, from)) {
        i.* = if (eol > from) eol else from + 1;
        return .none;
    }
    i.* = eol;
    if (std.mem.startsWith(u8, line, "+++") or std.mem.startsWith(u8, line, "---")) return .heading;
    if (std.mem.startsWith(u8, line, "@@")) return .keyword;
    if (std.mem.startsWith(u8, line, "diff ") or std.mem.startsWith(u8, line, "index ")) return .comment;
    return switch (line[0]) {
        '+' => .added,
        '-' => .removed,
        else => .none,
    };
}
