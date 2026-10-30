//! TextAreaState - Multi-line text input engine with vertical scrolling
//!
//! Key differences from TextInputState:
//! - Handles newlines (\n) in text
//! - Vertical scrolling (renders only visible lines)
//! - Line index cache for O(log n) line lookup
//! - Up/down cursor navigation with preferred column
//! - Multi-line selection rendering
//!
//! Naming: this is the *engine* type — the heap-allocated state object
//! that owns the multi-line text buffer, line index, cursor, IME
//! composition, edit history, and focus state. The user-facing
//! declarative component is `components.TextArea` in
//! `components/src/text_area.zig`, which is what application code
//! constructs as a literal
//! (`TextArea{ .id = "...", .placeholder = "..." }`). The two types
//! used to share the name `TextArea`, which only worked as long as no
//! file imported both — the disambiguation is the prep work for PR 8.4
//! lifting `TextAreaState` onto the keyed `Window.element_states` pool.

const std = @import("std");
const builtin = @import("builtin");

// Clipboard support (platform-specific)
const clipboard = if (builtin.os.tag == .macos)
    @import("../platform/macos/clipboard.zig")
else if (builtin.os.tag == .freestanding and builtin.cpu.arch == .wasm32)
    @import("../platform/web/clipboard.zig")
else if (builtin.os.tag == .linux)
    @import("../platform/linux/clipboard.zig")
else
    struct {
        pub fn getText(_: std.mem.Allocator) ?[]const u8 {
            return null;
        }
        pub fn setText(_: []const u8) bool {
            return false;
        }
    };

const scene_mod = @import("../scene/mod.zig");
const input_mod = @import("../input/events.zig");
const text_mod = @import("../text/mod.zig");
// PR 8.4b — `core/element_id.zig` import retired alongside the
// `id: ElementId` field and `getId()` method. Same reduction
// `text_input_state.zig` does post-PR-8.4b: the engine type is
// keyed by `LayoutId.id` (a u32 hash) on `Window.element_states`,
// and the only reader of the field (`getId()`) was unused outside
// its own definition.
const common = @import("text_common.zig");
const history_mod = @import("edit_history.zig");
const focus_mod = @import("../context/focus.zig");
const EditHistory = history_mod.EditHistory;
const Edit = history_mod.Edit;

const Scene = scene_mod.Scene;
const Quad = scene_mod.Quad;
const Hsla = scene_mod.Hsla;
const GlyphInstance = scene_mod.GlyphInstance;
const TextSystem = text_mod.TextSystem;
const KeyCode = input_mod.KeyCode;
const InputEvent = input_mod.InputEvent;
const Modifiers = input_mod.Modifiers;

// Re-export shared utilities
pub const isCharBoundary = common.isCharBoundary;
pub const Selection = common.Selection;
pub const Position = common.Position;

/// Rectangle bounds for positioning.
///
/// Re-exports the shared flat hot-loop rectangle from `text_common.zig`,
/// which is the single source of truth for the text-widget family
/// (`TextInput` / `TextArea` / `CodeEditorState`). Keeping this `pub const`
/// alias preserves existing `text_area_state.Bounds` import paths in
/// `widgets/mod.zig`, `code_editor_state.zig`, and the
/// `Builder.DEFAULT_TEXT_AREA_BOUNDS` seed value (post-PR-8.4b:
/// pre-PR-8.4b the alias was also used by the retired
/// `WidgetStore.default_text_area_bounds` field). See
/// `text_common.Bounds` for the half-open `[x, x+w) x [y, y+h)`
/// hit-test rationale.
pub const Bounds = common.Bounds;

pub const Style = struct {
    /// Text color (dark gray, near black)
    text_color: Hsla = Hsla.init(0, 0, 0.1, 1),
    /// Placeholder text color (medium gray)
    placeholder_color: Hsla = Hsla.init(0, 0, 0.5, 1),
    /// Selection highlight color (blue tint, semi-transparent)
    selection_color: Hsla = Hsla.init(0.6, 0.8, 0.5, 0.35),
    /// Cursor color (dark gray)
    cursor_color: Hsla = Hsla.init(0, 0, 0.1, 1),
    /// Preedit underline color (for IME)
    preedit_underline_color: Hsla = Hsla.init(0, 0, 0.3, 1),
};

/// A byte range drawn in its own text color (syntax highlighting).
pub const Mark = struct {
    /// Start byte offset (inclusive)
    start: usize,
    /// End byte offset (exclusive)
    end: usize,
};

pub const ColorSpan = struct {
    /// Start byte offset (inclusive)
    start: usize,
    /// End byte offset (exclusive)
    end: usize,
    color: Hsla,

    pub fn init(start: usize, end: usize, color: Hsla) ColorSpan {
        std.debug.assert(start <= end);
        return .{ .start = start, .end = end, .color = color };
    }

    /// Check if this span overlaps with a byte range
    pub fn overlaps(self: ColorSpan, range_start: usize, range_end: usize) bool {
        return self.start < range_end and self.end > range_start;
    }
};

pub const ScrollbarStyle = struct {
    /// Show vertical scrollbar when content exceeds viewport
    show_vertical: bool = true,
    /// Scrollbar width
    scrollbar_size: f32 = 8,
    /// Padding around scrollbar
    scrollbar_padding: f32 = 2,
    /// Minimum thumb size
    min_thumb_size: f32 = 30,
    /// Track color (subtle, semi-transparent)
    track_color: Hsla = Hsla.init(0, 0, 0, 0.05),
    /// Thumb color
    thumb_color: Hsla = Hsla.init(0, 0, 0, 0.3),
    /// Thumb corner radius
    thumb_radius: f32 = 4,
};

