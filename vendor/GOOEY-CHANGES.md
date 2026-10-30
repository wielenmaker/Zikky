# Changes to vendored gooey

`vendor/gooey` is [gooey](https://github.com/duanebester/gooey) at `3f69825` plus the changes
below; `vendor/gooey.patch` is the full diff. They are grouped as upstream pull requests would
be: each group stands on its own, lists the files it touches, and says why Zikky needed it.
Some files carry changes from more than one group (marked *shared*); split those hunks by hand.

Regenerate the patch (upstream clone in `../references-cache/gooey`):

```sh
t=$(mktemp -d) && rsync -a --exclude .git ../references-cache/gooey/ "$t/" \
  && git -C "$t" init -q && git -C "$t" add -A && git -C "$t" commit -qm upstream \
  && rsync -a --exclude .zig-cache --exclude zig-out vendor/gooey/ "$t/" \
  && git -C "$t" add -A && git -C "$t" diff --cached --diff-filter=AM > vendor/gooey.patch
```

(`--diff-filter=AM`: the vendored copy leaves out upstream's docs, examples and web files.)

## 1. Extra font faces

Lets one window draw with more than its primary face: a code editor in a monospaced font,
bold UI text.

- `TextSystem.font_id_mono` / `font_id_bold`: extra faces selected per text run by `font_id`.
- `loadExtraFontData` loads a face from font bytes (embedded fonts); `loadExtraFont` by name.
  Both clear the glyph cache.
- `ui.TextStyle.weight` semibold and above draws with the bold face.
- Code editors draw with the mono face.
- `ui.TextStyle.mono` draws and measures text with the mono face (a terminal grid).
- Replacing a slot's face also invalidates the shape and measure caches: they key on the slot's
  address, so a different font in the slot reused the old glyph ids.

Files: `src/text/text_system.zig`*, `src/text/backends/coretext/face.zig`*,
`src/text/backends/coretext/bindings.zig`, `src/runtime/render.zig`, `src/ui/builder.zig`,
`src/widgets/code_editor_state.zig`*.

## 2. GPUI-quality glyphs, quads and shadows

Text and boxes looked thinner and blurrier than the same UI in GPUI (Zed).

- Glyphs: GPUI's color-based font-smoothing dilation (smoothing on at level 0, cached per
  level), origin quantization, 16pt base face, rasterized at logical size.
- Runs longer than `MAX_GLYPHS_PER_RUN` (1024) are drawn in chunks; upstream asserts.
- Quad shader: premultiplied border blending, 1-device-pixel antialiasing.
- Shadow shader: GPUI's gaussian shadow; fixes the offset being applied twice.

Files: `src/text/render.zig`, `src/text/cache.zig`, `src/text/text_system.zig`*,
`src/text/backends/coretext/face.zig`*, `src/platform/macos/metal/quad.zig`,
`src/platform/macos/metal/shadow.zig`.

## 3. Canvas gradients keep their draw order

`fillPathLinearGradient` / `fillPathRadialGradient` ignored the canvas's reserved draw order
(`fillPath` honours it), so a gradient painted above later floating boxes.

Files: `src/ui/canvas.zig`, `src/scene/scene.zig`.

## 4. Code editor: highlighting, soft wrap, scrollbar styling

- `highlighter` callback (style and component prop); spans color the text itself
  (`TextAreaState.color_spans`) instead of drawing backgrounds.
- `TextAreaState.revision` bumps on every buffer change, so derived caches know to rebuild.
- `soft_wrap`: the line index holds visual rows (`wrap_cols`); cursor, selection, clicks and
  scroll follow them; the gutter numbers text lines (each row's line is kept in the index,
  `row_lines`) and is drawn after rewrapping and after the frame's scroll step
  (`TextAreaState.stepScroll`), so it, the line highlight and the syntax spans move with the text.
- Scrollbar width and colors reach text areas and editors (upstream dropped them);
  `scrollbar_padding` on editors.
- `TextAreaState.select` places cursor and selection; `cursor_block` draws a block cursor.
- `TextAreaState.marks` / `mark_color`: ranges filled behind the text like the selection (search
  matches), drawn for the visible rows only; the selection shares the same range painter.

Files: `src/widgets/text_area_state.zig`*, `src/widgets/code_editor_state.zig`*,
`components/src/code_editor.zig`, `src/ui/styles.zig`, `src/runtime/frame.zig`*.

## 4b. Text widgets keep their z-order

Text inputs, text areas and code editors were drawn after every layout command, so they showed
through floating boxes above them (a find bar over an editor). Commands come sorted by
z-index; each level's text widgets are now drawn once that level's commands are
(`renderTextWidgets(above, through)` with `layout.getZIndex`).

Files: `src/runtime/frame.zig`*.

## 5. macOS text editing behaviour

- ⌘⌫ / ⌥⌫ delete to line start / previous word; ⌘⌦ / ⌥⌦ forward.
- Word boundaries skip punctuation, like ⌥←/→ in AppKit.
- Click-to-cursor only measures at codepoint boundaries (upstream panics clicking past a
  multi-byte character).
- Focused text widgets take only the ⌘ keys they use (A C V X Z, arrows, deletes), so
  ⌘Q / ⌘H reach the menu bar; upstream swallowed every ⌘ key.

Files: `src/widgets/text_common.zig`, `src/widgets/text_area_state.zig`*,
`src/runtime/input.zig`*.

## 6. Smooth, low-latency scrolling (macOS)

- Wheel deltas reach widgets in points: precise trackpad deltas 1:1, line wheels scaled by
  `wheel_line_points`; text areas no longer multiply by 20.
- Horizontal scrolling in text areas (wheel `delta.x`, cursor reveal, clamped to the widest
  visible line).
- `ScrollEvent.time_us` (from `NSEvent.timestamp`) and `ScrollEvent.precise`.
- `TextAreaState.scrollBySmooth`: line notches ease (45ms); trackpad streams are resampled
  behind the frame's presentation time (the averaged display-link lead + the recent longest
  event gap, which rises fast and decays slowly; the applied delay is slewed, at most +1/4 or
  −1/16 of a frame interval per frame, so a late event never stalls or skips a frame) and
  hold through gaps up to 60ms. Each frame averages the input over the event gap before its
  read time: a trackpad's deltas are smooth but its timestamps jitter ±2ms around its ~16ms
  cadence, so read at one point the speed jumped ~10% at every event (frame step error on a
  real trackpad trace: 21% → 10%; ~8ms more lag). Input to screen: 69ms → ~40ms at 120Hz, ~50ms in a 60Hz VM.
