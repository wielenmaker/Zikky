"""Zikky file marks: geometry for each language's mark on a 16-unit grid.

Every mark is one path, one color, filled with the nonzero rule (what gooey's
SVG renderer draws). Solids wind one way and knockouts the other; knockouts
never overlap each other.
"""
import math

K = 0.5522847498


class Contour:
    def __init__(self, start):
        self.start = start
        self.segs = []  # ('L', p) | ('C', c1, c2, p)

    def L(self, *p):
        self.segs.append(('L', p))
        return self

    def C(self, c1, c2, p):
        self.segs.append(('C', c1, c2, p))
        return self

    def nodes(self):
        out = [self.start]
        for s in self.segs:
            out.append(s[-1])
        return out

    def sample(self):
        pts = [self.start]
        cur = self.start
        for s in self.segs:
            if s[0] == 'L':
                pts.append(s[1])
            else:
                for i in range(1, 9):
                    t = i / 8
                    pts.append(bez(cur, s[1], s[2], s[3], t))
            cur = s[-1]
        return pts

    def area(self):
        p = self.sample()
        return sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p))) / 2

    def reversed(self):
        nodes = self.nodes()
        segs = list(self.segs)
        if nodes[-1] != nodes[0]:
            segs.append(('L', nodes[0]))
            nodes.append(nodes[0])
        r = Contour(nodes[-1])
        for i in range(len(segs) - 1, -1, -1):
            s, prev = segs[i], nodes[i]
            if s[0] == 'L':
                r.L(*prev)
            else:
                r.C(s[2], s[1], prev)
        return r

    def map(self, f):
        r = Contour(f(self.start))
        for s in self.segs:
            if s[0] == 'L':
                r.L(*f(s[1]))
            else:
                r.C(f(s[1]), f(s[2]), f(s[3]))
        return r


def bez(p0, p1, p2, p3, t):
    u = 1 - t
    return (u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
            u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1])


# ---- primitives -----------------------------------------------------------

def poly(*pts):
    c = Contour(pts[0])
    for p in pts[1:]:
        c.L(*p)
    return c


def rect(x0, y0, x1, y1):
    return poly((x0, y0), (x1, y0), (x1, y1), (x0, y1))


def rrect(x0, y0, x1, y1, r):
    k = r * K
    c = Contour((x0 + r, y0))
    c.L(x1 - r, y0).C((x1 - r + k, y0), (x1, y0 + r - k), (x1, y0 + r))
    c.L(x1, y1 - r).C((x1, y1 - r + k), (x1 - r + k, y1), (x1 - r, y1))
    c.L(x0 + r, y1).C((x0 + r - k, y1), (x0, y1 - r + k), (x0, y1 - r))
    c.L(x0, y0 + r).C((x0, y0 + r - k), (x0 + r - k, y0), (x0 + r, y0))
    return c


def arc_pts(cx, cy, rx, ry, a0, a1):
    """Cubic pieces for an elliptical arc from angle a0 to a1 (degrees, y down)."""
    n = max(1, math.ceil(abs(a1 - a0) / 90 - 1e-9))
    step = (a1 - a0) / n
    out = []
    for i in range(n):
        t0 = math.radians(a0 + i * step)
        t1 = math.radians(a0 + (i + 1) * step)
        k = 4 / 3 * math.tan((t1 - t0) / 4)
        p0 = (cx + rx * math.cos(t0), cy + ry * math.sin(t0))
        p3 = (cx + rx * math.cos(t1), cy + ry * math.sin(t1))
        c1 = (p0[0] - k * rx * math.sin(t0), p0[1] + k * ry * math.cos(t0))
        c2 = (p3[0] + k * rx * math.sin(t1), p3[1] - k * ry * math.cos(t1))
        out.append((c1, c2, p3))
    return out


def ellipse(cx, cy, rx, ry):
    c = Contour((cx + rx, cy))
    for c1, c2, p in arc_pts(cx, cy, rx, ry, 0, 360):
        c.C(c1, c2, p)
    return c


def circle(cx, cy, r):
    return ellipse(cx, cy, r, r)


