//! Token lexers for code and config files: one configurable lexer covers each
//! family (Zig, Rust, C-like, JS/TS, Python, Ruby/Lua, shell, JSON, YAML, TOML,
//! INI, HCL/Terraform, SQL, Dockerfile, Makefile).

const std = @import("std");

pub const Token = enum(u8) { none, comment, string, number, keyword, type, call, key, tag, attr, heading, link, code, emphasis, punct, variable, added, removed };

/// Lexes one token at `i.*` (or skips one byte, returning `.none`) and moves
/// past it; it always advances. `state` carries context between tokens (inside
/// a tag, a code fence…) and is kept with the cached spans.
pub const Next = *const fn (text: []const u8, i: *usize, state: *u64) Token;

const Lang = struct {
    keywords: []const []const u8,
    /// Built-in type names; Capitalized names count as types too when `capital_types`.
    types: []const []const u8 = &.{},
    capital_types: bool = true,
    line_comments: []const []const u8 = &.{"//"},
    block_comment: bool = true,
    /// `'…'` is a string; otherwise only a short char literal like `'a'` or `'\n'`.
    single_quote_strings: bool = false,
    backtick_strings: bool = false,
    triple_quotes: bool = false,
    /// Zig's `\\` multiline string lines.
    zig_lines: bool = false,
    /// Rust's `name!(…)` macro calls.
    macros: bool = false,
    /// Keywords match in any case (listed lowercase): SQL, Dockerfile.
    ci_keywords: bool = false,
    /// Only a line's first word can be a keyword (Dockerfile instructions).
    keywords_line_start: bool = false,
    /// `name: ` and `"name":` are keys (YAML, JSON, Makefile targets).
    colon_keys: bool = false,
    /// A line's leading `name =` (or `a.b =`, `:=`, `?=`, `+=`) is a key (TOML, INI, HCL, Makefile).
    equals_keys: bool = false,
    /// `[section]` at a line's start is a heading (TOML, INI).
    sections: bool = false,
    /// `-` continues a name (`cidr-block`, `my-target`).
    dash_names: bool = false,
    /// `$name`, `${…}`, `$(…)` are variables.
    dollar_vars: bool = false,
};

const zig_lang = Lang{
    .keywords = &.{ "const", "var", "fn", "pub", "return", "if", "else", "while", "for", "switch", "break", "continue", "defer", "errdefer", "try", "catch", "orelse", "and", "or", "struct", "enum", "union", "error", "test", "comptime", "inline", "noinline", "export", "extern", "packed", "unreachable", "undefined", "null", "true", "false", "threadlocal", "usingnamespace", "anytype", "opaque", "async", "await", "suspend", "resume", "callconv", "noreturn", "linksection", "volatile", "allowzero", "align" },
    .types = &.{ "u8", "u16", "u32", "u64", "u128", "usize", "i8", "i16", "i32", "i64", "i128", "isize", "f16", "f32", "f64", "f128", "bool", "void", "type", "anyerror", "anyopaque", "c_int", "comptime_int", "comptime_float" },
    .block_comment = false,
    .zig_lines = true,
};

const rust_lang = Lang{
    .keywords = &.{ "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while" },
    .types = &.{ "u8", "u16", "u32", "u64", "u128", "usize", "i8", "i16", "i32", "i64", "i128", "isize", "f32", "f64", "bool", "char", "str" },
    .macros = true,
};

const c_like_lang = Lang{
    .keywords = &.{ "auto", "break", "case", "catch", "class", "const", "constexpr", "continue", "default", "delete", "do", "else", "enum", "extends", "extern", "false", "final", "finally", "for", "func", "go", "goto", "if", "implements", "import", "inline", "interface", "let", "namespace", "new", "nil", "null", "nullptr", "override", "package", "private", "protected", "public", "return", "sizeof", "static", "struct", "switch", "template", "this", "throw", "throws", "true", "try", "typedef", "typename", "union", "using", "var", "virtual", "void", "volatile", "while", "defer", "range", "chan", "select", "map", "type", "guard", "self", "init", "in", "fun", "val", "when", "object", "#include", "#define", "#if", "#ifdef", "#ifndef", "#endif", "#else", "#pragma" },
    .types = &.{ "int", "char", "short", "long", "float", "double", "unsigned", "signed", "bool", "boolean", "byte", "string", "size_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t", "error", "uint", "int64", "int32", "float64", "rune" },
    .backtick_strings = true,
};

const js_lang = Lang{
    .keywords = &.{ "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null", "of", "private", "protected", "public", "readonly", "return", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "yield", "as", "declare", "namespace", "keyof" },
    .types = &.{ "string", "number", "boolean", "any", "unknown", "never", "object", "symbol", "bigint" },
    .single_quote_strings = true,
    .backtick_strings = true,
};

