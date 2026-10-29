"""Builds file-marks.pdf: the Zikky file marks brochure, drawn as vector PDF.

Usage: python3 design/brochure.py [out.pdf] [page-preview-dir]
"""
import os
import sys
import textwrap

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import marks  # noqa: E402

W, H = 792.0, 612.0  # US Letter, landscape
K = 0.5522847498

INK = 0x1F1F23
MUTED = 0x8A8794
SIDEBAR = 0xF4F3F1
CARD = 0xF7F6F4
TAB_BG = 0xEDECEA
RING = 0xD2D2D2
BORDER = 0xE4E2DF

SAMPLE = {
    "Zig": "build.zig", "Rust": "main.rs", "Go": "server.go", "Python": "app.py", "JavaScript": "index.js",
    "TypeScript": "types.ts", "React": "Button.tsx", "Vue": "App.vue", "C": "parser.c", "C++": "engine.cpp",
    "C#": "Program.cs", "Swift": "View.swift", "Java": "Main.java", "Kotlin": "Build.kt", "Ruby": "app.rb",
    "PHP": "index.php", "Lua": "init.lua", "Shell": "install.sh", "HTML": "index.html", "CSS": "style.css",
    "JSON": "package.json", "YAML": "ci.yml", "TOML": "Cargo.toml", "Markdown": "README.md", "SQL": "schema.sql",
    "Docker": "Dockerfile", "Git": ".gitignore",
}

CUE = {
    "Zig": "Z inside open brackets; the slash runs past them.",
    "Rust": "Ten-tooth cog with a knocked-out R.",
    "Go": "Italic GO with three speed lines.",
    "Python": "Two interlocked snakes, each with an eye.",
    "JavaScript": "Yellow tile, JS set bottom-right.",
    "TypeScript": "Blue tile, TS set bottom-right.",
    "React": "Three orbits around a nucleus.",
    "Vue": "Two nested Vs.",
    "C": "Hexagon with an open C.",
    "C++": "Hexagon, C and two plus signs.",
    "C#": "Hexagon, C and a sharp.",
    "Swift": "Swift bird diving across a rounded tile.",
    "Java": "Steaming cup on a saucer.",
    "Kotlin": "Square with a notch cut to its centre.",
    "Ruby": "Cut gem with facet lines.",
    "PHP": "Oval with a cut-out php.",
    "Lua": "Planet, its shadow and a moon.",
    "Shell": "Prompt >_ in a terminal tile.",
    "HTML": "Shield with a 5.",
    "CSS": "Shield with a 3.",
    "JSON": "A pair of curly braces.",
    "YAML": "Y and the colon of key: value.",
    "TOML": "T between square brackets.",
    "Markdown": "M and a down arrow in a frame.",
    "SQL": "A database cylinder of three discs.",
    "Docker": "Whale carrying a stack of containers.",
    "Git": "Branch graph inside a diamond.",
}


def rgb(c):
    return f"{(c >> 16 & 255) / 255:.3f} {(c >> 8 & 255) / 255:.3f} {(c & 255) / 255:.3f}"


def esc(s):
    return s.encode("cp1252").replace(b"\\", b"\\\\").replace(b"(", b"\\(").replace(b")", b"\\)").decode("latin-1")