def band(cx, cy, ro, ri, a0, a1):
    """An annular sector (a stroke of a circle) from a0 to a1 degrees."""
    t0 = math.radians(a0)
    c = Contour((cx + ro * math.cos(t0), cy + ro * math.sin(t0)))
    for c1, c2, p in arc_pts(cx, cy, ro, ro, a0, a1):
        c.C(c1, c2, p)
    t1 = math.radians(a1)
    c.L(cx + ri * math.cos(t1), cy + ri * math.sin(t1))
    for c1, c2, p in arc_pts(cx, cy, ri, ri, a1, a0):
        c.C(c1, c2, p)
    return c


def ring(cx, cy, ro, ri):
    """A full ring: returns (solid, hole)."""
    return [('s', circle(cx, cy, ro)), ('h', circle(cx, cy, ri))]


def cubic_line(p0, p1, p2, p3, n=12):
    return [bez(p0, p1, p2, p3, i / n) for i in range(n + 1)]


def stroke(pts, w):
    """Offset a polyline into a polygon (butt caps, miter joins)."""
    h = w / 2
    left, right = [], []
    n = len(pts)
    for i in range(n):
        if i == 0:
            dx, dy = pts[1][0] - pts[0][0], pts[1][1] - pts[0][1]
        elif i == n - 1:
            dx, dy = pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]
        else:
            ax, ay = pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]
            bx, by = pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]
            la, lb = math.hypot(ax, ay), math.hypot(bx, by)
            dx, dy = ax / la + bx / lb, ay / la + by / lb
        l = math.hypot(dx, dy)
        nx, ny = -dy / l, dx / l
        m = h
        if 0 < i < n - 1:
            ax, ay = pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]
            la = math.hypot(ax, ay)
            cosv = (nx * -ay / la + ny * ax / la)
            m = h / max(cosv, 0.5)
        left.append((pts[i][0] + nx * m, pts[i][1] + ny * m))
        right.append((pts[i][0] - nx * m, pts[i][1] - ny * m))
    return poly(*(left + right[::-1]))


def plus(cx, cy, s, a):
    """A plus sign as one outline (s: half size, a: half arm width)."""
    return poly((cx - a, cy - s), (cx + a, cy - s), (cx + a, cy - a), (cx + s, cy - a), (cx + s, cy + a),
                (cx + a, cy + a), (cx + a, cy + s), (cx - a, cy + s), (cx - a, cy + a), (cx - s, cy + a),
                (cx - s, cy - a), (cx - a, cy - a))


