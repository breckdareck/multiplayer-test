#!/usr/bin/env python3
"""Zero-dependency pixel-art canvas + PNG encoder (stdlib zlib/struct only).

Draw hard-edged, no-AA shapes on a small RGBA grid, add a clean 1px outline
around the silhouette, and save a PNG. Built for 32x32 game-matching icons.
"""
import zlib, struct

class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.buf = [(0, 0, 0, 0)] * (w * h)  # transparent

    def px(self, x, y, c):
        x = int(x); y = int(y)
        if 0 <= x < self.w and 0 <= y < self.h and c is not None:
            if len(c) == 3:
                c = (c[0], c[1], c[2], 255)
            self.buf[y * self.w + x] = c

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.buf[y * self.w + x]
        return (0, 0, 0, 0)

    def hline(self, x0, x1, y, c):
        if x1 < x0:
            x0, x1 = x1, x0
        for x in range(x0, x1 + 1):
            self.px(x, y, c)

    def vline(self, x, y0, y1, c):
        if y1 < y0:
            y0, y1 = y1, y0
        for y in range(y0, y1 + 1):
            self.px(x, y, c)

    def rect(self, x0, y0, x1, y1, c, fill=None):
        if fill is not None:
            for y in range(y0, y1 + 1):
                self.hline(x0, x1, y, fill)
        self.hline(x0, x1, y0, c)
        self.hline(x0, x1, y1, c)
        self.vline(x0, y0, y1, c)
        self.vline(x1, y0, y1, c)

    def line(self, x0, y0, x1, y1, c):
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        dx = abs(x1 - x0); dy = -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1; sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.px(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy; x0 += sx
            if e2 <= dx:
                err += dx; y0 += sy

    def disc(self, cx, cy, r, c):
        for y in range(int(cy - r), int(cy + r) + 1):
            for x in range(int(cx - r), int(cx + r) + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + r * 0.5:
                    self.px(x, y, c)

    def ring(self, cx, cy, r, c):
        # midpoint circle
        x = r; y = 0; err = 1 - r
        while x >= y:
            for sx, sy in [(x, y), (y, x), (-x, y), (-y, x), (x, -y), (y, -x), (-x, -y), (-y, -x)]:
                self.px(cx + sx, cy + sy, c)
            y += 1
            if err < 0:
                err += 2 * y + 1
            else:
                x -= 1; err += 2 * (y - x) + 1

    def poly(self, pts, c):
        # scanline fill, no AA
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            n = len(pts)
            for i in range(n):
                x0, y0 = pts[i]; x1, y1 = pts[(i + 1) % n]
                if (y0 <= y < y1) or (y1 <= y < y0):
                    xs.append(x0 + (y - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                self.hline(int(round(xs[i])), int(round(xs[i + 1])), y, c)

    def ellipse(self, cx, cy, rx, ry, c):
        for y in range(int(cy - ry), int(cy + ry) + 1):
            for x in range(int(cx - rx), int(cx + rx) + 1):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                    self.px(x, y, c)

    def outline(self, c, diagonal=True):
        """Add a 1px outline around the union silhouette into transparent pixels."""
        nbrs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        if diagonal:
            nbrs += [(-1, -1), (1, -1), (-1, 1), (1, 1)]
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.get(x, y)[3] != 0:
                    continue
                for dx, dy in nbrs:
                    if self.get(x + dx, y + dy)[3] != 0:
                        add.append((x, y))
                        break
        for x, y in add:
            self.px(x, y, c)

    def to_png(self, path, scale=1):
        w, h = self.w * scale, self.h * scale
        raw = bytearray()
        for y in range(h):
            raw.append(0)  # filter type 0
            sy = y // scale
            for x in range(w):
                r, g, b, a = self.buf[sy * self.w + (x // scale)]
                raw += bytes((r, g, b, a))
        def chunk(typ, data):
            return (struct.pack(">I", len(data)) + typ + data +
                    struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff))
        png = b"\x89PNG\r\n\x1a\n"
        png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        png += chunk(b"IEND", b"")
        with open(path, "wb") as f:
            f.write(png)


def hexc(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16),
            int(s[6:8], 16) if len(s) >= 8 else 255)