/// TextAreaState — multi-line text input engine.
///
/// See file header for the engine-vs-component naming rationale.
pub const TextAreaState = struct {
    allocator: std.mem.Allocator,

    // PR 8.4b — `id: ElementId` field dropped (see file header for
    // rationale).

    // Geometry
    bounds: Bounds,
    style: Style,
    scrollbar_style: ScrollbarStyle = .{},

    // Text state (UTF-8 encoded)
    buffer: std.ArrayList(u8),

    // Line index: byte offset of each line start (always has at least one element: 0)
    line_starts: std.ArrayList(usize),
    /// While wrapping, the text line each row belongs to (for line numbers).
    row_lines: std.ArrayList(u32) = .empty,

    /// Cursor position as byte offset into buffer
    cursor_byte: usize = 0,

    /// Cached cursor row (line number, 0-based)
    cursor_row: usize = 0,

    /// Cached cursor column (byte offset within line)
    cursor_col: usize = 0,

    /// Selection anchor (byte offset), null if no selection
    selection_anchor: ?usize = null,

    /// Preferred column for up/down navigation (preserves horizontal position)
    /// Stored as byte offset within line
    preferred_column: ?usize = null,
    /// Draw the cursor as a block over the character (vim's normal mode).
    cursor_block: bool = false,
    /// Ease the cursor to each new position instead of jumping.
    cursor_glide: bool = false,
    /// Where the cursor is headed and where it started, relative to that,
    /// in content coordinates so scrolling doesn't glide it.
    glide_target: ?[2]f32 = null,
    glide_offset: [2]f32 = .{ 0, 0 },
    glide_start_us: i64 = 0,
    cursor_gliding: bool = false,

    // IME composition state
    preedit_buffer: std.ArrayList(u8),
    preedit_cursor: usize = 0,

    // Visual state
    focused: bool = false,
    cursor_visible: bool = true,
    last_blink_time: i64 = 0,

    // Scroll state
    scroll_offset_x: f32 = 0,
    /// Widest visible line, measured each render; bounds horizontal scroll.
    content_width: f32 = 0,
    /// Set when the cursor moves; the next render scrolls it into view horizontally.
    reveal_cursor_x: bool = false,
    /// Wrap long lines at the bounds' width instead of scrolling sideways.
    soft_wrap: bool = false,
    /// Columns per row while wrapping (0 = no wrap). The line index then holds
    /// visual rows, so cursor, selection, clicks and scrolling follow them.
    wrap_cols: usize = 0,
    scroll_offset_y: f32 = 0,

    /// Wheel scrolling eases the offset toward these targets over the next
    /// frames. Programmatic scrolling sets both and stops the animation.
    scroll_target_x: f32 = 0,
    scroll_target_y: f32 = 0,
    scroll_animating: bool = false,
    scroll_last_input_us: i64 = 0,
    scroll_last_step_us: i64 = 0,
    /// The wheel scroll already advanced for the frame being drawn.
    scroll_stepped: bool = false,
    /// When the frame being rendered will be shown (awake-clock µs; 0 = now).
    /// Easing steps by it so each frame moves by its real on-screen interval.
    frame_time_us: i64 = 0,
    /// Offset written by the last easing step; a different value next frame
    /// means something scrolled directly, so the target is re-synced.
    scroll_last_applied_x: f32 = 0,
    scroll_last_applied_y: f32 = 0,
    /// Continuous input (trackpad, momentum, a spinning wheel) is resampled
    /// rather than eased: its targets are kept with their input times and
    /// read back at a fixed delay behind each frame. Events land unevenly
    /// against vsync (0, 1 or 2 a frame); interpolating between them gives
    /// even motion at a small constant lag, where easing needed a long time
    /// constant, and so a long lag, to hide that unevenness.
    scroll_resampling: bool = false,
    /// How far ahead of the clock frames are shown (the display link's lead,
    /// ~1.5 frames: 12ms at 120Hz, 24ms at 60Hz), averaged, and the longest
    /// recent gap between continuous events (it rises quickly and decays
    /// slowly: a VM's events jitter 10-30ms apart). Their sum, plus slack,
    /// is how far behind a frame input is read, so a frame almost always
    /// falls between two samples whatever the refresh rate or event rate.
    scroll_lead_us: i64 = 0,
    scroll_gap_us: i64 = scroll_gap_init_us,
    /// The delay frames read input at, slewed toward that sum: a sudden
    /// change would stall or skip a frame; slewed, input plays a little
    /// slower or faster for a moment (0 = adopt it at once).
    scroll_delay_us: i64 = 0,
    scroll_samples: [scroll_samples_max]ScrollSample = undefined,
    scroll_sample_count: usize = 0,

    // Layout info (set during render)
    line_height: f32 = 0,
    viewport_height: f32 = 0,

    // Placeholder text
    placeholder: []const u8 = "",

    /// Colored ranges for the next render, sorted by start and non-overlapping;
    /// text outside them uses `style.text_color`.
    color_spans: []const ColorSpan = &.{},

    /// Ranges drawn behind the text in `mark_color` (search matches, say),
    /// sorted by start; set for the next render.
    marks: []const Mark = &.{},
    mark_color: Hsla = Hsla.init(0.13, 0.9, 0.5, 0.35),

    // Callbacks
    on_change: ?*const fn (*TextAreaState) void = null,

    /// Cursor rect for IME candidate window positioning (set during render)
    cursor_rect: struct { x: f32 = 0, y: f32 = 0, width: f32 = 1.5, height: f32 = 20 } = .{},

    /// Pending click position for cursor placement (processed during render when text_system is available)
    pending_click: ?struct { x: f32, y: f32 } = null,

    /// Edit history for undo/redo (heap-allocated, ~512KB)
    edit_history: ?*EditHistory = null,

    /// Bumped whenever the buffer changes. Derived caches (e.g. syntax
    /// highlighting) compare it instead of hashing the text each frame.
    revision: u64 = 0,

    const Self = @This();

    pub const BindingSync = enum {
        unchanged,
        applied,
        deferred_ime,
    };

    const BLINK_INTERVAL_MS: i64 = 530;

    /// Initialize TextAreaState.
    /// Marked noinline to prevent stack accumulation.
    ///
    /// PR 8.4b — `init` and `initWithId` collapsed into a single
    /// constructor now that `id: ElementId` is gone. The pre-PR-8.4b
    /// `init` ran a counter-derived id only because the field
    /// existed; with the field retired the counter was dead weight
    /// and the call sites split (`init` for tests, `initWithId` for
    /// `WidgetStore`) collapse onto a single shape.
    pub noinline fn init(allocator: std.mem.Allocator, bounds: Bounds) Self {
        var line_starts: std.ArrayList(usize) = .empty;
        line_starts.append(allocator, 0) catch {};

        return .{
            .allocator = allocator,
            .bounds = bounds,
            .style = .{},
            .buffer = .empty,
            .line_starts = line_starts,
            .preedit_buffer = .empty,
            .edit_history = EditHistory.create(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
        self.line_starts.deinit(self.allocator);
        self.row_lines.deinit(self.allocator);
        self.preedit_buffer.deinit(self.allocator);
        if (self.edit_history) |h| h.destroy(self.allocator);
    }

    // =========================================================================
    // Text Content
    // =========================================================================

    pub fn getText(self: *const Self) []const u8 {
        return self.buffer.items;
    }

    pub fn setText(self: *Self, text: []const u8) !void {
        // Handle aliasing (same as TextInput)
        const buf_start = @intFromPtr(self.buffer.items.ptr);
        const buf_end = buf_start + self.buffer.items.len;
        const text_start = @intFromPtr(text.ptr);
        const text_end = text_start + text.len;
        const aliases = text_start < buf_end and text_end > buf_start;

        if (aliases) {
            var temp: std.ArrayList(u8) = .empty;
            defer temp.deinit(self.allocator);

            try temp.appendSlice(self.allocator, text);
            self.buffer.clearRetainingCapacity();
            try self.buffer.appendSlice(self.allocator, temp.items);
        } else {
            self.buffer.clearRetainingCapacity();
            try self.buffer.appendSlice(self.allocator, text);
        }

        self.rebuildLineIndex();
        self.cursor_byte = @min(self.cursor_byte, self.buffer.items.len);
        self.updateCursorPosition();
        self.selection_anchor = null;
        self.revision +%= 1;
    }

    /// Reconcile a controlled binding while preserving valid editing offsets.
    /// IME preedit is never discarded by a render-time model update.
    pub fn syncBoundText(self: *Self, text: []const u8) !BindingSync {
        std.debug.assert(self.cursor_byte <= self.buffer.items.len);
        if (self.selection_anchor) |anchor| std.debug.assert(anchor <= self.buffer.items.len);
        if (std.mem.eql(u8, self.buffer.items, text)) return .unchanged;
        if (self.preedit_buffer.items.len > 0) return .deferred_ime;

        const selection_anchor = self.selection_anchor;
        try self.setText(text);
        self.cursor_byte = common.snapToCharBoundary(text, @min(self.cursor_byte, text.len));
        self.selection_anchor = if (selection_anchor) |anchor|
            common.snapToCharBoundary(text, @min(anchor, text.len))
        else
            null;
        if (self.selection_anchor == self.cursor_byte) self.selection_anchor = null;
        self.updateCursorPosition();
        self.preferred_column = null;
        self.clearHistory();
        return .applied;
    }

    pub fn clear(self: *Self) void {
        self.buffer.clearRetainingCapacity();
        self.line_starts.clearRetainingCapacity();
        self.line_starts.append(self.allocator, 0) catch {};
        self.cursor_byte = 0;
        self.cursor_row = 0;
        self.cursor_col = 0;
        self.selection_anchor = null;
        self.notifyChange();
    }

    pub fn setPlaceholder(self: *Self, placeholder: []const u8) void {
        self.placeholder = placeholder;
    }

    // =========================================================================
    // Line Index Management
    // =========================================================================

    /// Rebuild the entire line index from scratch. While wrapping, a row
    /// that reaches `wrap_cols` breaks after its last space, or mid-word if it has none.
    fn rebuildLineIndex(self: *Self) void {
        self.line_starts.clearRetainingCapacity();
        self.line_starts.append(self.allocator, 0) catch return;
        self.row_lines.clearRetainingCapacity();
        const wrapping = self.wrap_cols > 0;
        if (wrapping) self.row_lines.append(self.allocator, 0) catch return;

        const text = self.buffer.items;
        var line: u32 = 0;
        var cols: usize = 0;
        var after_space: ?usize = null;
        var i: usize = 0;
        while (i < text.len) {
            if (text[i] == '\n') {
                i += 1;
                cols = 0;
                after_space = null;
                line += 1;
                self.line_starts.append(self.allocator, i) catch return;
                if (wrapping) self.row_lines.append(self.allocator, line) catch return;
                continue;
            }
            if (self.wrap_cols > 0 and cols == self.wrap_cols) {
                const brk = after_space orelse i;
                self.line_starts.append(self.allocator, brk) catch return;
                self.row_lines.append(self.allocator, line) catch return;
                cols = std.unicode.utf8CountCodepoints(text[brk..i]) catch i - brk;
                after_space = null;
            }
            if (text[i] == ' ') after_space = i + 1;
            cols += 1;
            i = common.nextCharBoundary(text, i);
        }
    }

    /// Whether `row` begins a line of the text, not a wrapped continuation.
    pub fn isLineStart(self: *const Self, row: usize) bool {
        const start = self.lineStartOffset(row);
        return start == 0 or self.buffer.items[start - 1] == '\n';
    }

    /// 0-based line of the text (not visual row) that `row` belongs to.
    pub fn textLine(self: *const Self, row: usize) usize {
        // Unwrapped, rows are lines; wrapped, the index records them.
        if (self.wrap_cols == 0) return row;
        if (row < self.row_lines.items.len) return self.row_lines.items[row];
        return std.mem.count(u8, self.buffer.items[0..self.lineStartOffset(row)], "\n");
    }

    /// Get the number of lines
    pub fn lineCount(self: *const Self) usize {
        return self.line_starts.items.len;
    }

    /// Find which line a byte offset is on (binary search)
    pub fn lineForOffset(self: *const Self, offset: usize) usize {
        const starts = self.line_starts.items;
        if (starts.len == 0) return 0;

        var low: usize = 0;
        var high: usize = starts.len;

        while (low < high) {
            const mid = low + (high - low) / 2;
            if (starts[mid] <= offset) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return if (low > 0) low - 1 else 0;
    }

    /// Get the byte offset for the start of a line
    pub fn lineStartOffset(self: *const Self, row: usize) usize {
        if (row >= self.line_starts.items.len) {
            return self.buffer.items.len;
        }
        return self.line_starts.items[row];
    }

    /// Get the byte offset for the end of a line (before \n or end of buffer)
    pub fn lineEndOffset(self: *const Self, row: usize) usize {
        if (row + 1 < self.line_starts.items.len) {
            // End is one before the next line start (the \n), or at it for a wrapped row
            const next = self.line_starts.items[row + 1];
            return if (self.buffer.items[next - 1] == '\n') next - 1 else next;
        }
        return self.buffer.items.len;
    }

    /// Get the text content of a specific line (without trailing \n)
    pub fn lineContent(self: *const Self, row: usize) []const u8 {
        const start = self.lineStartOffset(row);
        const end = self.lineEndOffset(row);
        return self.buffer.items[start..end];
    }

    /// Update cursor row/col from cursor_byte
    fn updateCursorPosition(self: *Self) void {
        self.cursor_row = self.lineForOffset(self.cursor_byte);
        const line_start = self.lineStartOffset(self.cursor_row);
        self.cursor_col = self.cursor_byte - line_start;
    }

    /// Update line index incrementally after inserting text at position
    fn updateLineIndexAfterInsert(self: *Self, insert_pos: usize, inserted_text: []const u8) void {
        // Count newlines in inserted text and their positions
        var new_line_offsets: std.ArrayList(usize) = .empty;
        defer new_line_offsets.deinit(self.allocator);

        for (inserted_text, 0..) |c, i| {
            if (c == '\n') {
                new_line_offsets.append(self.allocator, insert_pos + i + 1) catch return;
            }
        }

        if (new_line_offsets.items.len == 0 and inserted_text.len > 0 and self.wrap_cols == 0) {
            // No newlines inserted, just shift subsequent line starts
            for (self.line_starts.items) |*start| {
                if (start.* > insert_pos) {
                    start.* += inserted_text.len;
                }
            }
            return;
        }

        // Rebuild is simpler for now - optimize later if needed
        self.rebuildLineIndex();
    }

    /// Update line index after deleting a range
    fn updateLineIndexAfterDelete(self: *Self, _: usize, _: usize) void {
        // For simplicity, rebuild. Could be optimized for incremental updates.
        self.rebuildLineIndex();
    }

    // =========================================================================
    // Focus
    // =========================================================================

    pub fn focus(self: *Self) void {
        self.focused = true;
        self.cursor_visible = true;
        self.last_blink_time = getTimestamp();
    }

    pub fn blur(self: *Self) void {
        self.focused = false;
        self.preedit_buffer.clearRetainingCapacity();
    }

    pub fn isFocused(self: *const Self) bool {
        return self.focused;
    }

    /// Build a `Focusable` trait for this widget instance. Called by
    /// the UI builder during render so the framework can drive focus
    /// without importing the widget type — see PR 4 in
    /// `docs/cleanup-implementation-plan.md`. The vtable is shared
    /// across all `TextAreaState` instances and lives in static storage.
    pub fn focusable(self: *Self) focus_mod.Focusable {
        return focus_mod.Focusable.fromInstance(Self, self);
    }

    pub fn maxScrollY(self: *const Self) f32 {
        const content_height = @as(f32, @floatFromInt(self.lineCount())) * self.line_height;
        return @max(0, content_height - self.viewport_height);
    }

    /// Room past the widest line so the caret at its end stays visible.
    const scroll_margin_x: f32 = 2;

    /// Wheel event gaps below this are a trackpad (or a spinning wheel).
    const scroll_fast_gap_us: i64 = 30_000;
    /// A continuous stream stays one until a gap this long (events jitter,
    /// up to 30ms apart in a VM), and holds its last sample until then.
    const scroll_stream_gap_us: i64 = 60_000;
    const scroll_gap_init_us: i64 = 10_000;
    /// Time constant easing each discrete notch, so it glides.
    const scroll_tau_ms: f32 = 45;
    /// Assumed frame time for the first step after a pause.
    const scroll_default_dt_us: i64 = 8_333;
    const scroll_samples_max = 8;
    const scroll_lead_max_us: i64 = 50_000;

    const ScrollSample = struct { t_us: i64, x: f32, y: f32 };

    fn maxScrollX(self: *const Self) f32 {
        return @max(0, self.content_width + scroll_margin_x - self.bounds.width);
    }

    /// Scrolls immediately (cursor reveal, programmatic jumps), clamped.
    pub fn scrollBy(self: *Self, dx: f32, dy: f32) void {
        self.scroll_offset_x = std.math.clamp(self.scroll_offset_x - dx, 0, self.maxScrollX());
        self.scroll_offset_y = std.math.clamp(self.scroll_offset_y - dy, 0, self.maxScrollY());
        self.syncScrollTarget();
    }

    /// Integrates a wheel delta into the target. A precise device (trackpad)
    /// and frequent events (a spinning wheel) are resampled; sparse ones (a
    /// line wheel) are eased, so each notch glides instead of jumping 20px on
    /// one frame. `time_us` is when the input happened (0 = now): arrival
    /// times jitter, which resampling shows.
    pub fn scrollBySmooth(self: *Self, dx: f32, dy: f32, time_us: i64, precise: bool) void {
        const now = if (time_us != 0) time_us else getTimestampUs();
        const gap = if (self.scroll_last_input_us == 0) std.math.maxInt(i64) else now - self.scroll_last_input_us;
        self.scroll_last_input_us = now;
        const streaming = self.scroll_animating and self.scroll_resampling;
        const continuous = precise or gap < if (streaming) scroll_stream_gap_us else scroll_fast_gap_us;
        if (gap < scroll_stream_gap_us) {
            const d = gap - self.scroll_gap_us;
            self.scroll_gap_us += if (d > 0) @divTrunc(d, 2) else @divTrunc(d, 32);
        }

        // Start from, or rebase on, where the offset actually is: a cursor
        // reveal may have moved it since the last frame.
        const moved = @abs(self.scroll_offset_x - self.scroll_last_applied_x) > 0.01 or
            @abs(self.scroll_offset_y - self.scroll_last_applied_y) > 0.01;
        if (!self.scroll_animating or moved) {
            self.scroll_target_x = self.scroll_offset_x;
            self.scroll_target_y = self.scroll_offset_y;
            self.scroll_last_step_us = now;
            self.scroll_last_applied_x = self.scroll_offset_x;
            self.scroll_last_applied_y = self.scroll_offset_y;
        }
        // Resampling (re)starts from the offset as it is now.
        if (!self.scroll_animating or moved or continuous != self.scroll_resampling) {
            self.scroll_samples[0] = .{ .t_us = now - self.scroll_gap_us, .x = self.scroll_offset_x, .y = self.scroll_offset_y };
            self.scroll_sample_count = 1;
            self.scroll_delay_us = 0;
        }
        self.scroll_resampling = continuous;
        self.scroll_target_x = std.math.clamp(self.scroll_target_x - dx, 0, self.maxScrollX());
        self.scroll_target_y = std.math.clamp(self.scroll_target_y - dy, 0, self.maxScrollY());

        if (self.scroll_sample_count == scroll_samples_max) {
            std.mem.copyForwards(ScrollSample, self.scroll_samples[0 .. scroll_samples_max - 1], self.scroll_samples[1..]);
            self.scroll_sample_count -= 1;
        }
        self.scroll_samples[self.scroll_sample_count] = .{ .t_us = now, .x = self.scroll_target_x, .y = self.scroll_target_y };
        self.scroll_sample_count += 1;
        self.scroll_animating = true;
    }

    /// Stops easing and adopts the current offset as the target.
    fn syncScrollTarget(self: *Self) void {
        self.scroll_target_x = self.scroll_offset_x;
        self.scroll_target_y = self.scroll_offset_y;
        self.scroll_animating = false;
        self.scroll_last_applied_x = self.scroll_offset_x;
        self.scroll_last_applied_y = self.scroll_offset_y;
    }

    /// Advances the wheel scroll for the frame being drawn, once: an editor
    /// calls it before drawing what reads the offset (gutter, highlighting),
    /// so those move with the text instead of a frame behind it.
    pub fn stepScroll(self: *Self) void {
        if (self.scroll_stepped) return;
        self.scroll_stepped = true;
        self.updateSmoothScroll();
    }

    /// Advances the eased offset one frame toward the wheel target. Called
    /// from `render` before the visible lines are computed, so drawing,
    /// hit-testing, the gutter and the syntax window all see the same value.
    fn updateSmoothScroll(self: *Self) void {
        if (!self.scroll_animating) {
            self.scroll_last_applied_x = self.scroll_offset_x;
            self.scroll_last_applied_y = self.scroll_offset_y;
            return;
        }

        // A cursor reveal or programmatic scroll moved the offset directly;
        // adopt it rather than pulling it back toward a stale target.
        if (@abs(self.scroll_offset_x - self.scroll_last_applied_x) > 0.01 or
            @abs(self.scroll_offset_y - self.scroll_last_applied_y) > 0.01)
        {
            self.syncScrollTarget();
            return;
        }

        self.scroll_target_x = std.math.clamp(self.scroll_target_x, 0, self.maxScrollX());
        self.scroll_target_y = std.math.clamp(self.scroll_target_y, 0, self.maxScrollY());

        const now = if (self.frame_time_us != 0) self.frame_time_us else getTimestampUs();
        if (self.frame_time_us != 0) {
            const lead = std.math.clamp(self.frame_time_us - getTimestampUs(), 0, scroll_lead_max_us);
            self.scroll_lead_us = if (self.scroll_lead_us == 0) lead else self.scroll_lead_us + @divTrunc(lead - self.scroll_lead_us, 8);
        }
        if (self.scroll_resampling) {
            self.slewScrollDelay(now);
            self.resampleScroll(now - self.scroll_delay_us);
            self.scroll_last_step_us = now;
            self.scroll_last_applied_x = self.scroll_offset_x;
            self.scroll_last_applied_y = self.scroll_offset_y;
            return;
        }
        var dt_us = now - self.scroll_last_step_us;
        if (dt_us <= 0 or dt_us > 50_000) dt_us = scroll_default_dt_us;
        const tau_us = scroll_tau_ms * 1000;
        const alpha = 1 - @exp(-@as(f32, @floatFromInt(dt_us)) / tau_us);

        const dx = self.scroll_target_x - self.scroll_offset_x;
        const dy = self.scroll_target_y - self.scroll_offset_y;
        self.scroll_offset_x = std.math.clamp(self.scroll_offset_x + dx * alpha, 0, self.maxScrollX());
        self.scroll_offset_y = std.math.clamp(self.scroll_offset_y + dy * alpha, 0, self.maxScrollY());
        self.scroll_last_step_us = now;

        if (@abs(dx) < 0.05 and @abs(dy) < 0.05) {
            self.scroll_offset_x = self.scroll_target_x;
            self.scroll_offset_y = self.scroll_target_y;
            self.scroll_animating = false;
        }
        self.scroll_last_applied_x = self.scroll_offset_x;
        self.scroll_last_applied_y = self.scroll_offset_y;
    }

    /// How far behind a frame's presentation time continuous input should be
    /// read: the lead plus the recent longest event gap and slack.
    fn scrollResampleDelayUs(self: *const Self) i64 {
        return self.scroll_lead_us + self.scroll_gap_us + 2_000;
    }

    /// Moves the applied delay toward `scrollResampleDelayUs`, per frame at
    /// most a quarter of its interval longer (input plays at 3/4 speed) or a
    /// sixteenth shorter, whatever the refresh rate.
    fn slewScrollDelay(self: *Self, now: i64) void {
        const target = self.scrollResampleDelayUs();
        if (self.scroll_delay_us == 0) {
            self.scroll_delay_us = target;
            return;
        }
        var dt_us = now - self.scroll_last_step_us;
        if (dt_us <= 0 or dt_us > 50_000) dt_us = scroll_default_dt_us;
        self.scroll_delay_us += std.math.clamp(target - self.scroll_delay_us, -@divTrunc(dt_us, 16), @divTrunc(dt_us, 4));
    }

    /// Sets the offset to the input as it was over the event gap before
    /// `t_us`, averaged: a trackpad's deltas are smooth but its timestamps
    /// jitter, so each segment between two samples has its own speed, and
    /// read at one point the speed jumps at every sample (on a real trackpad,
    /// ~10% per frame). Past the last sample it holds there, so a late event
    /// continues the stream; once the stream has gone quiet, scrolling is done.
    fn resampleScroll(self: *Self, t_us: i64) void {
        const last = self.scroll_samples[self.scroll_sample_count - 1];
        if (t_us - last.t_us >= scroll_stream_gap_us) {
            self.scroll_offset_x = last.x;
            self.scroll_offset_y = last.y;
            self.scroll_animating = false;
            return;
        }
        const n = 4;
        var x: f32 = 0;
        var y: f32 = 0;
        for (0..n) |k| {
            const p = self.scrollSampleAt(t_us - @divTrunc(self.scroll_gap_us * @as(i64, @intCast(k)), n - 1));
            x += p.x / n;
            y += p.y / n;
        }
        self.scroll_offset_x = std.math.clamp(x, 0, self.maxScrollX());
        self.scroll_offset_y = std.math.clamp(y, 0, self.maxScrollY());
    }

    /// The input at `t_us`, interpolated between the samples around it and
    /// held at either end.
    fn scrollSampleAt(self: *const Self, t_us: i64) ScrollSample {
        const s = self.scroll_samples[0..self.scroll_sample_count];
        var i = s.len - 1;
        if (t_us >= s[i].t_us) return s[i];
        while (i > 0 and s[i - 1].t_us > t_us) i -= 1;
        if (i == 0) return s[0];
        const a = s[i - 1];
        const b = s[i];
        const f = @as(f32, @floatFromInt(t_us - a.t_us)) / @as(f32, @floatFromInt(b.t_us - a.t_us));
        return .{ .t_us = t_us, .x = a.x + (b.x - a.x) * f, .y = a.y + (b.y - a.y) * f };
    }

    pub fn isScrollAnimating(self: *const Self) bool {
        return self.scroll_animating;
    }

    pub fn getBounds(self: *const Self) struct { x: f32, y: f32, width: f32, height: f32 } {
        return .{
            .x = self.bounds.x,
            .y = self.bounds.y,
            .width = self.bounds.width,
            .height = self.bounds.height,
        };
    }

    pub fn canFocus(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn onFocus(self: *Self) void {
        self.focus();
    }

    pub fn onBlur(self: *Self) void {
        self.blur();
    }

    // =========================================================================
    // Text Editing
    // =========================================================================

    pub fn insertText(self: *Self, text: []const u8) !void {
        // Skip empty inserts
        if (text.len == 0) return;

        // Save state for history before any modifications
        const cursor_before: u32 = @intCast(self.cursor_byte);
        const anchor_before: ?u32 = if (self.selection_anchor) |a| @intCast(a) else null;
        const insert_offset: u32 = @intCast(self.selectionStart());

        // Handle selection replacement as a single compound edit
        const had_selection = self.hasSelection();
        var deleted_text_buf: [history_mod.MAX_EDIT_BYTES]u8 = undefined;
        var deleted_len: usize = 0;

        if (had_selection) {
            // Save deleted text for compound edit before deleting
            const start = self.selectionStart();
            const end = self.selectionEnd();
            deleted_len = end - start;
            if (deleted_len <= history_mod.MAX_EDIT_BYTES) {
                @memcpy(deleted_text_buf[0..deleted_len], self.buffer.items[start..end]);
            }
            // Delete without recording history (we'll record a compound replace instead)
            self.deleteSelection();
        }

        try self.buffer.insertSlice(self.allocator, self.cursor_byte, text);
        self.updateLineIndexAfterInsert(self.cursor_byte, text);

        // Record in history
        if (self.edit_history) |h| {
            if (had_selection and deleted_len > 0 and deleted_len <= history_mod.MAX_EDIT_BYTES) {
                // Compound replace edit (single undo step for delete + insert)
                if (Edit.makeReplace(
                    insert_offset,
                    deleted_text_buf[0..deleted_len],
                    text,
                    cursor_before,
                    anchor_before,
                    getTimestamp(),
                )) |edit| {
                    h.push(edit);
                }
            } else if (!had_selection and text.len <= history_mod.MAX_EDIT_BYTES) {
                // Simple insert
                h.push(Edit.makeInsert(
                    insert_offset,
                    text,
                    cursor_before,
                    anchor_before,
                    getTimestamp(),
                ));
            }
        }

        self.cursor_byte += text.len;
        self.updateCursorPosition();
        self.ensureCursorVisible();
        self.preferred_column = null;

        self.preedit_buffer.clearRetainingCapacity();
        self.resetCursorBlink();
        self.notifyChange();
    }

    pub fn setComposition(self: *Self, text: []const u8) !void {
        self.preedit_buffer.clearRetainingCapacity();
        try self.preedit_buffer.appendSlice(self.allocator, text);
        self.preedit_cursor = text.len;
        self.resetCursorBlink();
    }

    pub fn handleKey(self: *Self, key: input_mod.KeyEvent) !void {
        const code = key.key;
        const mods = key.modifiers;

        switch (code) {
            .delete => {
                // Backspace; ⌘ deletes to line start, ⌥ to the previous word.
                if (!self.hasSelection() and self.cursor_byte > 0 and (mods.cmd or mods.alt)) {
                    const line_start = self.lineStartOffset(self.cursor_row);
                    self.selection_anchor = if (mods.cmd and line_start < self.cursor_byte)
                        line_start
                    else if (mods.alt)
                        common.prevWordBoundary(self.buffer.items, self.cursor_byte)
                    else
                        common.prevCharBoundary(self.buffer.items, self.cursor_byte);
                }
                if (self.hasSelection()) {
                    self.deleteSelectionWithHistory();
                } else if (self.cursor_byte > 0) {
                    const prev = common.prevCharBoundary(self.buffer.items, self.cursor_byte);
                    const char_len = self.cursor_byte - prev;

                    // Record in history before deleting
                    const deleted_text = self.buffer.items[prev..self.cursor_byte];
                    if (self.edit_history) |h| {
                        if (deleted_text.len <= history_mod.MAX_EDIT_BYTES) {
                            h.push(Edit.makeDelete(
                                @intCast(prev),
                                deleted_text,
                                @intCast(self.cursor_byte),
                                null,
                                getTimestamp(),
                            ));
                        }
                    }

                    for (0..char_len) |_| {
                        _ = self.buffer.orderedRemove(prev);
                    }
                    self.updateLineIndexAfterDelete(prev, self.cursor_byte);
                    self.cursor_byte = prev;
                    self.updateCursorPosition();
                    self.preferred_column = null;
                    self.notifyChange();
                }
            },
            .forward_delete => {
                // ⌘ deletes to line end, ⌥ to the next word.
                if (!self.hasSelection() and self.cursor_byte < self.buffer.items.len and (mods.cmd or mods.alt)) {
                    const line_end = self.lineEndOffset(self.cursor_row);
                    self.selection_anchor = if (mods.cmd and line_end > self.cursor_byte)
                        line_end
                    else if (mods.alt)
                        common.nextWordBoundary(self.buffer.items, self.cursor_byte)
                    else
                        common.nextCharBoundary(self.buffer.items, self.cursor_byte);
                }
                if (self.hasSelection()) {
                    self.deleteSelectionWithHistory();
                } else if (self.cursor_byte < self.buffer.items.len) {
                    const next = common.nextCharBoundary(self.buffer.items, self.cursor_byte);
                    const char_len = next - self.cursor_byte;

                    // Record in history before deleting
                    const deleted_text = self.buffer.items[self.cursor_byte..next];
                    if (self.edit_history) |h| {
                        if (deleted_text.len <= history_mod.MAX_EDIT_BYTES) {
                            h.push(Edit.makeDelete(
                                @intCast(self.cursor_byte),
                                deleted_text,
                                @intCast(self.cursor_byte),
                                null,
                                getTimestamp(),
                            ));
                        }
                    }

                    for (0..char_len) |_| {
                        _ = self.buffer.orderedRemove(self.cursor_byte);
                    }
                    self.updateLineIndexAfterDelete(self.cursor_byte, next);
                    self.updateCursorPosition();
                    self.notifyChange();
                }
            },
            .left => {
                if (mods.shift) {
                    if (self.selection_anchor == null) {
                        self.selection_anchor = self.cursor_byte;
                    }
                } else {
                    if (self.hasSelection()) {
                        self.cursor_byte = self.selectionStart();
                        self.selection_anchor = null;
                        self.updateCursorPosition();
                        self.preferred_column = null;
                        return;
                    }
                    self.selection_anchor = null;
                }
                if (mods.cmd) {
                    // Move to start of line
                    self.cursor_byte = self.lineStartOffset(self.cursor_row);
                } else if (mods.alt) {
                    self.cursor_byte = common.prevWordBoundary(self.buffer.items, self.cursor_byte);
                } else {
                    if (self.cursor_byte > 0) {
                        self.cursor_byte = common.prevCharBoundary(self.buffer.items, self.cursor_byte);
                    }
                }
                self.updateCursorPosition();
                self.preferred_column = null;
            },
            .right => {
                if (mods.shift) {
                    if (self.selection_anchor == null) {
                        self.selection_anchor = self.cursor_byte;
                    }
                } else {
                    if (self.hasSelection()) {
                        self.cursor_byte = self.selectionEnd();
                        self.selection_anchor = null;
                        self.updateCursorPosition();
                        self.preferred_column = null;
                        return;
                    }
                    self.selection_anchor = null;
                }
                if (mods.cmd) {
                    // Move to end of line
                    self.cursor_byte = self.lineEndOffset(self.cursor_row);
                } else if (mods.alt) {
                    self.cursor_byte = common.nextWordBoundary(self.buffer.items, self.cursor_byte);
                } else {
                    if (self.cursor_byte < self.buffer.items.len) {
                        self.cursor_byte = common.nextCharBoundary(self.buffer.items, self.cursor_byte);
                    }
                }
                self.updateCursorPosition();
                self.preferred_column = null;
            },
            .up => {
                if (mods.shift) {
                    if (self.selection_anchor == null) {
                        self.selection_anchor = self.cursor_byte;
                    }
                } else {
                    self.selection_anchor = null;
                }

                if (mods.cmd) {
                    // Move to start of document
                    self.cursor_byte = 0;
                    self.cursor_row = 0;
                    self.cursor_col = 0;
                    self.preferred_column = null;
                } else {
                    self.moveUp();
                }
            },
            .down => {
                if (mods.shift) {
                    if (self.selection_anchor == null) {
                        self.selection_anchor = self.cursor_byte;
                    }
                } else {
                    self.selection_anchor = null;
                }

                if (mods.cmd) {
                    // Move to end of document
                    self.cursor_byte = self.buffer.items.len;
                    self.updateCursorPosition();
                    self.preferred_column = null;
                } else {
                    self.moveDown();
                }
            },
            .a => {
                if (mods.cmd) {
                    // Select all
                    self.selection_anchor = 0;
                    self.cursor_byte = self.buffer.items.len;
                    self.updateCursorPosition();
                }
            },
            .c => {
                if (mods.cmd and self.hasSelection()) {
                    // Copy selection to clipboard
                    const start = self.selectionStart();
                    const end = self.selectionEnd();
                    const selected_text = self.buffer.items[start..end];
                    _ = clipboard.setText(selected_text);
                }
            },
            .v => {
                if (mods.cmd) {
                    // Paste from clipboard
                    if (clipboard.getText(self.allocator)) |text| {
                        defer self.allocator.free(text);
                        if (self.hasSelection()) {
                            self.deleteSelection();
                        }
                        self.insertText(text) catch {};
                    }
                }
            },
            .x => {
                if (mods.cmd and self.hasSelection()) {
                    // Cut = Copy + Delete
                    const start = self.selectionStart();
                    const end = self.selectionEnd();
                    const selected_text = self.buffer.items[start..end];
                    _ = clipboard.setText(selected_text);
                    self.deleteSelectionWithHistory();
                }
            },
            .z => {
                if (mods.cmd and !mods.shift) {
                    // Undo
                    self.applyUndo();
                } else if (mods.cmd and mods.shift) {
                    // Redo
                    self.applyRedo();
                }
            },
            .@"return" => {
                // Insert newline (multi-line support!)
                try self.insertText("\n");
            },
            else => {},
        }
        self.ensureCursorVisible();
        self.resetCursorBlink();
    }

    /// Move cursor up one line, preserving preferred column
    fn moveUp(self: *Self) void {
        if (self.cursor_row == 0) return;

        // Initialize preferred column if not set
        if (self.preferred_column == null) {
            self.preferred_column = self.cursor_col;
        }

        self.cursor_row -= 1;
        self.cursor_byte = self.clampColumnToLine(self.cursor_row, self.preferred_column.?);
        self.cursor_col = self.cursor_byte - self.lineStartOffset(self.cursor_row);
    }

    /// Move cursor down one line, preserving preferred column
    fn moveDown(self: *Self) void {
        if (self.cursor_row >= self.lineCount() - 1) return;

        if (self.preferred_column == null) {
            self.preferred_column = self.cursor_col;
        }

        self.cursor_row += 1;
        self.cursor_byte = self.clampColumnToLine(self.cursor_row, self.preferred_column.?);
        self.cursor_col = self.cursor_byte - self.lineStartOffset(self.cursor_row);
    }

    /// Convert a column offset to a valid byte position within a line
    fn clampColumnToLine(self: *const Self, row: usize, target_col: usize) usize {
        const line_start = self.lineStartOffset(row);
        const line_end = self.lineEndOffset(row);
        const line_len = line_end - line_start;

        const actual_col = @min(target_col, line_len);
        const byte_pos = line_start + actual_col;

        // Snap to char boundary
        return common.snapToCharBoundary(self.buffer.items, byte_pos);
    }

    // =========================================================================
    // Selection Helpers
    // =========================================================================

    /// Place the cursor at `cursor` (a codepoint boundary), selecting from `anchor`.
    pub fn select(self: *Self, anchor: ?usize, cursor: usize) void {
        self.selection_anchor = anchor;
        self.cursor_byte = @min(cursor, self.buffer.items.len);
        self.updateCursorPosition();
        self.preferred_column = null;
        self.ensureCursorVisible();
        self.resetCursorBlink();
    }

    pub fn hasSelection(self: *const Self) bool {
        return self.selection_anchor != null and self.selection_anchor.? != self.cursor_byte;
    }

    fn selectionStart(self: *const Self) usize {
        if (self.selection_anchor) |anchor| {
            return @min(anchor, self.cursor_byte);
        }
        return self.cursor_byte;
    }

    fn selectionEnd(self: *const Self) usize {
        if (self.selection_anchor) |anchor| {
            return @max(anchor, self.cursor_byte);
        }
        return self.cursor_byte;
    }

    /// Delete selection without recording history (used internally)
    fn deleteSelection(self: *Self) void {
        if (!self.hasSelection()) return;

        const start = self.selectionStart();
        const end = self.selectionEnd();
        const len = end - start;

        for (0..len) |_| {
            _ = self.buffer.orderedRemove(start);
        }

        self.updateLineIndexAfterDelete(start, end);
        self.cursor_byte = start;
        self.updateCursorPosition();
        self.selection_anchor = null;
        self.preferred_column = null;
        self.notifyChange();
    }

    /// Delete selection and record in history (used for standalone delete operations)
    fn deleteSelectionWithHistory(self: *Self) void {
        if (!self.hasSelection()) return;

        const start = self.selectionStart();
        const end = self.selectionEnd();
        const len = end - start;

        // Save deleted text for history before removing
        const deleted_text = self.buffer.items[start..end];
        if (self.edit_history) |h| {
            if (deleted_text.len <= history_mod.MAX_EDIT_BYTES) {
                h.push(Edit.makeDelete(
                    @intCast(start),
                    deleted_text,
                    @intCast(self.cursor_byte),
                    if (self.selection_anchor) |a| @intCast(a) else null,
                    getTimestamp(),
                ));
            }
        }

        for (0..len) |_| {
            _ = self.buffer.orderedRemove(start);
        }

        self.updateLineIndexAfterDelete(start, end);
        self.cursor_byte = start;
        self.updateCursorPosition();
        self.selection_anchor = null;
        self.preferred_column = null;
        self.notifyChange();
    }

    /// Select an entire line by row number (0-based)
    /// Sets selection from line start to line end (including newline if present)
    pub fn selectLine(self: *Self, row: usize) void {
        const line_count = self.lineCount();
        if (line_count == 0) return;

        const clamped_row = @min(row, line_count - 1);
        const start = self.lineStartOffset(clamped_row);

        // Selection end includes the newline character if this isn't the last line
        const end = if (clamped_row + 1 < line_count)
            self.lineStartOffset(clamped_row + 1)
        else
            self.buffer.items.len;

        // Assert offsets are valid within buffer bounds
        std.debug.assert(start <= self.buffer.items.len);
        std.debug.assert(end <= self.buffer.items.len);
        std.debug.assert(start <= end);

        // For line selection: anchor at end (including newline), cursor at start
        // This way selection spans the full line but cursor stays on selected line
        self.selection_anchor = end;
        self.cursor_byte = start;
        self.cursor_row = clamped_row;
        self.cursor_col = 0;
        self.preferred_column = null;
        self.ensureCursorVisible();
    }

    // =========================================================================
    // Undo/Redo
    // =========================================================================

    /// Apply an undo operation
    fn applyUndo(self: *Self) void {
        const h = self.edit_history orelse return;
        const edit = h.undo() orelse return;

        // Assertions: validate edit is applicable to current buffer state
        std.debug.assert(edit.op == .insert or edit.op == .delete or edit.op == .replace);
        std.debug.assert(edit.cursor_before <= self.buffer.items.len + edit.len); // cursor_before was valid

        h.beginApply();
        defer h.endApply();

        switch (edit.op) {
            .insert => {
                // Undo insert = delete the inserted text
                const start = edit.offset;
                const len = edit.len;
                const end = start + len;

                // Assert buffer has the content we're about to delete
                std.debug.assert(start + len <= self.buffer.items.len);

                for (0..len) |_| {
                    _ = self.buffer.orderedRemove(start);
                }
                self.updateLineIndexAfterDelete(start, end);
            },
            .delete => {
                // Undo delete = reinsert the deleted text
                const text = edit.getText();

                // Assert offset is valid for insertion
                std.debug.assert(edit.offset <= self.buffer.items.len);

                self.buffer.insertSlice(self.allocator, edit.offset, text) catch {
                    // Restore history state on allocation failure
                    h.undoUndo();
                    return;
                };
                self.updateLineIndexAfterInsert(edit.offset, text);
            },
            .replace => {
                // Undo replace = delete inserted text, reinsert deleted text
                const inserted_len = edit.len2;
                const deleted_text = edit.getDeletedText();

                // Assert buffer has the inserted content we're about to delete
                std.debug.assert(edit.offset + inserted_len <= self.buffer.items.len);

                // First, remove the inserted text
                for (0..inserted_len) |_| {
                    _ = self.buffer.orderedRemove(edit.offset);
                }
                self.updateLineIndexAfterDelete(edit.offset, edit.offset + inserted_len);

                // Then, reinsert the deleted text
                self.buffer.insertSlice(self.allocator, edit.offset, deleted_text) catch {
                    // Partial failure: we deleted but couldn't reinsert
                    // Restore history state - user can retry
                    h.undoUndo();
                    return;
                };
                self.updateLineIndexAfterInsert(edit.offset, deleted_text);
            },
        }

        // Restore cursor and selection state
        self.cursor_byte = edit.cursor_before;
        self.selection_anchor = if (edit.getAnchor()) |a| @as(usize, a) else null;
        self.updateCursorPosition();
        self.preferred_column = null;
        self.ensureCursorVisible();
        self.resetCursorBlink();
        self.notifyChange();
    }

    /// Apply a redo operation
    fn applyRedo(self: *Self) void {
        const h = self.edit_history orelse return;
        const edit = h.redo() orelse return;

        // Assertions: validate edit is applicable to current buffer state
        std.debug.assert(edit.op == .insert or edit.op == .delete or edit.op == .replace);
        std.debug.assert(edit.offset <= self.buffer.items.len);

        h.beginApply();
        defer h.endApply();

        switch (edit.op) {
            .insert => {
                // Redo insert = reinsert the text
                const text = edit.getText();

                // Assert offset is valid for insertion
                std.debug.assert(edit.offset <= self.buffer.items.len);

                self.buffer.insertSlice(self.allocator, edit.offset, text) catch {
                    // Restore history state on allocation failure
                    h.undoRedo();
                    return;
                };
                self.updateLineIndexAfterInsert(edit.offset, text);
                self.cursor_byte = edit.offset + edit.len;
            },
            .delete => {
                // Redo delete = delete the text again
                const start = edit.offset;
                const len = edit.len;
                const end = start + len;

                // Assert buffer has the content we're about to delete
                std.debug.assert(start + len <= self.buffer.items.len);

                for (0..len) |_| {
                    _ = self.buffer.orderedRemove(start);
                }
                self.updateLineIndexAfterDelete(start, end);
                self.cursor_byte = start;
            },
            .replace => {
                // Redo replace = delete the deleted text, insert the inserted text
                const deleted_len = edit.len;
                const inserted_text = edit.getInsertedText();

                // Assert buffer has the content we're about to delete
                std.debug.assert(edit.offset + deleted_len <= self.buffer.items.len);

                // First, remove the deleted text (which was restored by undo)
                for (0..deleted_len) |_| {
                    _ = self.buffer.orderedRemove(edit.offset);
                }
                self.updateLineIndexAfterDelete(edit.offset, edit.offset + deleted_len);

                // Then, reinsert the inserted text
                self.buffer.insertSlice(self.allocator, edit.offset, inserted_text) catch {
                    // Partial failure: we deleted but couldn't reinsert
                    // Restore history state - user can retry
                    h.undoRedo();
                    return;
                };
                self.updateLineIndexAfterInsert(edit.offset, inserted_text);
                self.cursor_byte = edit.offset + @as(usize, edit.len2);
            },
        }

        self.selection_anchor = null;
        self.updateCursorPosition();
        self.preferred_column = null;
        self.ensureCursorVisible();
        self.resetCursorBlink();
        self.notifyChange();
    }

    /// Check if undo is available
    pub fn canUndo(self: *const Self) bool {
        const h = self.edit_history orelse return false;
        return h.canUndo();
    }

    /// Check if redo is available
    pub fn canRedo(self: *const Self) bool {
        const h = self.edit_history orelse return false;
        return h.canRedo();
    }

    /// Clear edit history (e.g., after loading new content)
    pub fn clearHistory(self: *Self) void {
        if (self.edit_history) |h| h.clear();
    }

    // =========================================================================
    // Visual State
    // =========================================================================

    fn resetCursorBlink(self: *Self) void {
        self.cursor_visible = true;
        self.last_blink_time = getTimestamp();
    }

    pub fn updateBlink(self: *Self) void {
        if (!self.focused) return;

        const now = getTimestamp();
        if (now - self.last_blink_time >= BLINK_INTERVAL_MS) {
            self.cursor_visible = !self.cursor_visible;
            self.last_blink_time = now;
        }
    }

    /// Milliseconds until the caret's next blink toggle, or `null` while
    /// unfocused, when the caret does not blink.
    ///
    /// The caret changes with the clock alone, so on an on-demand backend no
    /// event would draw its next phase. The frame driver passes this to
    /// `Window.requestRenderAfter` after each render, which wakes the window
    /// about twice a second instead of every vsync.
    pub fn blinkDelayMs(self: *const Self) ?u32 {
        if (!self.focused) return null;

        const elapsed_ms = getTimestamp() - self.last_blink_time;
        std.debug.assert(BLINK_INTERVAL_MS > 0);
        if (elapsed_ms < BLINK_INTERVAL_MS) {
            const delay_ms: u32 = @intCast(BLINK_INTERVAL_MS - @max(elapsed_ms, 0));
            std.debug.assert(delay_ms <= BLINK_INTERVAL_MS);
            return delay_ms;
        } else {
            return 0; // Overdue: the next frame toggles it.
        }
    }

    fn notifyChange(self: *Self) void {
        self.revision +%= 1;
        if (self.on_change) |callback| {
            callback(self);
        }
    }

    // =========================================================================
    // Rendering
    // =========================================================================

    pub fn render(self: *Self, scene: *Scene, text_system: *TextSystem, scale_factor: f32) !void {
        defer self.scroll_stepped = false;
        self.updateBlink();

        const text = self.buffer.items;
        const preedit = self.preedit_buffer.items;

        // Get font metrics
        const metrics = text_system.getMetrics() orelse return;
        self.line_height = metrics.line_height;
        self.viewport_height = self.bounds.height;

        try self.updateWrap(text_system);

        // Move one frame toward the wheel target before anything reads the
        // offset (visible range, clipping, cursor), unless the editor already has.
        self.stepScroll();

        // Process pending click if any (needs text_system for measurement)
        if (self.pending_click) |click| {
            // Note: Error is intentionally ignored here - click positioning failure is recoverable
            // (user can click again). We can't use std.log on WASM (freestanding) targets.
            self.processPendingClick(click.x, click.y, text_system) catch {};
            self.pending_click = null;
        }

        // Calculate visible line range
        const first_visible_f = @floor(self.scroll_offset_y / self.line_height);
        const first_visible: usize = if (first_visible_f < 0) 0 else @intFromFloat(first_visible_f);

        const visible_count_f = @ceil(self.viewport_height / self.line_height) + 1;
        const visible_count: usize = @intFromFloat(visible_count_f);
        const last_visible = @min(first_visible + visible_count, self.lineCount());
        try self.updateScrollX(text_system, first_visible, last_visible);

        // Push clip for text content area
        try scene.pushClip(.{
            .x = self.bounds.x,
            .y = self.bounds.y,
            .width = self.bounds.width,
            .height = self.bounds.height,
        });
        defer scene.popClip();

        const has_content = text.len > 0 or preedit.len > 0;

        if (!has_content and self.placeholder.len > 0) {
            // Render placeholder (first line only)
            const baseline_y = metrics.calcBaseline(self.bounds.y, self.line_height);
            var opts = text_mod.RenderTextOptions{};
            _ = try text_mod.renderText(
                scene,
                text_system,
                self.placeholder,
                self.bounds.x,
                baseline_y,
                scale_factor,
                self.style.placeholder_color,
                metrics.point_size,
                &opts,
            );
        } else if (has_content) {
            // Render marks and the selection behind the text
            try self.renderMarks(scene, text_system, first_visible, last_visible);
            if (self.hasSelection()) {
                try self.renderRange(scene, text_system, self.selectionStart(), self.selectionEnd(), self.style.selection_color, true);
            }

            // Render visible lines
            for (first_visible..last_visible) |row| {
                try self.renderLine(scene, text_system, row, scale_factor);
            }
        }

        // Place the cursor even while blinked off, so its glide keeps time;
        // one that wasn't shown appears without gliding.
        if (self.focused and preedit.len == 0) {
            try self.renderCursor(scene, text_system, scale_factor);
        } else {
            self.glide_target = null;
            self.cursor_gliding = false;
        }

        // Render scrollbar
        try self.renderScrollbar(scene);
    }

    fn renderLine(
        self: *Self,
        scene: *Scene,
        text_system: *TextSystem,
        row: usize,
        scale_factor: f32,
    ) !void {
        const metrics = text_system.getMetrics() orelse return;
        const line_y = self.bounds.y + @as(f32, @floatFromInt(row)) * self.line_height - self.scroll_offset_y;
        const baseline_y = metrics.calcBaseline(line_y, self.line_height);

        const line_content = self.lineContent(row);

        // Handle preedit if cursor is on this line
        if (row == self.cursor_row and self.preedit_buffer.items.len > 0) {
            const preedit = self.preedit_buffer.items;
            const line_start = self.lineStartOffset(row);
            const cursor_in_line = self.cursor_byte - line_start;

            var pen_x = self.bounds.x - self.scroll_offset_x;

            // Text before cursor
            if (cursor_in_line > 0) {
                const before = line_content[0..cursor_in_line];
                var opts = text_mod.RenderTextOptions{};
                const width = try text_mod.renderText(
                    scene,
                    text_system,
                    before,
                    pen_x,
                    baseline_y,
                    scale_factor,
                    self.style.text_color,
                    metrics.point_size,
                    &opts,
                );
                pen_x += width;
            }

            // Preedit with underline
            const preedit_start_x = pen_x;
            var preedit_opts = text_mod.RenderTextOptions{};
            const preedit_width = try text_mod.renderText(
                scene,
                text_system,
                preedit,
                pen_x,
                baseline_y,
                scale_factor,
                self.style.text_color,
                metrics.point_size,
                &preedit_opts,
            );

            // Draw underline
            const underline_y = baseline_y + 2;
            const underline = Quad.filled(
                preedit_start_x,
                underline_y,
                preedit_width,
                1,
                self.style.preedit_underline_color,
            );
            try scene.insertQuad(underline);
            pen_x += preedit_width;

            // Text after cursor
            if (cursor_in_line < line_content.len) {
                const after = line_content[cursor_in_line..];
                var after_opts = text_mod.RenderTextOptions{};
                _ = try text_mod.renderText(
                    scene,
                    text_system,
                    after,
                    pen_x,
                    baseline_y,
                    scale_factor,
                    self.style.text_color,
                    metrics.point_size,
                    &after_opts,
                );
            }
        } else {
            // Normal line rendering, split into colored runs
            const line_start = self.lineStartOffset(row);
            var pen_x = self.bounds.x - self.scroll_offset_x;
            var pos: usize = 0;
            var span_i = self.firstSpanEndingAfter(line_start);
            while (pos < line_content.len) {
                var end = line_content.len;
                var color = self.style.text_color;
                if (span_i < self.color_spans.len) {
                    const span = self.color_spans[span_i];
                    const span_start = @max(span.start, line_start + pos) - line_start;
                    if (span_start > pos) {
                        end = @min(end, span_start);
                    } else {
                        end = @min(end, span.end - line_start);
                        color = span.color;
                        span_i += 1;
                    }
                }
                if (end == pos) continue;
                var opts = text_mod.RenderTextOptions{};
                pen_x += try text_mod.renderText(
                    scene,
                    text_system,
                    line_content[pos..end],
                    pen_x,
                    baseline_y,
                    scale_factor,
                    color,
                    metrics.point_size,
                    &opts,
                );
                pos = end;
            }
        }
    }

    /// Index of the first color span that ends after `offset`.
    fn firstSpanEndingAfter(self: *const Self, offset: usize) usize {
        var lo: usize = 0;
        var hi = self.color_spans.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (self.color_spans[mid].end <= offset) lo = mid + 1 else hi = mid;
        }
        return lo;
    }

    fn renderCursor(
        self: *Self,
        scene: *Scene,
        text_system: *TextSystem,
        scale_factor: f32,
    ) !void {
        _ = scale_factor;
        const metrics = text_system.getMetrics() orelse return;

        // Calculate cursor x position
        var text_x: f32 = 0;
        if (self.cursor_col > 0) {
            const line_content = self.lineContent(self.cursor_row);
            if (self.cursor_col <= line_content.len) {
                text_x = try self.measureText(text_system, line_content[0..self.cursor_col]);
            }
        }
        const at = self.glideCursor(.{ text_x, @as(f32, @floatFromInt(self.cursor_row)) * self.line_height });
        const cursor_x = self.bounds.x - self.scroll_offset_x + at[0];
        const line_y = self.bounds.y + at[1] - self.scroll_offset_y;

        const cursor_height = metrics.line_height;
        const cursor_y = line_y + (self.line_height - cursor_height) / 2;

        var width: f32 = 1.5;
        var color = self.style.cursor_color;
        if (self.cursor_block) {
            const line_content = self.lineContent(self.cursor_row);
            const end = if (self.cursor_col < line_content.len) common.nextCharBoundary(line_content, self.cursor_col) else self.cursor_col;
            width = try self.measureText(text_system, if (end > self.cursor_col) line_content[self.cursor_col..end] else " ");
            color.a *= 0.35;
        }
        const cursor = Quad.filled(cursor_x, cursor_y, width, cursor_height, color);
        if (self.cursor_visible) try scene.insertQuadClipped(cursor);

        // Store cursor rect for IME positioning
        self.cursor_rect = .{ .x = cursor_x, .y = cursor_y, .width = width, .height = cursor_height };
    }

    const glide_us: i64 = 80_000;

    /// Where to draw a cursor headed for `target`: eased out from where it
    /// was drawn when the target last changed.
    fn glideCursor(self: *Self, target: [2]f32) [2]f32 {
        if (!self.cursor_glide) {
            self.glide_target = null;
            self.cursor_gliding = false;
            return target;
        }
        const now = if (self.frame_time_us != 0) self.frame_time_us else getTimestampUs();
        if (self.glide_target) |from| {
            if (from[0] != target[0] or from[1] != target[1]) {
                const shown = self.glideAt(from, now);
                self.glide_offset = .{ shown[0] - target[0], shown[1] - target[1] };
                self.glide_start_us = now;
            }
        } else self.glide_offset = .{ 0, 0 };
        self.glide_target = target;
        const at = self.glideAt(target, now);
        self.cursor_gliding = at[0] != target[0] or at[1] != target[1];
        return at;
    }

    fn glideAt(self: *const Self, target: [2]f32, now: i64) [2]f32 {
        const t = std.math.clamp(@as(f32, @floatFromInt(now - self.glide_start_us)) / glide_us, 0, 1);
        const left = (1 - t) * (1 - t) * (1 - t); // ease out
        return .{ target[0] + self.glide_offset[0] * left, target[1] + self.glide_offset[1] * left };
    }

    /// The marks overlapping the visible rows.
    fn renderMarks(self: *Self, scene: *Scene, text_system: *TextSystem, first_row: usize, last_row: usize) !void {
        if (self.marks.len == 0 or last_row <= first_row) return;
        const from = self.lineStartOffset(first_row);
        const to = self.lineEndOffset(last_row - 1);
        // Marks are sorted and don't overlap, so their ends are sorted too.
        var lo: usize = 0;
        var hi = self.marks.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.marks[mid].end <= from) lo = mid + 1 else hi = mid;
        }
        for (self.marks[lo..]) |m| {
            if (m.start > to) break;
            try self.renderRange(scene, text_system, @max(m.start, from), @min(m.end, to), self.mark_color, false);
        }
    }

    /// Fills `[sel_start, sel_end)` behind the text, a rect per row; `newline`
    /// extends rows the range continues past.
    fn renderRange(
        self: *Self,
        scene: *Scene,
        text_system: *TextSystem,
        sel_start: usize,
        sel_end: usize,
        color: Hsla,
        newline: bool,
    ) !void {
        if (sel_end <= sel_start) return;

        const start_row = self.lineForOffset(sel_start);
        const end_row = self.lineForOffset(sel_end);

        // Render selection highlight for each line
        for (start_row..end_row + 1) |row| {
            const line_start = self.lineStartOffset(row);
            const line_end = self.lineEndOffset(row);

            // Calculate selection range within this line
            const sel_line_start = if (row == start_row) sel_start - line_start else 0;
            const sel_line_end = if (row == end_row) sel_end - line_start else line_end - line_start;

            // Skip if no actual selection content on this line
            if (sel_line_start >= sel_line_end) continue;

            const line_content = self.lineContent(row);
            const line_y = self.bounds.y + @as(f32, @floatFromInt(row)) * self.line_height - self.scroll_offset_y;

            // Calculate x positions
            var start_x = self.bounds.x - self.scroll_offset_x;
            if (sel_line_start > 0 and sel_line_start <= line_content.len) {
                start_x += try self.measureText(text_system, line_content[0..sel_line_start]);
            }

            var end_x = self.bounds.x - self.scroll_offset_x;
            if (sel_line_end > 0 and sel_line_end <= line_content.len) {
                end_x += try self.measureText(text_system, line_content[0..sel_line_end]);
            } else if (sel_line_end > line_content.len) {
                end_x += try self.measureText(text_system, line_content);
            }

            // Show newline extension for non-end rows (full line selected) or when selection extends past content
            if (newline and (row != end_row or sel_line_end > line_content.len)) {
                end_x += 4; // Small extension to show selection includes newline
            }

            const selection_quad = Quad.filled(
                start_x,
                line_y,
                @max(2, end_x - start_x), // Min width of 2 for visibility
                self.line_height,
                color,
            );
            try scene.insertQuadClipped(selection_quad);
        }
    }

    /// Measure text width without rendering.
    /// Delegates to TextSystem.measureText which has a zero-alloc fast path
    /// on shape cache hits (~25 ns vs ~5200 ns through shapeText+deinit).
    fn measureText(self: *Self, text_system: *TextSystem, text: []const u8) !f32 {
        _ = self;
        if (text.len == 0) return 0;
        return text_system.measureText(text);
    }

    /// Process a pending click to position cursor at the clicked location
    fn processPendingClick(self: *Self, click_x: f32, click_y: f32, text_system: *TextSystem) !void {
        std.debug.assert(std.math.isFinite(click_x) and std.math.isFinite(click_y));
        std.debug.assert(text_system.getMetrics() != null);

        if (self.line_height <= 0) return;

        // Calculate which row was clicked
        const relative_y = click_y - self.bounds.y + self.scroll_offset_y;
        const row_f = @floor(relative_y / self.line_height);
        const row: usize = if (row_f < 0) 0 else @intFromFloat(row_f);
        const clamped_row = @min(row, if (self.lineCount() > 0) self.lineCount() - 1 else 0);

        // Calculate which column was clicked using text measurement
        const line_content = self.lineContent(clamped_row);
        const line_start_x = self.bounds.x - self.scroll_offset_x;
        const click_offset_x = click_x - line_start_x;

        // Binary search for the closest character position
        var best_col: usize = 0;
        var best_distance: f32 = click_offset_x; // Distance if cursor at position 0

        // Check each character position to find the closest one
        var col: usize = 0;
        while (col <= line_content.len) : (col += 1) {
            // Only codepoint boundaries: a slice ending mid-character would break shaping.
            if (col < line_content.len and line_content[col] & 0xC0 == 0x80) continue;
            const text_width = if (col > 0) try self.measureText(text_system, line_content[0..col]) else 0;
            const distance = @abs(click_offset_x - text_width);

            if (distance < best_distance) {
                best_distance = distance;
                best_col = col;
            }

            // Early exit if we've passed the click point
            if (text_width > click_offset_x and col > 0) break;
        }

        // Set cursor position
        const line_start = self.lineStartOffset(clamped_row);
        self.cursor_byte = line_start + best_col;
        self.cursor_row = clamped_row;
        self.cursor_col = best_col;
        self.preferred_column = null;
        self.resetCursorBlink();

        // Assert cursor is within valid bounds
        std.debug.assert(self.cursor_byte <= self.buffer.items.len);
    }

    fn ensureCursorVisible(self: *Self) void {
        // Ensure cursor row is visible vertically
        const cursor_y = @as(f32, @floatFromInt(self.cursor_row)) * self.line_height;

        // Only scroll if cursor is completely outside visible area
        // If cursor is above visible area, scroll up
        if (cursor_y < self.scroll_offset_y) {
            self.scroll_offset_y = cursor_y;
        }

        // If cursor is below visible area, scroll down
        const cursor_bottom = cursor_y + self.line_height;
        if (cursor_bottom > self.scroll_offset_y + self.viewport_height) {
            self.scroll_offset_y = cursor_bottom - self.viewport_height;
        }

        // Clamp scroll
        self.scroll_offset_y = std.math.clamp(self.scroll_offset_y, 0, self.maxScrollY());
        self.reveal_cursor_x = true;
    }

    /// Rewraps when soft wrap, the width or the font changed the columns that
    /// fit. Columns come from the width of "0", so wrapping assumes a monospace font.
    pub fn updateWrap(self: *Self, text_system: *TextSystem) !void {
        var cols: usize = 0;
        if (self.soft_wrap) {
            const char_width = try self.measureText(text_system, "0");
            // Always leave the scrollbar's lane, so wrapping can't toggle it and rewrap.
            const bar = &self.scrollbar_style;
            const lane = if (bar.show_vertical) bar.scrollbar_size + bar.scrollbar_padding * 2 else scroll_margin_x;
            if (char_width > 0) cols = @max(1, @as(usize, @intFromFloat(@max(0, self.bounds.width - lane) / char_width)));
        }
        if (cols == self.wrap_cols) return;
        self.wrap_cols = cols;
        self.rebuildLineIndex();
        self.updateCursorPosition();
        self.preferred_column = null;
    }

    /// Measures the visible lines' width, then keeps the cursor (after it
    /// moved) and the scroll offset within the content horizontally.
    fn updateScrollX(self: *Self, text_system: *TextSystem, first: usize, last: usize) !void {
        var widest: f32 = 0;
        for (first..last) |row| widest = @max(widest, try self.measureText(text_system, self.lineContent(row)));
        self.content_width = widest;
        if (self.reveal_cursor_x) {
            self.reveal_cursor_x = false;
            const line = self.lineContent(self.cursor_row);
            const x = try self.measureText(text_system, line[0..@min(self.cursor_col, line.len)]);
            if (x < self.scroll_offset_x) self.scroll_offset_x = x;
            if (x + scroll_margin_x > self.scroll_offset_x + self.bounds.width) self.scroll_offset_x = x + scroll_margin_x - self.bounds.width;
        }
        self.scroll_offset_x = std.math.clamp(self.scroll_offset_x, 0, self.maxScrollX());
    }

    // =========================================================================
    // Scrollbar
    // =========================================================================

    /// Check if content can scroll (content taller than viewport)
    pub fn canScrollY(self: *const Self) bool {
        const content_height = @as(f32, @floatFromInt(self.lineCount())) * self.line_height;
        return content_height > self.viewport_height;
    }

    /// Get scroll percentage (0.0 - 1.0)
    fn scrollPercentY(self: *const Self) f32 {
        const max = self.maxScrollY();
        if (max <= 0) return 0;
        return self.scroll_offset_y / max;
    }

    /// Get the thumb height based on content/viewport ratio
    fn getThumbHeight(self: *const Self) f32 {
        const content_height = @as(f32, @floatFromInt(self.lineCount())) * self.line_height;
        if (content_height <= 0) return self.scrollbar_style.min_thumb_size;

        const track_height = self.bounds.height - self.scrollbar_style.scrollbar_padding * 2;
        const ratio = self.viewport_height / content_height;
        return @max(self.scrollbar_style.min_thumb_size, track_height * ratio);
    }

    /// Render vertical scrollbar
    fn renderScrollbar(self: *Self, scene: *Scene) !void {
        if (!self.scrollbar_style.show_vertical or !self.canScrollY()) return;

        const track_x = self.bounds.x + self.bounds.width - self.scrollbar_style.scrollbar_size - self.scrollbar_style.scrollbar_padding;
        const track_y = self.bounds.y + self.scrollbar_style.scrollbar_padding;
        const track_height = self.bounds.height - self.scrollbar_style.scrollbar_padding * 2;

        // Track background
        try scene.insertQuad(Quad{
            .bounds_origin_x = track_x,
            .bounds_origin_y = track_y,
            .bounds_size_width = self.scrollbar_style.scrollbar_size,
            .bounds_size_height = track_height,
            .background = self.scrollbar_style.track_color,
            .corner_radii = .{
                .top_left = self.scrollbar_style.thumb_radius,
                .top_right = self.scrollbar_style.thumb_radius,
                .bottom_left = self.scrollbar_style.thumb_radius,
                .bottom_right = self.scrollbar_style.thumb_radius,
            },
        });

        // Thumb
        const thumb_height = self.getThumbHeight();
        const scroll_range = track_height - thumb_height;
        const thumb_y = track_y + (scroll_range * self.scrollPercentY());

        try scene.insertQuad(Quad{
            .bounds_origin_x = track_x,
            .bounds_origin_y = thumb_y,
            .bounds_size_width = self.scrollbar_style.scrollbar_size,
            .bounds_size_height = thumb_height,
            .background = self.scrollbar_style.thumb_color,
            .corner_radii = .{
                .top_left = self.scrollbar_style.thumb_radius,
                .top_right = self.scrollbar_style.thumb_radius,
                .bottom_left = self.scrollbar_style.thumb_radius,
                .bottom_right = self.scrollbar_style.thumb_radius,
            },
        });
    }
};

/// Monotonic millisecond timestamp for edit-history entries and the cursor
/// blink timer. Native targets use the process-lifetime `Io`; browsers use
/// their JavaScript monotonic clock because `Io.Threaded` cannot be analyzed
/// for `wasm32-freestanding`. Both clocks provide stable edit ordering and
/// keep blink deltas independent of wall-clock adjustments.
fn getTimestamp() i64 {
    const timestamp_ms = if (comptime builtin.os.tag == .freestanding and builtin.cpu.arch == .wasm32)
        @as(i64, @intFromFloat(@import("../platform/web/imports.zig").getFrameTime()))
    else blk: {
        const io = std.Io.Threaded.global_single_threaded.io();
        break :blk std.Io.Timestamp.now(io, .awake).toMilliseconds();
    };
    std.debug.assert(timestamp_ms >= 0);
    std.debug.assert(timestamp_ms <= std.math.maxInt(i64));
    return timestamp_ms;
}

fn getTimestampUs() i64 {
    const timestamp_us = if (comptime builtin.os.tag == .freestanding and builtin.cpu.arch == .wasm32)
        @as(i64, @intFromFloat(@import("../platform/web/imports.zig").getFrameTime() * 1000.0))
    else blk: {
        const io = std.Io.Threaded.global_single_threaded.io();
        break :blk std.Io.Timestamp.now(io, .awake).toMicroseconds();
    };
    std.debug.assert(timestamp_us >= 0);
    return timestamp_us;
}

// =============================================================================
// Tests
// =============================================================================

test "TextAreaState basic operations" {
    const allocator = std.testing.allocator;
    var ta = TextAreaState.init(allocator, .{ .x = 0, .y = 0, .width = 300, .height = 200 });
    defer ta.deinit();

    try ta.setText("Hello\nWorld");
    try std.testing.expectEqualStrings("Hello\nWorld", ta.getText());
    try std.testing.expectEqual(@as(usize, 2), ta.lineCount());
}

test "TextAreaState line index" {
    const allocator = std.testing.allocator;
    var ta = TextAreaState.init(allocator, .{ .x = 0, .y = 0, .width = 300, .height = 200 });
    defer ta.deinit();

    try ta.setText("Line 1\nLine 2\nLine 3");

    try std.testing.expectEqual(@as(usize, 3), ta.lineCount());
    try std.testing.expectEqual(@as(usize, 0), ta.lineStartOffset(0));
    try std.testing.expectEqual(@as(usize, 7), ta.lineStartOffset(1));
    try std.testing.expectEqual(@as(usize, 14), ta.lineStartOffset(2));

    try std.testing.expectEqual(@as(usize, 0), ta.lineForOffset(0));
    try std.testing.expectEqual(@as(usize, 0), ta.lineForOffset(5));
    try std.testing.expectEqual(@as(usize, 1), ta.lineForOffset(7));
    try std.testing.expectEqual(@as(usize, 2), ta.lineForOffset(14));
}

test "TextAreaState soft wrap rows" {
    const allocator = std.testing.allocator;
    var ta = TextAreaState.init(allocator, .{ .x = 0, .y = 0, .width = 300, .height = 200 });
    defer ta.deinit();

    ta.wrap_cols = 6;
    try ta.setText("hello world\nabcdefghij");

    // Breaks after a space, mid-word without one; the newline still starts a line.
    try std.testing.expectEqual(@as(usize, 4), ta.lineCount());
    try std.testing.expectEqualStrings("hello ", ta.lineContent(0));
    try std.testing.expectEqualStrings("world", ta.lineContent(1));
    try std.testing.expectEqualStrings("abcdef", ta.lineContent(2));
    try std.testing.expectEqualStrings("ghij", ta.lineContent(3));
    try std.testing.expect(!ta.isLineStart(1));
    try std.testing.expect(ta.isLineStart(2));
    try std.testing.expectEqual(@as(usize, 1), ta.textLine(3));
}

test "TextAreaState line content" {
    const allocator = std.testing.allocator;
    var ta = TextAreaState.init(allocator, .{ .x = 0, .y = 0, .width = 300, .height = 200 });
    defer ta.deinit();

    try ta.setText("First\nSecond\nThird");

    try std.testing.expectEqualStrings("First", ta.lineContent(0));
    try std.testing.expectEqualStrings("Second", ta.lineContent(1));
    try std.testing.expectEqualStrings("Third", ta.lineContent(2));
}

test "TextAreaState cursor navigation" {
    const allocator = std.testing.allocator;
    var ta = TextAreaState.init(allocator, .{ .x = 0, .y = 0, .width = 300, .height = 200 });
    defer ta.deinit();

    try ta.setText("AB\nCD\nEF");

    // Start at beginning
    ta.cursor_byte = 0;
    ta.updateCursorPosition();
    try std.testing.expectEqual(@as(usize, 0), ta.cursor_row);
    try std.testing.expectEqual(@as(usize, 0), ta.cursor_col);

    // Move down
    ta.moveDown();
    try std.testing.expectEqual(@as(usize, 1), ta.cursor_row);

    // Move down again
    ta.moveDown();
    try std.testing.expectEqual(@as(usize, 2), ta.cursor_row);

    // Move up
    ta.moveUp();
    try std.testing.expectEqual(@as(usize, 1), ta.cursor_row);
}

test "TextAreaState controlled binding resets and preserves active editing state" {
    // External content replaces committed text, rebuilds line metadata, and
    // preserves cursor/selection offsets only as far as the new value allows.
    const allocator = std.testing.allocator;
    var ta = TextAreaState.init(allocator, .{ .x = 0, .y = 0, .width = 300, .height = 200 });
    defer ta.deinit();

    try ta.setText("one\ntwo");
    ta.cursor_byte = 5;
    ta.selection_anchor = 2;
    try std.testing.expectEqual(TextAreaState.BindingSync.applied, try ta.syncBoundText("alpha\nbeta"));
    try std.testing.expectEqual(@as(usize, 5), ta.cursor_byte);
    try std.testing.expectEqual(@as(?usize, 2), ta.selection_anchor);
    try std.testing.expectEqual(@as(usize, 2), ta.lineCount());

    try std.testing.expectEqual(TextAreaState.BindingSync.applied, try ta.syncBoundText(""));
    try std.testing.expectEqualStrings("", ta.getText());
    try std.testing.expectEqual(@as(usize, 0), ta.cursor_byte);
    try std.testing.expectEqual(@as(?usize, null), ta.selection_anchor);

    try ta.insertText("x");
    try std.testing.expect(!ta.hasSelection());
}

test "TextAreaState controlled binding defers replacement during IME preedit" {
    // The next render may carry a new model value, but composition owns the
    // visible edit until the platform commits or cancels it.
    const allocator = std.testing.allocator;
    var ta = TextAreaState.init(allocator, .{ .x = 0, .y = 0, .width = 300, .height = 200 });
    defer ta.deinit();

    try ta.setText("before");
    try ta.setComposition("候補");
    try std.testing.expectEqual(TextAreaState.BindingSync.deferred_ime, try ta.syncBoundText("external"));
    try std.testing.expectEqualStrings("before", ta.getText());

    try ta.setComposition("");
    try std.testing.expectEqual(TextAreaState.BindingSync.applied, try ta.syncBoundText("external"));
    try std.testing.expectEqualStrings("external", ta.getText());
}

test "TextAreaState wheel scrolling eases to its target" {
    const allocator = std.testing.allocator;
    var ta = TextAreaState.init(allocator, .{ .x = 0, .y = 0, .width = 300, .height = 100 });
    defer ta.deinit();

    try ta.setText("Line 1\nLine 2\nLine 3");
    ta.line_height = 100;
    ta.viewport_height = 100;

    ta.scrollBySmooth(0, -50, 0, false);
    try std.testing.expect(ta.isScrollAnimating());
    try std.testing.expectEqual(@as(f32, 0), ta.scroll_offset_y);

    ta.updateSmoothScroll();
    const first: f32 = ta.scroll_offset_y;
    try std.testing.expect(first > 0 and first < 50);

    var steps: usize = 0;
    while (ta.isScrollAnimating() and steps < 500) : (steps += 1) ta.updateSmoothScroll();
    try std.testing.expect(!ta.isScrollAnimating());
    try std.testing.expectApproxEqAbs(@as(f32, 50), ta.scroll_offset_y, 0.001);

    // A programmatic scroll cancels the easing and becomes the new target.
    ta.scrollBySmooth(0, -20, 0, false);
    try std.testing.expect(ta.isScrollAnimating());
    ta.scrollBy(0, 0);
    try std.testing.expect(!ta.isScrollAnimating());
    ta.updateSmoothScroll();
    try std.testing.expectApproxEqAbs(@as(f32, 50), ta.scroll_offset_y, 0.001);

    // A direct move (e.g. the caret being revealed) adopts the new offset
    // instead of being pulled back toward a stale wheel target.
    ta.scrollBySmooth(0, -20, 0, false);
    ta.scroll_offset_y += 5;
    ta.updateSmoothScroll();
    try std.testing.expect(!ta.isScrollAnimating());
    try std.testing.expectApproxEqAbs(@as(f32, 55), ta.scroll_offset_y, 0.001);
    ta.updateSmoothScroll();
    try std.testing.expectApproxEqAbs(@as(f32, 55), ta.scroll_offset_y, 0.001);
}

test "TextAreaState continuous scrolling is resampled behind the input" {
    const allocator = std.testing.allocator;
    var ta = TextAreaState.init(allocator, .{ .x = 0, .y = 0, .width = 300, .height = 100 });
    defer ta.deinit();

    try ta.setText("1\n2\n3\n4\n5\n6\n7\n8\n9\n10");
    ta.line_height = 100;
    ta.viewport_height = 100;

    // Trackpad events 8ms apart; a wheel's would become continuous at the second.
    ta.scrollBySmooth(0, -8, 1_000_000, true);
    try std.testing.expect(ta.scroll_resampling);
    ta.scrollBySmooth(0, -8, 1_008_000, true);
    ta.scrollBySmooth(0, -8, 1_016_000, true);

    // A frame reads the input as it was a lead and the longest recent event
    // gap before it is shown, averaged over the gap before that; at 1pt/ms
    // that is half a gap behind the plain read (20, between the last two).
    const delay = ta.scrollResampleDelayUs();
    try std.testing.expect(delay > 10_000 and delay < 20_000);
    ta.frame_time_us = 1_012_000 + delay;
    ta.updateSmoothScroll();
    const half_gap: f32 = @floatFromInt(@divTrunc(ta.scroll_gap_us, 2));
    try std.testing.expectApproxEqAbs(20 - half_gap / 1000, ta.scroll_offset_y, 0.01);
    try std.testing.expect(ta.isScrollAnimating());

    // Past the last event the offset holds on it while a late event could
    // still continue the stream; a later event (a VM's jittery 45ms gap)
    // stays in the stream instead of restarting it.
    ta.frame_time_us = 1_030_000 + delay;
    ta.updateSmoothScroll();
    try std.testing.expectApproxEqAbs(@as(f32, 24), ta.scroll_offset_y, 0.001);
    try std.testing.expect(ta.isScrollAnimating());
    ta.scrollBySmooth(0, -8, 1_061_000, false);
    try std.testing.expect(ta.scroll_resampling);
    try std.testing.expectEqual(@as(usize, 5), ta.scroll_sample_count);

    // Once the stream has gone quiet, scrolling stops on the last event.
    ta.frame_time_us = 1_061_000 + TextAreaState.scroll_stream_gap_us + ta.scrollResampleDelayUs();
    ta.updateSmoothScroll();
    try std.testing.expectApproxEqAbs(@as(f32, 32), ta.scroll_offset_y, 0.001);
    try std.testing.expect(!ta.isScrollAnimating());
}

test "TextAreaState resampling delay follows long gaps gradually" {
    const allocator = std.testing.allocator;
    var ta = TextAreaState.init(allocator, .{ .x = 0, .y = 0, .width = 300, .height = 100 });
    defer ta.deinit();

    try ta.setText("1\n2\n3\n4\n5\n6\n7\n8\n9\n10");
    ta.line_height = 100;
    ta.viewport_height = 100;

    ta.scrollBySmooth(0, -8, 1_000_000, true);
    ta.scrollBySmooth(0, -8, 1_010_000, true);
    ta.frame_time_us = 1_016_000;
    ta.updateSmoothScroll();
    const before = ta.scroll_delay_us;

    // A late event (30ms) raises the target at once, but the applied delay
    // grows by at most a quarter of each 16ms frame: no stalled frame.
    ta.scrollBySmooth(0, -8, 1_040_000, true);
    try std.testing.expect(ta.scrollResampleDelayUs() >= before + 9_000);
    ta.frame_time_us = 1_032_000;
    ta.updateSmoothScroll();
    try std.testing.expectEqual(before + 4_000, ta.scroll_delay_us);

    // The recent longest gap decays slowly, so regular events keep the margin.
    const gap = ta.scroll_gap_us;
    ta.scrollBySmooth(0, -8, 1_050_000, true);
    try std.testing.expect(ta.scroll_gap_us < gap and ta.scroll_gap_us > gap - 1_000);
}

test "TextAreaState wrapped rows know their text line" {
    const allocator = std.testing.allocator;
    var ta = TextAreaState.init(allocator, .{ .x = 0, .y = 0, .width = 300, .height = 100 });
    defer ta.deinit();

    ta.wrap_cols = 4;
    try ta.setText("abcdefgh\nij\nklmnop");
    try std.testing.expectEqual(@as(usize, 5), ta.lineCount());
    const lines = [_]usize{ 0, 0, 1, 2, 2 };
    for (lines, 0..) |line, row| try std.testing.expectEqual(line, ta.textLine(row));
}

test "TextAreaState caret blink delay wakes only a focused widget" {
    // The frame driver arms a timed redraw from this value, so it must be
    // absent while unfocused, within one interval just after focus, and zero
    // once the toggle is overdue. Elapsed time is simulated by moving
    // `last_blink_time` back rather than by sleeping, keeping this
    // deterministic.
    const bounds: Bounds = .{ .x = 0, .y = 0, .width = 300, .height = 200 };
    var ta = TextAreaState.init(std.testing.allocator, bounds);
    defer ta.deinit();
    try std.testing.expectEqual(@as(?u32, null), ta.blinkDelayMs());

    ta.focus();
    const fresh_ms = ta.blinkDelayMs().?;
    try std.testing.expect(fresh_ms > 0);
    try std.testing.expect(fresh_ms <= 530);

    ta.last_blink_time -= 400;
    try std.testing.expect(ta.blinkDelayMs().? <= 130);

    ta.last_blink_time -= 130; // Exactly one interval: the toggle is due.
    try std.testing.expectEqual(@as(?u32, 0), ta.blinkDelayMs());

    ta.blur();
    try std.testing.expectEqual(@as(?u32, null), ta.blinkDelayMs());
}

test "TextAreaState cursor glides to a new position, then settles" {
    const bounds: Bounds = .{ .x = 0, .y = 0, .width = 300, .height = 200 };
    var ta = TextAreaState.init(std.testing.allocator, bounds);
    defer ta.deinit();
    ta.cursor_glide = true;
    ta.frame_time_us = 1_000_000;
    try std.testing.expectEqual([2]f32{ 0, 0 }, ta.glideCursor(.{ 0, 0 }));
    try std.testing.expect(!ta.cursor_gliding);

    try std.testing.expectEqual([2]f32{ 0, 0 }, ta.glideCursor(.{ 10, 0 }));
    try std.testing.expect(ta.cursor_gliding);

    ta.frame_time_us += 40_000;
    const mid = ta.glideCursor(.{ 10, 0 });
    try std.testing.expect(mid[0] > 5 and mid[0] < 10);

    ta.frame_time_us += 40_000;
    try std.testing.expectEqual([2]f32{ 10, 0 }, ta.glideCursor(.{ 10, 0 }));
    try std.testing.expect(!ta.cursor_gliding);
}