def hexagon(cx, cy, r):
    return poly(*[(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
                  for a in (-90, -30, 30, 90, 150, 210)])


def S(*items):
    return [('s', c) for c in items]


def H(*items):
    return [('h', c) for c in items]


# ---- letters (knockout-safe: pieces abut, never overlap) ------------------

def letter_S(x0, y0, x1, y1, t):
    m0 = (y0 + y1) / 2 - t / 2
    return [rect(x0, y0, x1, y0 + t), rect(x0, y0 + t, x0 + t, m0), rect(x0, m0, x1, m0 + t),
            rect(x1 - t, m0 + t, x1, y1 - t), rect(x0, y1 - t, x1, y1)]


def letter_3(x0, y0, x1, y1, t):
    m0 = (y0 + y1) / 2 - t / 2
    return [rect(x0, y0, x1, y0 + t), rect(x1 - t, y0 + t, x1, m0), rect(x0 + t * 0.8, m0, x1, m0 + t),
            rect(x1 - t, m0 + t, x1, y1 - t), rect(x0, y1 - t, x1, y1)]


# ---- the marks ------------------------------------------------------------

def zig():
    return S(poly((1.5, 3), (10.5, 3), (8.7, 5.25), (3.75, 5.25), (3.75, 8), (1.5, 10.8)),
             poly((14.5, 13), (5.5, 13), (7.3, 10.75), (12.25, 10.75), (12.25, 8), (14.5, 5.2)),
             poly((12.1, 1), (15.1, 1), (3.9, 15), (0.9, 15)))


def rust():
    parts = [('s', circle(8, 8, 6.0))]
    for i in range(10):
        a = math.radians(i * 36 - 90)
        def at(r, d):
            return (8 + r * math.cos(a + math.radians(d)), 8 + r * math.sin(a + math.radians(d)))
        parts.append(('s', poly(at(5.5, -10), at(7.6, -6), at(7.6, 6), at(5.5, 10))))
    # R, knocked out
    x = -0.3
    parts += H(rect(5.0 + x, 4.3, 6.6 + x, 11.7), rect(6.6 + x, 4.3, 9.0 + x, 5.9),
               band(9.0 + x, 6.65, 2.35, 0.75, -90, 90), rect(6.6 + x, 7.4, 9.0 + x, 9.0),
               poly((8.1 + x, 9.0), (9.8 + x, 9.0), (11.6 + x, 11.7), (9.9 + x, 11.7)))
    return parts


def go():
    sk = lambda p: (p[0] + 0.24 * (8 - p[1]), p[1])
    parts = [('s', band(6.4, 8, 3.5, 1.9, 0, 318)), ('s', rect(7.0, 7.25, 9.9, 8.75))]
    parts += ring(12.55, 8, 3.25, 1.7)
    parts += S(rect(0.4, 5.6, 2.5, 6.7), rect(0.0, 7.45, 2.5, 8.55), rect(0.4, 9.3, 2.5, 10.4))
    return [(k, c.map(sk)) for k, c in parts]


def python():
    a_head = rrect(4.6, 1.0, 11.4, 5.0, 1.8)
    a_body = rrect(1.0, 4.0, 7.2, 10.0, 1.8)
    parts = S(a_head, a_body)
    parts += H(circle(6.5, 2.85, 0.85))
    rot = lambda p: (16 - p[0], 16 - p[1])
    return parts + [(k, c.map(rot)) for k, c in parts]


def js():
    return S(rrect(1, 1, 15, 15, 2.4)) + H(rect(6.4, 7.2, 7.8, 12.1), rect(4.4, 12.1, 7.8, 13.5),
                                            *letter_S(9.0, 7.2, 13.4, 13.5, 1.4))


def ts():
    return S(rrect(1, 1, 15, 15, 2.4)) + H(rect(3.8, 7.2, 8.4, 8.6), rect(5.4, 8.6, 6.8, 13.5),
                                            *letter_S(9.0, 7.2, 13.4, 13.5, 1.4))


def c_lang():
    return S(hexagon(8, 8, 7.5)) + H(band(8.4, 8, 3.9, 2.0, 42, 318))


def cpp():
    return S(hexagon(8, 8, 7.5)) + H(band(6.1, 8, 3.4, 1.75, 45, 315), plus(10.65, 8, 1.1, 0.42),
                                     plus(13.0, 8, 1.1, 0.42))


def csharp():
    h = [band(6.0, 8, 3.4, 1.75, 45, 315)]
    h += [rect(10.25, 5.6, 10.95, 10.4), rect(12.05, 5.6, 12.75, 10.4)]
    for y in (6.9, 8.4):
        h += [rect(9.3, y, 10.25, y + 0.7), rect(10.95, y, 12.05, y + 0.7), rect(12.75, y, 13.7, y + 0.7)]
    return S(hexagon(8, 8, 7.5)) + H(*h)


def swift():
    bird = Contour((2.2, 4.6))
    bird.C((4.6, 7.4), (7.6, 9.6), (10.0, 10.6))       # lower feather edge, sweeping right
    bird.C((7.4, 7.9), (5.4, 5.6), (4.4, 3.4))          # back up to the second feather tip
    bird.C((6.6, 5.6), (9.4, 7.6), (11.2, 8.4))         # second feather
    bird.C((11.6, 6.0), (10.6, 3.6), (9.2, 2.2))        # up to the tail tip
    bird.C((12.4, 3.8), (14.0, 7.6), (13.4, 10.6))      # back of the bird
    bird.C((14.2, 11.6), (14.2, 12.8), (13.8, 13.4))    # tail flick
    bird.C((12.8, 12.4), (11.6, 12.4), (10.2, 13.0))
    bird.C((7.4, 14.0), (4.0, 13.0), (1.8, 10.8))       # belly
    bird.C((5.0, 12.2), (8.0, 12.0), (9.6, 11.2))
    bird.C((7.0, 9.8), (4.2, 7.4), (2.2, 4.6))
    return S(rrect(0.8, 0.8, 15.2, 15.2, 3.4)) + H(bird)


def java():
    cup = Contour((2.4, 8.0)).L(11.4, 8.0).L(11.4, 10.6)
    cup.C((11.4, 12.7), (9.8, 14.0), (7.6, 14.0)).L(6.2, 14.0)
    cup.C((4.0, 14.0), (2.4, 12.7), (2.4, 10.6))
    parts = S(cup, rrect(1.0, 14.7, 13.8, 15.7, 0.5)) + ring(11.6, 10.0, 2.3, 1.15)
    for x0, ph in ((5.4, 0.0), (8.4, 0.6)):
        pts = [(x0 + 0.9 * math.sin((y - 1.2) / 5.4 * 2 * math.pi + ph), y) for y in [1.2 + i * 0.35 for i in range(17)]]
        parts.append(('s', stroke(pts, 1.25)))
    return parts


def kotlin():
    return S(poly((1.5, 1.5), (14.5, 1.5), (8, 8), (14.5, 14.5), (1.5, 14.5)))


def ruby():
    crown = poly((4.2, 1.8), (11.8, 1.8), (14.9, 5.4), (1.1, 5.4))
    pav = poly((1.1, 6.2), (14.9, 6.2), (8, 14.8))
    holes = [poly((6.6, 2.4), (7.3, 2.4), (5.7, 4.9), (5.0, 4.9)),
             poly((8.7, 2.4), (9.4, 2.4), (11.0, 4.9), (10.3, 4.9)),
             poly((4.9, 6.7), (5.6, 6.7), (7.9, 12.6), (7.6, 12.0)),
             poly((10.4, 6.7), (11.1, 6.7), (8.4, 12.0), (8.1, 12.6))]
    return S(crown, pav) + H(*holes)


def php():
    def p(x):
        return [rect(x, 5.6, x + 1.1, 11.6), rect(x + 1.1, 5.6, x + 2.3, 6.7), rect(x + 2.3, 5.6, x + 3.3, 9.8),
                rect(x + 1.1, 8.7, x + 2.3, 9.8)]
    h = p(2.9) + p(10.4)
    h += [rect(6.95, 4.0, 8.05, 9.8), rect(8.05, 5.6, 8.85, 6.7), rect(8.85, 5.6, 9.95, 9.8)]
    return S(ellipse(8, 8, 7.6, 5.3)) + H(*h)


def lua():
    return S(circle(7, 9, 6), circle(13.5, 2.5, 1.7)) + H(circle(9.6, 6.4, 1.7))


def shield():
    return poly((1.6, 1.0), (14.4, 1.0), (13.2, 13.6), (8, 15.2), (2.8, 13.6))


def html():
    return S(shield()) + H(*letter_S(5.2, 3.6, 10.8, 12.0, 1.6))


def css():
    return S(shield()) + H(*letter_3(5.2, 3.6, 10.8, 12.0, 1.6))


def json_braces():
    def half(sign):
        f = (lambda p: p) if sign > 0 else (lambda p: (p[0], 16 - p[1]))
        pts = cubic_line(f((6.8, 1.6)), f((5.2, 1.6)), f((4.5, 2.2)), f((4.5, 3.6)))
        pts += [f((4.5, 6.0))]
        pts += cubic_line(f((4.5, 6.0)), f((4.5, 7.3)), f((3.7, 8.0)), f((2.2, 8.0)))[1:]
        return stroke(pts, 1.55)
    left = [half(1), half(-1)]
    mirror = lambda p: (16 - p[0], p[1])
    return S(*left, *[c.map(mirror) for c in left])


def yaml():
    y = poly((0.8, 2.0), (3.2, 2.0), (5.4, 5.8), (7.6, 2.0), (10.0, 2.0), (6.6, 7.9), (6.6, 14.0), (4.2, 14.0),
             (4.2, 7.9))
    return S(y, rrect(11.2, 7.0, 13.8, 9.6, 0.5), rrect(11.2, 11.4, 13.8, 14.0, 0.5))


def toml():
    lb = poly((1.4, 1.8), (5.0, 1.8), (5.0, 3.5), (3.2, 3.5), (3.2, 12.5), (5.0, 12.5), (5.0, 14.2), (1.4, 14.2))
    rb = lb.map(lambda p: (16 - p[0], p[1]))
    return S(lb, rb, rect(5.7, 4.5, 10.3, 6.2), rect(7.15, 6.2, 8.85, 11.5))


def markdown():
    m = poly((2.8, 10.6), (2.8, 5.4), (4.5, 5.4), (6.0, 7.3), (7.5, 5.4), (9.2, 5.4), (9.2, 10.6), (7.7, 10.6),
             (7.7, 7.7), (6.0, 9.8), (4.3, 7.7), (4.3, 10.6))
    return S(rrect(0.4, 2.6, 15.6, 13.4, 2.0)) + H(rrect(1.7, 3.9, 14.3, 12.1, 0.9)) + S(
        m, rect(11.0, 5.4, 12.4, 8.2), poly((9.6, 8.2), (13.8, 8.2), (11.7, 10.8)))


def shell():
    return S(rrect(0.8, 1.8, 15.2, 14.2, 2.4)) + H(
        poly((3.6, 5.0), (5.5, 5.0), (8.6, 8.0), (5.5, 11.0), (3.6, 11.0), (6.7, 8.0)),
        rect(9.2, 9.6, 12.8, 11.0))


def docker():
    body = Contour((1.0, 8.2)).L(13.0, 8.2)
    body.C((13.3, 7.2), (14.3, 6.6), (15.4, 6.9))
    body.C((15.2, 7.9), (14.6, 8.6), (13.7, 8.9))
    body.C((12.6, 12.4), (9.6, 14.2), (6.0, 14.2))
    body.C((3.0, 14.2), (1.2, 12.0), (1.0, 8.2))
    boxes = [rect(x, 5.8, x + 1.6, 7.4) for x in (2.4, 4.4, 6.4, 8.4, 10.4)]
    boxes += [rect(x, 3.8, x + 1.6, 5.4) for x in (4.4, 6.4, 8.4)]
    boxes += [rect(8.4, 1.8, 10.0, 3.4)]
    return S(body, *boxes)


def git():
    d = rrect(3.0, 3.0, 13.0, 13.0, 1.4)
    rot = lambda p: (8 + (p[0] - 8 - (p[1] - 8)) * 0.7071 * 1.02, 8 + (p[0] - 8 + p[1] - 8) * 0.7071 * 1.02)
    w, r = 1.15, 1.4
    a, b, c = (6.6, 6.0), (6.6, 11.3), (10.9, 8.9)

    def seg(p, q, r0, r1):
        dx, dy = q[0] - p[0], q[1] - p[1]
        l = math.hypot(dx, dy)
        ux, uy = dx / l, dy / l
        e0 = math.sqrt(max(r0 * r0 - (w / 2) ** 2, 0)) if r0 else 0
        e1 = math.sqrt(r1 * r1 - (w / 2) ** 2)
        s = (p[0] + ux * e0, p[1] + uy * e0)
        t = (q[0] - ux * e1, q[1] - uy * e1)
        nx, ny = -uy * w / 2, ux * w / 2
        return poly((s[0] + nx, s[1] + ny), (t[0] + nx, t[1] + ny), (t[0] - nx, t[1] - ny), (s[0] - nx, s[1] - ny))

    holes = [circle(*a, r), circle(*b, r), circle(*c, r), seg(a, b, r, r), seg(a, c, r, r),
             seg((6.6, 3.0), a, 0, r)]
    return S(d.map(rot)) + H(*holes)


def react():
    parts = []
    for ang in (0, 60, 120):
        t = math.radians(ang)
        rot = lambda p, t=t: (8 + (p[0] - 8) * math.cos(t) - (p[1] - 8) * math.sin(t),
                              8 + (p[0] - 8) * math.sin(t) + (p[1] - 8) * math.cos(t))
        parts += [('s', ellipse(8, 8, 7.4, 2.9).map(rot)), ('h', ellipse(8, 8, 6.45, 1.95).map(rot))]
    return parts + S(circle(8, 8, 1.45))


def vue():
    return S(poly((0.4, 2.0), (3.6, 2.0), (8, 9.6), (12.4, 2.0), (15.6, 2.0), (8, 15.0)),
             poly((4.6, 2.0), (6.7, 2.0), (8, 4.3), (9.3, 2.0), (11.4, 2.0), (8, 7.9)))


def sql():
    def seg(a, b):
        c = Contour((1.8, a))
        for c1, c2, p in arc_pts(8, a, 6.2, 2.2, 180, 0):
            c.C(c1, c2, p)
        c.L(14.2, b)
        for c1, c2, p in arc_pts(8, b, 6.2, 2.2, 0, 180):
            c.C(c1, c2, p)
        return c
    # top-edge arcs run 180 -> 0 through 90 (the lower half): concave from inside the band
    return S(ellipse(8, 3.4, 6.2, 2.2), seg(4.3, 8.0), seg(8.9, 12.6))


# name, color, extensions, factory
MARKS = [
    ("Zig", 0xF0A020, ".zig .zon", zig),
    ("Rust", 0xC6512B, ".rs  Cargo.toml", rust),
    ("Go", 0x00A5CF, ".go  go.mod", go),
    ("Python", 0x3776AB, ".py .pyi", python),
    ("JavaScript", 0xE9C319, ".js .mjs .cjs", js),
    ("TypeScript", 0x3178C6, ".ts .mts .d.ts", ts),
    ("React", 0x149ECA, ".jsx .tsx", react),
    ("Vue", 0x41B883, ".vue", vue),
    ("C", 0x5C6BC0, ".c .h", c_lang),
    ("C++", 0x00599C, ".cpp .cc .hpp", cpp),
    ("C#", 0x9B4F96, ".cs", csharp),
    ("Swift", 0xF05138, ".swift", swift),
    ("Java", 0xE76F00, ".java .jar", java),
    ("Kotlin", 0x7F52FF, ".kt .kts", kotlin),
    ("Ruby", 0xCC342D, ".rb  Gemfile", ruby),
    ("PHP", 0x777BB4, ".php", php),
    ("Lua", 0x2C2D72, ".lua", lua),
    ("Shell", 0x3E9F55, ".sh .bash .zsh", shell),
    ("HTML", 0xE34F26, ".html .htm", html),
    ("CSS", 0x1572B6, ".css .scss", css),
    ("JSON", 0xB8901A, ".json .jsonc", json_braces),
    ("YAML", 0xCB171E, ".yaml .yml", yaml),
    ("TOML", 0x9C4121, ".toml", toml),
    ("Markdown", 0x4A5A78, ".md .mdx", markdown),
    ("SQL", 0xD9822B, ".sql .sqlite", sql),
    ("Docker", 0x2496ED, "Dockerfile", docker),
    ("Git", 0xF05032, ".gitignore", git),
]


def contours(mark):
    """Contours oriented for nonzero: solids positive, knockouts negative."""
    out = []
    for kind, c in mark:
        a = c.area()
        if (kind == 's') != (a > 0):
            c = c.reversed()
        out.append(c)
    return out


def fmt(v):
    s = f"{v:.2f}".rstrip('0').rstrip('.')
    return "0" if s in ("-0", "") else s


def svg_d(mark):
    out = []
    for c in contours(mark):
        out.append(f"M{fmt(c.start[0])} {fmt(c.start[1])}")
        for s in c.segs:
            if s[0] == 'L':
                out.append(f"L{fmt(s[1][0])} {fmt(s[1][1])}")
            else:
                out.append("C" + " ".join(f"{fmt(p[0])} {fmt(p[1])}" for p in s[1:]))
        out.append("Z")
    return "".join(out)


IDENT = {"C++": "cpp", "C#": "csharp"}


def zig_source():
    out = ["//! File marks: each language's logo, one filled path on a 16-unit grid",
           "//! (nonzero rule). Generated by `python3 design/marks.py src/file_marks.zig`",
           "//! from design/marks.py; edit the geometry there, not here.", "",
           "pub const Mark = struct {", "    path: []const u8,", "    color: u32,", "};", ""]
    for name, color, _, f in MARKS:
        ident = IDENT.get(name, name.lower())
        out.append(f'pub const {ident} = Mark{{ .color = 0x{color:06x}, .path = "{svg_d(f())}" }};')
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    import sys
    open(sys.argv[1], "w").write(zig_source())
