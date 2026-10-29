//! Files embedded in the Slate binary.

/// Paper Mono Regular, the default editor font (SIL OFL 1.1, see fonts/OFL.txt).
pub const paper_mono = @embedFile("fonts/PaperMono-Regular.ttf");

/// JetBrains Mono Nerd Font Mono Regular (font: SIL OFL 1.1, fonts/JetBrainsMono-OFL.txt;
/// its icon glyphs' licenses: fonts/JetBrainsMonoNerdFont-README.md).
pub const jetbrains_mono_nerd = @embedFile("fonts/JetBrainsMonoNerdFontMono-Regular.ttf");

/// The app's logo, the rounded square on transparency (built by design/icon.py).
pub const logo = @embedFile("logo.png");