- `TextAreaState.frame_time_us`: steps use the display link's `in_output_time`, not the
  render's wall clock.
- Frames present immediately; `presentDrawable:atTime:` stalled `nextDrawable` for 1s in a VM.
- Three drawables while scrolling, two idle (`setDrawableCount`).
- `scroll_render_until_ms`: present every vsync during a gesture.

Files: `src/platform/macos/input_view.zig`, `src/input/events.zig`, `src/runtime/input.zig`*,
`src/widgets/text_area_state.zig`*, `src/runtime/frame.zig`*,
`src/platform/macos/window.zig`*, `src/platform/macos/metal/renderer.zig`,
`src/platform/macos/metal/render_pass.zig`.

## 7. On-demand rendering (macOS)

Idle windows re-rendered every vsync (~25–55% CPU): `benchmark_mode` off,
`requestRenderAfter` keeps a real deadline, and `setScene` no longer requests a render from
inside a render.

Files: `src/platform/macos/window.zig`*, `src/platform/unified.zig`*.

## 8. Input hooks

- `Window.key_capture`: sees key events before focused widgets (a vim layer), and mouse
  presses, drags, releases and wheels, so an app can claim a region it draws itself.
- `Window.mouse_down`: the press being dispatched, so click handlers can tell a right click.
- Keystroke names `=`/`equal`, `-`/`minus`, `\`/`backslash`, `,`/`comma`, `` ` ``/`grave`.

Files: `src/context/window.zig`*, `src/input/actions.zig`, `src/runtime/input.zig`*.

## 9. macOS windows and menus

- Native menus (`platform/macos/menu.zig`): `setMainMenu` (items send an AppKit action or
  replay their keystroke via `gooeyMenuKey:`), `popUp` context menus, `popUpSelect` (the current
  item checked and opened under the mouse, like a pop-up button).
- `alert.ask` (`platform/macos/alert.zig`): a modal NSAlert with a message and buttons; returns the
  clicked index.
- `trash.move` (`platform/macos/trash.zig`): moves a file or folder to the Trash.
- Appearance (`platform/macos/appearance.zig`): `set` NSApp's appearance (light, dark, or the
  system's) and `isDark`, an atomic so render threads can read it; views update it and re-render
  on `viewDidChangeEffectiveAppearance`, so an app following the system switches live.
- `traffic_light_position` window option, re-applied on `windowDidUpdate:`.
- `PlatformWindow.autosaveFrame` (`setFrameAutosaveName:`).
- Quitting runs the window's close callback (`applicationWillTerminate:`).
- Multiple windows: one render lock for all windows (shared text system); shared-resource
  windows initialised in place (the a11y bridge points into the window); teardown owns the
  NSWindow (`releasedWhenClosed` off) and releases its view; views accept the first click.

