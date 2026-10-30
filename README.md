# Zikky

A small native code editor for macOS, written in Zig on [gooey](https://github.com/duanebester/gooey).

- File tree, tabs, soft wrap, find, quick open (⌘P), command palette (⇧⌘P)
- Syntax highlighting for ~25 language families
- Built-in terminal (⌘J, powered by Ghostty's terminal core)
- Optional vim mode, light/dark/system appearance, settings (⌘,)

## Build

Requires macOS and Zig 0.17.

```sh
zig build
zig-out/bin/zikky [folder]
zig build test
```

To make `dist/Zikky.app`: `scripts/bundle.sh`. Releases are built from `v*` tags and the app is not
notarized, so on first launch right-click it and choose Open (or `xattr -cr Zikky.app`).

## Contributing

Issues and pull requests are welcome.

- Branch from `main`, one feature per branch.
- Keep changes small: one small component per file, no extra abstractions.
- Run `zig build test` before opening a PR.
- Changes to `vendor/gooey` must be recorded in `vendor/GOOEY-CHANGES.md`.

## License

[MIT](LICENSE). Third-party notices are in [NOTICE](NOTICE).
