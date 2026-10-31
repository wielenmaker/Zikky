# Changelog

Each release's section is also its GitHub release notes, so keep the
`## <version> (<date>)` heading format: `.github/workflows/release.yml` reads it.

## 0.0.2 (2026-10-31)

Requires macOS 15 or later.

### Added

- Settings › Keyboard lists every shortcut, and you can record your own keys.
- The caret glides to each new position, with a Settings switch to turn it off.
- ⌘O opens a file with the open panel.
- Sidebar: New File in the folder menu, drag rows to move them, and rename or
  delete rows (deleting moves to the Trash).
- Saving an Untitled file with no folder open opens the file's folder.

### Changed

- Zikky starts with just the editor when no folder is open, and restoring the
  last session is off by default.
- Quitting or closing a window with unsaved text asks to save first, replacing
  the Unsaved badge.
- The sidebar loads folders on demand, and quick open scans the disk, so large
  folders open quickly.
- Settings panes scroll, and their icons have thinner strokes.
- The tab logo has an even gap to its ring, so the ring no longer looks like it
  cuts into the logo's corners.
- Builds target macOS 15 as the minimum instead of the version of the Mac that
  built them. The app bundle declares it, so older Macs get a clear message.

### Fixed

- Clicks no longer land on content scrolled out of view: hit testing is
  clipped to scroll containers.

### Project

- SECURITY.md, a README screenshot and the copyright holder in LICENSE.
- Source grouped into feature folders.

## 0.0.1-rc1 (2026-10-30)

First release candidate.