Files: `src/platform/macos/menu.zig` (new), `src/platform/macos/alert.zig` (new), `src/platform/macos/trash.zig` (new),
`src/platform/macos/appearance.zig` (new),
`src/platform/macos/input_view.zig`*, `src/platform/macos/mod.zig`,
`src/platform/macos/window.zig`*, `src/platform/macos/window_delegate.zig`,
`src/platform/interface.zig`, `src/platform/unified.zig`*, `src/runtime/runner.zig`,
`src/runtime/multi_window_app.zig`, `src/runtime/window_context.zig`.

## 10. Windows on displays with different scales

The text system and the SVG and image atlases are shared by all windows, but their scale was
set once, from the first window (the per-frame sync in `WindowContext.beginFrame` was commented
out). A window on a 2x display then drew 1x glyphs at 2x positions: half-size, spread-out text.

- `WindowContext.beginFrame` sets the window's scale on the text system and both atlases.
  Windows build their frames under the one render lock, so the shared scale can't change mid-frame.
- `setScaleFactor` no longer clears those caches: every key already carries the scale (glyphs)
  or the device size (SVGs, images), so a window moving between displays, or two windows on
  different displays, keep both sets cached.

Files: `src/context/window.zig`*, `src/text/cache.zig`, `src/svg/atlas.zig`,
`src/image/atlas.zig`.

## 11. Glyph atlas room for 2x text

At 2x the glyph atlas ran out of skyline nodes (128) and cleared mid-frame, and a full glyph
cache (4096) silently dropped entries, so glyphs re-rasterized every frame until the atlas
overflowed. Glyphs placed before a clear then pointed at wiped or reused pixels (quick open
drew garbage).

- 1024 skyline nodes, 8192 cached glyphs.
- A full cache clears instead of dropping the entry.
- `GlyphCache.evictions` counts clears; a frame that saw one requests another frame.

Files: `src/text/atlas.zig`, `src/text/cache.zig`*, `src/runtime/frame.zig`*.

## 12. Embedded images by name

`Image` only loaded files, so an app's own logo had to sit on disk next to the binary.

- `image.loader.embedded`: name/bytes pairs (`@embedFile`); an image whose source is one of
  these names decodes the bytes (`loadFromMemory`) instead of reading a file.

Files: `src/image/loader.zig`, `src/runtime/render.zig`*.

## 12. Floating elements take clicks over text widgets

`handleMouseDownEvent` gave a click to any text area or code editor whose bounds held the point
before it looked at the dispatch tree, so a floating card above the editor (a command palette)
never got its clicks, and the editor took the focus.

- The hit test runs first; when the hit node or an ancestor is raised (`z_index > 0`), the text
  area and code editor claims are skipped and the click dispatches to the floating element.

Files: `src/runtime/input.zig`.

## 13. Hit testing respects scroll clips

A list's rows scrolled out of view (the overdraw rows above the viewport) stayed in the dispatch
tree with their layout bounds, so a click on whatever sits over the list's edge (the sidebar's
hide button over the file tree) went to the invisible row.

- `LayoutEngine.getClipBox`: the intersection of a node's scroll-container ancestors' boxes
  (the ones that draw a scissor); a floating element escapes them.
- `DispatchNode.clip` is set with the bounds each frame; `hitTest` also requires the point
  inside it.

Files: `src/layout/engine.zig`, `src/context/dispatch.zig`, `src/runtime/frame.zig`*.

## 14. Caret glide

The caret jumped to each new position; Zikky can ease it there instead, like Zed or VS Code's
smooth caret.

- `TextAreaState.cursor_glide`: the cursor eases out over 80ms from where it was drawn to its
  new position, kept in content coordinates so scrolling doesn't glide it. It is placed even
  while blinked off, and one that wasn't shown (unfocused, composing) appears without gliding.
- `TextAreaState.cursor_gliding`: the frame driver keeps frames coming until it settles.

Files: `src/widgets/text_area_state.zig`*, `src/runtime/frame.zig`*.

## 15. Quitting can be cancelled

Quitting (⌘Q, the Dock, logout) only told the close callback through the will-terminate
notification, too late to ask about unsaved work.

- The first window's delegate becomes `NSApp`'s delegate, and its `applicationShouldTerminate:`
  runs the close callback: one that returns false cancels the quit. The window clears it on deinit.

Files: `src/platform/macos/window_delegate.zig`, `src/platform/macos/window.zig`.