const python_lang = Lang{
    .keywords = &.{ "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield", "self", "match", "case" },
    .types = &.{ "int", "str", "float", "bool", "list", "dict", "set", "tuple", "bytes", "object" },
    .line_comments = &.{"#"},
    .block_comment = false,
    .single_quote_strings = true,
    .triple_quotes = true,
};

const ruby_lua_lang = Lang{
    .keywords = &.{ "and", "begin", "break", "case", "class", "def", "do", "else", "elsif", "elseif", "end", "ensure", "false", "for", "function", "if", "in", "local", "module", "next", "nil", "not", "or", "repeat", "require", "rescue", "return", "self", "then", "true", "unless", "until", "when", "while", "yield" },
    .line_comments = &.{"#"},
    .block_comment = false,
    .single_quote_strings = true,
};

const shell_lang = Lang{
    .keywords = &.{ "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in", "function", "return", "local", "export", "readonly", "set", "unset", "source", "echo", "exit", "cd", "shift", "true", "false" },
    .capital_types = false,
    .line_comments = &.{"#"},
    .block_comment = false,
    .single_quote_strings = true,
    .backtick_strings = true,
    .dollar_vars = true,
};

const json_lang = Lang{
    .keywords = &.{ "true", "false", "null" },
    .capital_types = false,
    .colon_keys = true,
};

const yaml_lang = Lang{
    .keywords = &.{ "true", "false", "null", "yes", "no", "on", "off", "True", "False", "Null" },
    .capital_types = false,
    .line_comments = &.{"#"},
    .block_comment = false,
    .single_quote_strings = true,
    .colon_keys = true,
    .dash_names = true,
};

const toml_lang = Lang{
    .keywords = &.{ "true", "false", "inf", "nan" },
    .capital_types = false,
    .line_comments = &.{"#"},
    .block_comment = false,
    .single_quote_strings = true,
    .triple_quotes = true,
    .equals_keys = true,
    .sections = true,
    .dash_names = true,
};

const ini_lang = Lang{
    .keywords = &.{ "true", "false", "yes", "no", "on", "off" },
    .capital_types = false,
    .line_comments = &.{ "#", ";" },
    .block_comment = false,
    .single_quote_strings = true,
    .equals_keys = true,
    .sections = true,
    .dash_names = true,
    .dollar_vars = true,
};

const hcl_lang = Lang{
    .keywords = &.{ "resource", "data", "variable", "output", "locals", "module", "provider", "terraform", "backend", "moved", "import", "check", "removed", "dynamic", "content", "for", "in", "if", "else", "endif", "endfor", "true", "false", "null", "each", "count", "var", "local", "self", "path" },
    .types = &.{ "string", "number", "bool", "list", "map", "set", "object", "tuple", "any" },
    .capital_types = false,
    .line_comments = &.{ "#", "//" },
    .equals_keys = true,
    .dash_names = true,
};

const sql_lang = Lang{
    .keywords = &.{ "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table", "index", "view", "drop", "alter", "add", "column", "primary", "key", "foreign", "references", "join", "left", "right", "inner", "outer", "full", "cross", "on", "as", "and", "or", "not", "null", "is", "in", "exists", "between", "like", "ilike", "limit", "offset", "order", "by", "group", "having", "union", "all", "distinct", "case", "when", "then", "else", "end", "begin", "commit", "rollback", "transaction", "if", "default", "unique", "check", "constraint", "returning", "with", "recursive", "asc", "desc", "true", "false", "cascade", "grant", "revoke", "schema", "database", "function", "returns", "language", "trigger", "replace", "using", "conflict", "do", "nothing" },
    .types = &.{ "int", "integer", "bigint", "smallint", "serial", "bigserial", "text", "varchar", "char", "boolean", "bool", "date", "time", "timestamp", "timestamptz", "interval", "numeric", "decimal", "real", "float", "double", "json", "jsonb", "uuid", "blob", "bytea" },
    .capital_types = false,
    .line_comments = &.{"--"},
    .single_quote_strings = true,
    .ci_keywords = true,
};

const dockerfile_lang = Lang{
    .keywords = &.{ "from", "run", "cmd", "label", "maintainer", "expose", "env", "add", "copy", "entrypoint", "volume", "user", "workdir", "arg", "onbuild", "stopsignal", "healthcheck", "shell" },
    .capital_types = false,
    .line_comments = &.{"#"},
    .block_comment = false,
    .single_quote_strings = true,
    .ci_keywords = true,
    .keywords_line_start = true,
    .dollar_vars = true,
};