class Page:
    def __init__(self):
        self.ops = []

    def fill(self, c):
        self.ops.append(f"{rgb(c)} rg")

    def rrect(self, x, y, w, h, r, c, stroke=None):
        y0 = H - y - h
        k = r * K
        self.fill(c)
        p = [f"{x + r:.2f} {y0:.2f} m", f"{x + w - r:.2f} {y0:.2f} l",
             f"{x + w - r + k:.2f} {y0:.2f} {x + w:.2f} {y0 + r - k:.2f} {x + w:.2f} {y0 + r:.2f} c",
             f"{x + w:.2f} {y0 + h - r:.2f} l",
             f"{x + w:.2f} {y0 + h - r + k:.2f} {x + w - r + k:.2f} {y0 + h:.2f} {x + w - r:.2f} {y0 + h:.2f} c",
             f"{x + r:.2f} {y0 + h:.2f} l",
             f"{x + r - k:.2f} {y0 + h:.2f} {x:.2f} {y0 + h - r + k:.2f} {x:.2f} {y0 + h - r:.2f} c",
             f"{x:.2f} {y0 + r:.2f} l", f"{x:.2f} {y0 + r - k:.2f} {x + r - k:.2f} {y0:.2f} {x + r:.2f} {y0:.2f} c"]
        self.ops += p
        if stroke is not None:
            self.ops.append(f"{rgb(stroke)} RG 0.6 w B")
        else:
            self.ops.append("f")

    def mark(self, mark, x, y, size, c):
        s = size / 16
        self.ops.append(f"q {s:.4f} 0 0 {-s:.4f} {x:.2f} {H - y:.2f} cm")
        self.fill(c)
        for ct in marks.contours(mark):
            self.ops.append(f"{ct.start[0]:.3f} {ct.start[1]:.3f} m")
            for sg in ct.segs:
                if sg[0] == 'L':
                    self.ops.append(f"{sg[1][0]:.3f} {sg[1][1]:.3f} l")
                else:
                    self.ops.append(" ".join(f"{p[0]:.3f} {p[1]:.3f}" for p in sg[1:]) + " c")
            self.ops.append("h")
        self.ops.append("f Q")

    def text(self, s, x, y, size, c=INK, bold=False):
        """y is the baseline, measured from the top."""
        self.fill(c)
        self.ops.append(f"BT /{'F2' if bold else 'F1'} {size} Tf 1 0 0 1 {x:.2f} {H - y:.2f} Tm ({esc(s)}) Tj ET")

    def para(self, s, x, y, size, width, c=INK, lead=1.35):
        for line in textwrap.wrap(s, int(width / (size * 0.5))):
            self.text(line, x, y, size, c)
            y += size * lead
        return y

    def tile(self, mark, color, x, y):
        """The tab logo: the mark in white on its color, in Rex's white ring."""
        self.rrect(x, y, 23, 18, 5, 0xFFFFFF, stroke=RING)
        self.rrect(x + 1, y + 1, 21, 16, 4, color)
        self.mark(mark, x + 6.5, y + 3.5, 11, 0xFFFFFF)


def text_w(s, size):
    return len(s) * size * 0.52


def cover(all_marks):
    p = Page()
    p.text("Zikky File Marks", 48, 82, 34, bold=True)
    p.text("A crafted logo set for popular files  ·  draft 1  ·  28 October 2026", 48, 106, 12, MUTED)
    p.rrect(48, 136, 230, 230, 22, CARD)
    zig = all_marks[0]
    p.mark(zig[3](), 73, 161, 180, zig[1])
    p.text("Zig, the reference mark", 48, 388, 10, MUTED)

    x, y = 320, 150
    p.text("How the marks are built", x, y, 15, bold=True)
    y += 28
    rules = [
        ("16-unit grid.", "Every mark is drawn for the 14 pt file tree first and scales up cleanly; "
                          "strokes are about 1.5 units, so they stay over a pixel wide."),
        ("One path, one colour.", "Each mark is a single SVG path filled with the nonzero rule, which is "
                                  "exactly what gooey's renderer draws, so the paths go into Zikky unchanged."),
        ("Knockouts, not outlines.", "Letters and details are cut out of a solid shape. They stay legible "
                                     "when small and turn into white-on-colour for the tab logo."),
        ("Recognisable, not copied.", "Each mark keeps the cue people already know (Rust's cog, Python's "
                                      "two snakes, Lua's moon, Go's speed lines) and redraws it on our grid."),
    ]
    for i, (head, body) in enumerate(rules):
        p.text(f"{i + 1}", x, y, 13, all_marks[0][1], bold=True)
        p.text(head, x + 20, y, 12, bold=True)
        y = p.para(body, x + 20, y + 17, 10.5, 400, 0x4A4952) + 12

    p.rrect(48, 470, W - 96, 86, 14, SIDEBAR)
    p.text(f"The set: {len(all_marks)} marks", 66, 494, 10, MUTED)
    step = (W - 96 - 36) / len(all_marks)
    for i, (name, color, exts, f) in enumerate(all_marks):
        p.mark(f(), 66 + i * step + (step - 18) / 2, 512, 18, color)
    return p


