//! Files embedded in the Zikky binary.

/// JetBrains Mono Nerd Font Mono Regular, the default editor font (font: SIL OFL 1.1, fonts/JetBrainsMono-OFL.txt;
/// its icon glyphs' licenses: fonts/JetBrainsMonoNerdFont-README.md).
pub const jetbrains_mono_nerd = @embedFile("fonts/JetBrainsMonoNerdFontMono-Regular.ttf");

/// The app's logo, the rounded square on transparency (built by design/icon.py).
pub const logo = @embedFile("logo.png");