const make_lang = Lang{
    .keywords = &.{ "ifeq", "ifneq", "ifdef", "ifndef", "else", "endif", "include", "define", "endef", "export", "override", "sinclude", "vpath" },
    .capital_types = false,
    .line_comments = &.{"#"},
    .block_comment = false,
    .single_quote_strings = true,
    .colon_keys = true,
    .equals_keys = true,
    .dash_names = true,
    .dollar_vars = true,
};

pub const zig: Next = Lexer(zig_lang).next;
pub const rust: Next = Lexer(rust_lang).next;
pub const c_like: Next = Lexer(c_like_lang).next;
pub const js: Next = Lexer(js_lang).next;
pub const python: Next = Lexer(python_lang).next;
pub const ruby_lua: Next = Lexer(ruby_lua_lang).next;
pub const shell: Next = Lexer(shell_lang).next;
pub const json: Next = Lexer(json_lang).next;
pub const yaml: Next = Lexer(yaml_lang).next;
pub const toml: Next = Lexer(toml_lang).next;
pub const ini: Next = Lexer(ini_lang).next;
pub const hcl: Next = Lexer(hcl_lang).next;
pub const sql: Next = Lexer(sql_lang).next;
pub const dockerfile: Next = Lexer(dockerfile_lang).next;
pub const make: Next = Lexer(make_lang).next;

fn Lexer(comptime lang: Lang) type {
    return struct {
        /// Keywords sorted once so a word costs ~6 comparisons, not one per
        /// keyword (the linear scan dominated lexing a large file).
        const sorted_keywords = sorted(lang.keywords);

        fn next(text: []const u8, i: *usize, _: *u64) Token {
            const from = i.*;
            const rest = text[from..];
            const c = rest[0];
            inline for (lang.line_comments) |lc| if (std.mem.startsWith(u8, rest, lc)) return toLineEnd(text, i, .comment);
            if (lang.block_comment and std.mem.startsWith(u8, rest, "/*")) return until(text, i, 2, "*/", .comment);
            if (lang.zig_lines and std.mem.startsWith(u8, rest, "\\\\")) return toLineEnd(text, i, .string);
            if (lang.sections and c == '[' and atLineStart(text, from)) {
                const close = std.mem.indexOfScalarPos(u8, text, from, ']');
                const eol = std.mem.indexOfScalarPos(u8, text, from, '\n') orelse text.len;
                i.* = if (close) |e| if (e < eol) e + 1 else eol else eol;
                return .heading;
            }
            if (lang.triple_quotes and (std.mem.startsWith(u8, rest, "\"\"\"") or std.mem.startsWith(u8, rest, "'''")))
                return until(text, i, 3, rest[0..3], .string);
            if (c == '"' or (c == '`' and lang.backtick_strings) or (c == '\'' and (lang.single_quote_strings or isCharLiteral(rest)))) {
                _ = quoted(text, i, c);
                return if (lang.colon_keys and colonAfter(text[i.*..], false)) .key else .string;
            }
            if (lang.dollar_vars and c == '$' and rest.len > 1) return variable(text, i);
            if (std.ascii.isDigit(c)) {
                i.* += 1;
                while (i.* < text.len and (isIdent(text[i.*]) or text[i.*] == '.')) i.* += 1;
                return .number;
            }
            if (isIdent(c) or c == '@' or c == '#' or (lang.ci_keywords and c == '-' and rest.len > 1 and std.ascii.isAlphabetic(rest[1]))) {
                i.* += 1;
                while (i.* < text.len and (isIdent(text[i.*]) or (lang.dash_names and text[i.*] == '-'))) i.* += 1;
                return classify(text, from, i);
            }
            i.* += 1;
            return .none;
        }

        fn classify(text: []const u8, from: usize, i: *usize) Token {
            const word = text[from..i.*];
            const after = text[i.*..];
            if (lang.colon_keys and colonAfter(after, true)) return .key;
            if (lang.equals_keys and atLineStart(text, from)) if (equalsAfter(after)) |tail| {
                i.* += tail;
                return .key;
            };
            if (!lang.keywords_line_start or atLineStart(text, from)) if (isKeyword(word)) return .keyword;
            if (isType(word)) return .type;
            const trimmed = std.mem.trimStart(u8, after, " ");
            if (word[0] == '@' or (trimmed.len > 0 and (trimmed[0] == '(' or (trimmed[0] == '!' and lang.macros)))) return .call;
            if (lang.capital_types and std.ascii.isUpper(word[0])) return .type;
            return .none;
        }

        fn isKeyword(word: []const u8) bool {
            var buf: [32]u8 = undefined;
            if (lang.ci_keywords and word.len > buf.len) return false;
            return find(&sorted_keywords, if (lang.ci_keywords) std.ascii.lowerString(&buf, word) else word);
        }

        fn isType(word: []const u8) bool {
            var buf: [32]u8 = undefined;
            if (lang.ci_keywords and word.len > buf.len) return false;
            const w = if (lang.ci_keywords) std.ascii.lowerString(&buf, word) else word;
            for (lang.types) |k| if (std.mem.eql(u8, k, w)) return true;
            return false;
        }
    };
}

