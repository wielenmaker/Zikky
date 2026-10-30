//! Keys for the terminal: a gooey key press becomes Ghostty's key event and
//! is encoded for the shell the way the terminal's modes ask (application
//! cursor keys, Kitty keyboard protocol…). ⌘V pastes.

const std = @import("std");
const gooey = @import("gooey");
const vt = @import("ghostty-vt");
const Session = @import("term_session.zig").Session;

const KeyCode = gooey.input.KeyCode;
const Key = vt.input.Key;

pub fn press(session: *Session, k: gooey.input.KeyEvent) void {
    const text = k.characters orelse "";
    // Text the key types (not a control character); ctrl keys are encoded from the key.
    const typed = text.len > 0 and text[0] >= 0x20 and text[0] != 0x7f and !k.modifiers.ctrl;
    const plain = k.characters_ignoring_modifiers orelse "";
    const event = vt.input.KeyEvent{
        .key = key(k.key),
        .mods = .{ .shift = k.modifiers.shift, .ctrl = k.modifiers.ctrl, .alt = k.modifiers.alt },
        .consumed_mods = .{ .shift = typed and k.modifiers.shift },
        .utf8 = if (typed) text else "",
        .unshifted_codepoint = if (plain.len > 0) std.unicode.utf8Decode(plain[0 .. std.unicode.utf8ByteSequenceLength(plain[0]) catch 1]) catch 0 else 0,
    };
    session.lock();
    const opts = vt.input.KeyEncodeOptions.fromTerminal(&session.terminal);
    session.unlock();
    var buf: [128]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    vt.input.encodeKey(&w, event, opts) catch return;
    session.write(w.buffered());
}

/// ⌘V: the clipboard, bracketed when the shell asked for it.
pub fn paste(session: *Session) void {
    const a = std.heap.page_allocator;
    const text = gooey.platform.macos.clipboard.getText(a) orelse return;
    defer a.free(text);
    session.lock();
    const bracketed = session.terminal.modes.get(.bracketed_paste);
    session.unlock();
    if (bracketed) session.write("\x1b[200~");
    session.write(text);
    if (bracketed) session.write("\x1b[201~");
}

/// Ghostty's name for a physical key (W3C codes); gooey uses Mac names.
fn key(k: KeyCode) Key {
    return switch (k) {
        .left => .arrow_left,
        .right => .arrow_right,
        .up => .arrow_up,
        .down => .arrow_down,
        .@"return" => .enter,
        .delete => .backspace,
        .forward_delete => .delete,
        .left_bracket => .bracket_left,
        .right_bracket => .bracket_right,
        .grave => .backquote,
        .keypad_plus => .numpad_add,
        .keypad_minus => .numpad_subtract,
        .keypad_multiply => .numpad_multiply,
        .keypad_divide => .numpad_divide,
        .keypad_decimal => .numpad_decimal,
        .keypad_enter => .numpad_enter,
        .keypad_equals => .numpad_equal,
        else => {
            // The rest share a name, give or take a prefix (KeyCode is non-exhaustive).
            const info = @typeInfo(KeyCode).@"enum";
            inline for (info.field_names, info.field_values) |name, value| {
                if (@intFromEnum(k) == value) return comptime byName(name);
            }
            return .unidentified;
        },
    };
}

fn byName(comptime name: []const u8) Key {
    if (name.len == 1 and std.ascii.isLower(name[0])) return @field(Key, "key_" ++ name);
    if (name.len == 1 and std.ascii.isDigit(name[0])) return @field(Key, "digit_" ++ name);
    if (std.mem.startsWith(u8, name, "keypad_") and name.len == 8) return @field(Key, "numpad_" ++ name[7..]);
    if (@hasField(Key, name)) return @field(Key, name);
    return .unidentified;
}