def cards(chunk, index, total):
    p = Page()
    p.text("The set", 40, 52, 20, bold=True)
    p.text(f"{index} / {total}", W - 80, 52, 10, MUTED)
    cols, gap = 5, 12
    cw = (W - 80 - gap * (cols - 1)) / cols
    ch = 158
    for i, (name, color, exts, f) in enumerate(chunk):
        x = 40 + (i % cols) * (cw + gap)
        y = 74 + (i // cols) * (ch + gap)
        m = f()
        p.rrect(x, y, cw, ch, 10, CARD)
        p.mark(m, x + 12, y + 12, 48, color)
        p.text(name, x + 12, y + 79, 12, bold=True)
        p.text(f"#{color:06X}    {exts}", x + 12, y + 92, 8, MUTED)
        p.para(CUE[name], x + 12, y + 107, 8, cw - 20, 0x4A4952, 1.3)
        # Actual size: a tree row (14 pt mark, 13 pt label) and the tab logo.
        p.rrect(x + 6, y + ch - 32, cw - 12, 26, 6, SIDEBAR)
        p.mark(m, x + 12, y + ch - 26, 14, color)
        p.text(SAMPLE[name], x + 32, y + ch - 15, 10, 0x2B2A30)
        p.tile(m, color, x + cw - 36, y + ch - 28)
    if len(chunk) <= cols * 2 + 2:
        notes(p, 40 + 2 * (cw + gap), 74 + 2 * (ch + gap), W - 80 - 2 * (cw + gap), ch)
    return p


def notes(p, x, y, w, h):
    p.rrect(x, y, w, h, 10, 0xFFFFFF, stroke=BORDER)
    p.text("Notes", x + 16, y + 26, 12, bold=True)
    y = p.para("Files without a language keep today's Lucide icons: images, archives, fonts, audio, video "
               "and lockfiles stay grey, so the coloured marks point at the code.", x + 16, y + 46, 9, w - 32,
               0x4A4952)
    y = p.para("Every mark here is generated from design/marks.py; the same path strings go into "
               "src/file_kind.zig once the set is approved, drawn filled in the tree and quick open and in "
               "white on the tile in the tab bar.", x + 16, y + 6, 9, w - 32, 0x4A4952)
    p.para("Ask for changes by name, e.g. \"Ruby: fewer facets\" or \"YAML: try a list instead\".",
           x + 16, y + 6, 9, w - 32, MUTED)


def in_context(all_marks):
    p = Page()
    by = {n: (c, f) for n, c, e, f in all_marks}
    p.text("In context", 40, 52, 20, bold=True)
    p.text("Actual size, in Zikky's light theme: the tree, the tab bar and quick open.", 40, 72, 11, MUTED)

    wx, wy, ww, wh = 40, 92, 500, 470
    p.rrect(wx, wy, ww, wh, 12, SIDEBAR, stroke=BORDER)
    for i, c in enumerate((0xFF5F57, 0xFEBC2E, 0x28C840)):
        p.rrect(wx + 14 + i * 20, wy + 14, 12, 12, 6, c)
    tree = [
        (0, "folder", "zikky"), (1, "Zig", "build.zig"), (1, "Zig", "build.zig.zon"), (1, "Markdown", "README.md"),
        (1, "Git", ".gitignore"), (1, "Docker", "Dockerfile"), (1, "folder", "src"), (2, "Zig", "main.zig"),
        (2, "Zig", "editor.zig"), (1, "folder", "web"), (2, "React", "App.tsx"), (2, "TypeScript", "api.ts"),
        (2, "CSS", "style.css"), (2, "HTML", "index.html"), (2, "JSON", "package.json"), (1, "folder", "tools"),
        (2, "Python", "bench.py"), (2, "Shell", "release.sh"), (2, "Rust", "lexer.rs"), (2, "Go", "serve.go"),
        (2, "YAML", "ci.yml"), (2, "SQL", "schema.sql"),
    ]
    ry = wy + 48
    for depth, kind, label in tree:
        x = wx + 14 + depth * 16
        active = label == "main.zig"
        if active:
            p.rrect(x + 8, ry - 1, wx + 186 - x - 8, 19, 6, 0xFFFFFF, stroke=BORDER)
        if kind == "folder":
            p.mark([('s', marks.poly((4, 6), (12, 6), (8, 11)))], x, ry + 2, 12, MUTED)
            p.rrect(x + 14, ry + 4, 14, 10, 2, 0xB9B6B0)
        else:
            c, f = by[kind]
            p.mark(f(), x + 14, ry + 2, 14, c)
        p.text(label, x + 34, ry + 13, 12, INK if active else 0x2B2A30, bold=active)
        ry += 18.6

    # The editor container with its tab bar.
    cx, cy = wx + 196, wy + 44
    cw = ww - 196 - 8
    tabs = [("Zig", "main.zig", True), ("TypeScript", "api.ts", False), ("Python", "bench.py", False)]
    tx = cx
    for kind, label, shown in tabs:
        c, f = by[kind]
        w = 34 + text_w(label, 11) + 14
        if shown:
            p.rrect(tx, wy + 9, w, 28, 14, TAB_BG)
        p.tile(f(), c, tx + 6, wy + 14)
        p.text(label, tx + 36, wy + 27, 11, INK if shown else MUTED)
        tx += w + 4
    p.rrect(cx, cy, cw, wh - 52, 10, 0xFFFFFF, stroke=BORDER)
    for i, w in enumerate((180, 220, 120, 0, 240, 200, 160, 210, 90, 0, 230, 150, 190, 120, 0, 200, 170, 110)):
        p.text(f"{i + 1}", cx + 12, cy + 22 + i * 18, 9, 0xB9B6B0)
        if w:
            p.rrect(cx + 36, cy + 15 + i * 18, w * (cw - 48) / 240, 7, 3.5, 0xECEAE6)

    # Quick open, as a card of its own.
    qx, qy, qw = 560, 92, 192
    p.rrect(qx, qy, qw, 470, 12, 0xFFFFFF, stroke=BORDER)
    p.rrect(qx + 10, qy + 10, qw - 20, 26, 8, SIDEBAR)
    p.text("Quick open", qx + 20, qy + 27, 11, MUTED)
    files = [("Zig", "src/main.zig"), ("Rust", "tools/lexer.rs"), ("Go", "tools/serve.go"), ("Python", "tools/bench.py"),
             ("JavaScript", "web/index.js"), ("TypeScript", "web/api.ts"), ("React", "web/App.tsx"),
             ("Vue", "web/Nav.vue"), ("C", "vendor/parser.c"), ("C++", "vendor/engine.cpp"), ("C#", "ext/Program.cs"),
             ("Swift", "mac/View.swift"), ("Java", "jvm/Main.java"), ("Kotlin", "jvm/Build.kt"), ("Ruby", "models/user.rb"),
             ("PHP", "site/index.php"), ("Lua", "nvim/init.lua"), ("TOML", "Cargo.toml"), ("Markdown", "docs/guide.md"),
             ("Docker", "Dockerfile"), ("Git", ".gitattributes")]
    fy = qy + 46
    for i, (kind, label) in enumerate(files):
        c, f = by[kind]
        if i == 0:
            p.rrect(qx + 8, fy - 2, qw - 16, 20, 6, 0xEFEDEA)
        p.mark(f(), qx + 16, fy + 1, 14, c)
        p.text(label, qx + 38, fy + 12, 10, 0x2B2A30)
        fy += 20
    return p


def pdf(pages):
    objs = []

    def add(b):
        objs.append(b)
        return len(objs)

    f1 = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
    f2 = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
    pages_id = len(objs) + 1 + 2 * len(pages)
    kids = []
    for pg in pages:
        body = "\n".join(o for o in pg.ops if o).encode("latin-1")
        c = add(b"<< /Length %d >>\nstream\n" % len(body) + body + b"\nendstream")
        kids.append(add((f"<< /Type /Page /Parent {pages_id} 0 R /MediaBox [0 0 {W:.0f} {H:.0f}] "
                         f"/Resources << /Font << /F1 {f1} 0 R /F2 {f2} 0 R >> >> /Contents {c} 0 R >>").encode()))
    add((f"<< /Type /Pages /Kids [{' '.join(f'{k} 0 R' for k in kids)}] /Count {len(kids)} >>").encode())
    cat = add(f"<< /Type /Catalog /Pages {pages_id} 0 R >>".encode())
    info = add(b"<< /Title (Zikky File Marks) /Author (Zikky) >>")
    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offs = []
    for i, o in enumerate(objs):
        offs.append(len(out))
        out += f"{i + 1} 0 obj\n".encode() + o + b"\nendobj\n"
    x = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    out += b"".join(f"{o:010d} 00000 n \n".encode() for o in offs)
    out += f"trailer\n<< /Size {len(objs) + 1} /Root {cat} 0 R /Info {info} 0 R >>\nstartxref\n{x}\n%%EOF\n".encode()
    return bytes(out)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "file-marks.pdf")
    m = marks.MARKS
    pages = [cover(m), cards(m[:15], 1, 2), cards(m[15:], 2, 2), in_context(m)]
    open(out, "wb").write(pdf(pages))
    if len(sys.argv) > 2:
        for i, pg in enumerate(pages):
            open(os.path.join(sys.argv[2], f"page{i + 1}.pdf"), "wb").write(pdf([pg]))


main()