fn sorted(comptime words: []const []const u8) [words.len][]const u8 {
    @setEvalBranchQuota(100_000);
    var out: [words.len][]const u8 = undefined;
    for (words, 0..) |w, i| out[i] = w;
    std.mem.sort([]const u8, &out, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);
    return out;
}

fn find(words: []const []const u8, word: []const u8) bool {
    var lo: usize = 0;
    var hi: usize = words.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        switch (std.mem.order(u8, word, words[mid])) {
            .lt => hi = mid,
            .gt => lo = mid + 1,
            .eq => return true,
        }
    }
    return false;
}

/// `:` after optional spaces; a bare name also needs a space or line end after
/// it (`url: http://x` is a key, `http://x` is not).
fn colonAfter(after: []const u8, bare: bool) bool {
    const rest = std.mem.trimStart(u8, after, " \t");
    if (rest.len == 0 or rest[0] != ':') return false;
    return !bare or rest.len == 1 or rest[1] == ' ' or rest[1] == '\t' or rest[1] == '\n' or rest[1] == '\r';
}

/// After a line's first name: the rest of a dotted key (`.b.c`) and then an
/// assignment (`=`, `:=`, `?=`, `+=`, not `==`). Returns the key's remaining length.
fn equalsAfter(after: []const u8) ?usize {
    var n: usize = 0;
    while (n < after.len and (isIdent(after[n]) or after[n] == '.' or after[n] == '-')) n += 1;
    var j = n;
    while (j < after.len and (after[j] == ' ' or after[j] == '\t')) j += 1;
    if (j < after.len and (after[j] == ':' or after[j] == '?' or after[j] == '+')) j += 1;
    if (j >= after.len or after[j] != '=') return null;
    if (j + 1 < after.len and after[j + 1] == '=') return null;
    return n;
}

/// Only spaces and tabs between the line's start and `pos`.
pub fn atLineStart(text: []const u8, pos: usize) bool {
    var j = pos;
    while (j > 0) : (j -= 1) switch (text[j - 1]) {
        '\n' => return true,
        ' ', '\t' => {},
        else => return false,
    };
    return true;
}

/// `$name`, `${…}`, `$(…)`, or a special like `$1` / `$@`.
fn variable(text: []const u8, i: *usize) Token {
    const open = text[i.* + 1];
    if (open == '{' or open == '(') {
        const close: u8 = if (open == '{') '}' else ')';
        const eol = std.mem.indexOfScalarPos(u8, text, i.*, '\n') orelse text.len;
        const end = std.mem.indexOfScalarPos(u8, text[0..eol], i.* + 2, close);
        i.* = if (end) |e| e + 1 else eol;
        return .variable;
    }
    i.* += 1;
    if (!isIdent(text[i.*])) {
        if (std.mem.indexOfScalar(u8, "@?#!*$<^%-", text[i.*]) == null) return .none;
        i.* += 1;
        return .variable;
    }
    while (i.* < text.len and isIdent(text[i.*])) i.* += 1;
    return .variable;
}

pub fn quoted(text: []const u8, i: *usize, quote: u8) Token {
    i.* += 1;
    while (i.* < text.len) : (i.* += 1) {
        switch (text[i.*]) {
            '\\' => i.* += 1,
            '\n' => if (quote != '`') return .string,
            else => if (text[i.*] == quote) {
                i.* += 1;
                return .string;
            },
        }
    }
    i.* = text.len;
    return .string;
}

pub fn toLineEnd(text: []const u8, i: *usize, t: Token) Token {
    i.* = std.mem.indexOfScalarPos(u8, text, i.*, '\n') orelse text.len;
    return t;
}

pub fn until(text: []const u8, i: *usize, open_len: usize, close: []const u8, t: Token) Token {
    const found = std.mem.indexOfPos(u8, text, @min(text.len, i.* + open_len), close);
    i.* = if (found) |f| f + close.len else text.len;
    return t;
}

/// `'a'`, `'\n'`, `'\u{1F600}'`: a short literal, not a Rust lifetime like `'a`.
fn isCharLiteral(rest: []const u8) bool {
    if (rest.len >= 3 and rest[1] == '\\') return std.mem.indexOfScalarPos(u8, rest[0..@min(rest.len, 12)], 2, '\'') != null;
    const len = std.unicode.utf8ByteSequenceLength(if (rest.len > 1) rest[1] else 0) catch 1;
    return rest.len > len + 1 and rest[len + 1] == '\'';
}

pub fn isIdent(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}
