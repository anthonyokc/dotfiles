"""Draw one ASCII explosion that fills the terminal, then exit.

Usage: python3 fireball.py [seconds]
"""

import math
import os
import random
import sys
import time

# Hottest first: white core, yellow, orange, red, then smoke.
# Each entry is (foreground, background or None, character). The hot entries
# fill the cell background so the core reads as solid fire, not dots.
RAMP = [
    (231, 230, "@"), (230, 229, "#"), (229, 227, "%"), (227, 220, "*"),
    (221, 214, "*"), (214, 208, "+"), (208, 202, "="), (202, 166, "-"),
    (196, 124, ":"), (160, None, ":"), (124, None, "."), (240, None, "."),
    (238, None, "'"),
]


def main():
    duration = float(sys.argv[1]) if len(sys.argv) > 1 else 1.3
    rng = random.Random()
    out = sys.stdout
    out.write("\x1b[?25l\x1b[2J")
    start = time.monotonic()
    while True:
        t = (time.monotonic() - start) / duration
        if t >= 1:
            break
        # Read the size every frame: the app resizes the terminal after it starts.
        try:
            cols, rows = os.get_terminal_size()
        except OSError:
            cols, rows = 40, 12
        cx, cy = (cols - 1) / 2, (rows - 1) / 2
        # Cells are about twice as tall as wide. The ball grows to the largest
        # circle that fits, so the pane's corners stay empty.
        reach = max(min(cx, cy * 2), 1.0)
        radius = max(reach * (1 - (1 - min(t * 2.2, 1)) ** 3), 0.5)
        frame = ["\x1b[H"]
        for y in range(rows):
            line = []
            for x in range(cols):
                d = math.hypot(x - cx, (y - cy) * 2)
                if d > radius * (0.8 + 0.35 * rng.random()):
                    line.append(" ")
                    continue
                heat = max(0.0, 1 - d / radius) ** 0.6 * (1 - t) ** 0.5 + rng.uniform(-0.12, 0.12)
                if heat < 0.12:
                    line.append("\x1b[0m ")
                    continue
                fg, bg, ch = RAMP[int((1 - min(1.0, heat)) * (len(RAMP) - 1))]
                line.append(f"\x1b[0;38;5;{fg}m" + (f"\x1b[48;5;{bg}m" if bg else "") + ch)
            frame.append("".join(line) + "\x1b[0m" + ("\r\n" if y < rows - 1 else ""))
        out.write("".join(frame))
        out.flush()
        time.sleep(0.04)


if __name__ == "__main__":
    main()
