# Draws new sights in the style of the supplied pictograms, on the same
# 196-unit square the traced ones sit in, then traces them with potrace.
import sys, subprocess, math
from PIL import Image, ImageDraw, ImageFilter

K = 8            # pixels per unit
S = 196          # the square every icon sits in
SIGMA = 3.0      # corner rounding, in units
out = sys.argv[1]

class Pic:
    def __init__(self):
        self.im = Image.new('L', (S * K, S * K), 0)
        self.d = ImageDraw.Draw(self.im)
    def p(self, pts, on=True):
        self.d.polygon([(x * K, y * K) for x, y in pts], fill=255 if on else 0)
    def rect(self, x0, y0, x1, y1, on=True):
        self.d.rectangle([x0 * K, y0 * K, x1 * K, y1 * K], fill=255 if on else 0)
    def circle(self, cx, cy, r, on=True):
        self.d.ellipse([(cx - r) * K, (cy - r) * K, (cx + r) * K, (cy + r) * K], fill=255 if on else 0)
    def arch(self, x0, top, x1, bottom, on=True):
        r = (x1 - x0) / 2
        self.circle(x0 + r, top + r, r, on)
        self.rect(x0, top + r, x1, bottom, on)
    def line(self, a, b, w, on=True, caps=False):
        (x0, y0), (x1, y1) = a, b
        dx, dy = x1 - x0, y1 - y0
        n = math.hypot(dx, dy)
        ox, oy = -dy / n * w / 2, dx / n * w / 2
        self.p([(x0 + ox, y0 + oy), (x1 + ox, y1 + oy), (x1 - ox, y1 - oy), (x0 - ox, y0 - oy)], on)
        if caps:
            self.circle(x0, y0, w / 2, on); self.circle(x1, y1, w / 2, on)
    def curve(self, pts, w, steps=80):
        # Cubic bezier through four points, stroked with round caps.
        (a, b, c, d) = pts
        prev = None
        for i in range(steps + 1):
            t = i / steps
            x = (1-t)**3*a[0] + 3*(1-t)**2*t*b[0] + 3*(1-t)*t**2*c[0] + t**3*d[0]
            y = (1-t)**3*a[1] + 3*(1-t)**2*t*b[1] + 3*(1-t)*t**2*c[1] + t**3*d[1]
            self.circle(x, y, w / 2)
    def save(self, name, dx=0, dy=0, fit=True, box=168):
        if fit:
            # Fit the longest side to the box the set's icons fill, centred.
            x0, y0, x1, y1 = self.im.point(lambda v: 255 if v >= 128 else 0).getbbox()
            scale = box * K / max(x1 - x0, y1 - y0)
            art = self.im.crop((x0, y0, x1, y1))
            art = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)
            im = Image.new('L', self.im.size, 0)
            im.paste(art, ((S * K - art.width) // 2, (S * K - art.height) // 2))
        else:
            # Drawn to size already; only nudged.
            im = Image.new('L', self.im.size, 0)
            im.paste(self.im, (round(dx * K), round(dy * K)))
        im = im.filter(ImageFilter.GaussianBlur(SIGMA * K))
        bw = im.point(lambda v: 0 if v >= 128 else 255, '1')   # ink is black for potrace
        bw.save(f'{out}/{name}.pbm')
        for backend in ('pdf', 'svg'):
            subprocess.run(['potrace', f'{out}/{name}.pbm', '-b', backend, '-t', '40', '-a', '0.9', '-O', '0.4', '-o', f'{out}/{name}.{backend}'], check=True)

def bez(a, b, c, d, steps=60):
    return [((1-t)**3*a[0] + 3*(1-t)**2*t*b[0] + 3*(1-t)*t**2*c[0] + t**3*d[0],
             (1-t)**3*a[1] + 3*(1-t)**2*t*b[1] + 3*(1-t)*t**2*c[1] + t**3*d[1]) for t in (i / steps for i in range(steps + 1))]

# A church: spire with its cross over a tower, and the nave beside it.
c = Pic()
c.rect(50, 4, 66, 46)             # cross upright
c.rect(36, 14, 80, 30)            # cross arm
c.p([(22, 88), (58, 30), (94, 88)])  # spire
c.rect(22, 98, 94, 182)           # tower
c.circle(58, 126, 13, on=False)   # clock
c.arch(44, 150, 72, 183, on=False)  # door
c.p([(104, 182), (104, 122), (143, 88), (182, 122), (182, 182)])  # nave
c.arch(134, 132, 152, 164, on=False)  # window
c.save('spire')

# Clouds: a big one low down and a small one above it, so they fill the square.
# A cloud: three puffs on a flat bottom. One thing on its own, so it spans
# the width and stays short rather than being stretched to fill the square.
c = Pic()
c.circle(48, 120, 34); c.circle(146, 116, 38); c.circle(96, 86, 52)
c.rect(48, 100, 146, 154)
c.save('cloud', dx=-1, dy=4, fit=False)

# A gull, the way a far-off bird looks: two thick wings off a round body.
c = Pic()
left = bez((10, 112), (28, 50), (80, 40), (98, 82)) + bez((98, 130), (80, 86), (48, 90), (28, 128))
c.p(left); c.circle(18, 120, 11)
c.p([(196 - x, y) for x, y in left]); c.circle(178, 120, 11)
c.circle(98, 104, 21)
c.save('bird', dy=-8, fit=False)

# A tower crane: lattice mast, the jib across its top, cab, counterweight and hook.
c = Pic()
c.rect(12, 34, 184, 56)                  # jib
c.rect(48, 56, 90, 182)                  # mast
c.rect(59, 66, 79, 168, on=False)        # its lattice, cut out
for i, y in enumerate(range(66, 168, 34)):
    a, b = ((59, y), (79, y + 34)) if i % 2 == 0 else ((79, y), (59, y + 34))
    c.line(a, b, 11)
c.rect(34, 168, 104, 182)                # foot
c.rect(90, 56, 112, 80)                  # cab
c.rect(14, 56, 46, 92)                   # counterweight
c.rect(144, 56, 158, 112)                # cable
c.rect(132, 106, 170, 134)               # hook block
c.save('crane', dy=4, fit=False)

# Rooftops: a house with its chimney stack.
c = Pic()
c.p([(12, 108), (98, 38), (184, 108)])   # roof
c.rect(124, 32, 152, 80)                 # stack
c.rect(118, 20, 158, 36)                 # its cap
c.rect(28, 118, 168, 182)                # house
c.arch(83, 142, 113, 183, on=False)      # door
c.save('chimney')
