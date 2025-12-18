#!/usr/bin/env python3
"""Visual sleep cycle helper."""

from __future__ import annotations

import ctypes
import os
import platform
from datetime import datetime, timedelta
import tkinter as tk
from tkinter import font as tkfont

BACKGROUND = "#0d1b2a"
PANEL_BG = "#1b263b"
ACCENT = "#415a77"
TEXT_PRIMARY = "#e0fbfc"
TEXT_SECONDARY = "#cbd5e1"


def enable_platform_dpi_awareness() -> None:
    """Mark the process as DPI-aware when possible."""

    system = platform.system()
    if system == "Windows":
        awareness_context = -4  # DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
        try:
            ctypes.windll.user32.SetProcessDpiAwarenessContext(awareness_context)
            return
        except Exception:
            pass

        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(2)
            return
        except Exception:
            pass

        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass
    elif system == "Darwin":
        os.environ.setdefault("TK_SILENCE_DEPRECATION", "1")


def generate_sleep_windows(extra_cycles: int = 6):
    """Return tuples of (increment_number, wake_time)."""

    now = datetime.now()
    wake_times = []

    next_time = now + timedelta(minutes=14)
    for increment in range(1, extra_cycles + 2):
        wake_times.append((increment, next_time))
        next_time += timedelta(hours=1, minutes=30)

    return now, wake_times


def format_time(target: datetime, reference: datetime) -> str:
    """Format times nicely, adding day info if it rolls over."""

    time_text = target.strftime("%I:%M %p").lstrip("0")
    if target.date() != reference.date():
        time_text = f"{target.strftime('%a')} {time_text}"
    return time_text


def apply_high_dpi_scaling(root: tk.Tk) -> None:
    """Match Tk scaling to the actual display DPI."""

    try:
        pixels_per_inch = root.winfo_fpixels("1i")
        scaling = max(pixels_per_inch / 72.0, 2.5)
        root.tk.call("tk", "scaling", "-displayof", root, scaling)
    except tk.TclError:
        # If the platform does not support this query, skip it.
        pass


def configure_base_fonts() -> None:
    """Ensure Tk's named fonts map to crisp, scalable families."""

    try:
        family = "Segoe UI" if platform.system() == "Windows" else "Helvetica Neue"
        overrides = {
            "TkDefaultFont": 12,
            "TkTextFont": 12,
            "TkMenuFont": 11,
            "TkHeadingFont": 15,
        }
        for name, size in overrides.items():
            tkfont.nametofont(name).configure(family=family, size=size)
    except tk.TclError:
        pass


def center_window(root: tk.Tk) -> None:
    """Center the window on the screen."""
    root.update_idletasks()
    width = root.winfo_width()
    height = root.winfo_height()
    x = (root.winfo_screenwidth() // 2) - (width // 2)
    y = (root.winfo_screenheight() // 2) - (height // 2)
    root.geometry(f"+{x}+{y}")


def build_window():
    now, wake_windows = generate_sleep_windows()

    enable_platform_dpi_awareness()
    root = tk.Tk()
    root.overrideredirect(True)
    apply_high_dpi_scaling(root)
    configure_base_fonts()
    root.title("Sleep Cycle Helper")
    root.configure(bg=BACKGROUND)
    root.resizable(False, False)

    # Close on any key press
    root.bind("<Key>", lambda e: root.destroy())

    header = tk.Label(
        root,
        text="🌛 It takes the average person 14 minutes to fall asleep...",
        bg=BACKGROUND,
        fg=TEXT_PRIMARY,
        font=("Helvetica", 16, "bold"),
        wraplength=520,
        justify="left",
        pady=10,
    )
    header.pack(padx=24, pady=(24, 0), anchor="w")

    subheader = tk.Label(
        root,
        text=(
            "If you lie in bed now, try to wake up at one of the "
            "following times to wake up near the end of your REM cycle:"
        ),
        bg=BACKGROUND,
        fg=TEXT_SECONDARY,
        font=("Helvetica", 12),
        wraplength=520,
        justify="left",
    )
    subheader.pack(padx=24, pady=(0, 10), anchor="w")

    panel = tk.Frame(root, bg=PANEL_BG, highlightbackground=ACCENT, highlightthickness=1)
    panel.pack(padx=24, pady=(0, 24), fill="x")

    for increment, wake_time in wake_windows:
        row = tk.Frame(panel, bg=PANEL_BG)
        row.pack(fill="x", padx=16, pady=8)

        index_label = tk.Label(
            row,
            text=f"{increment}",
            width=4,
            anchor="w",
            bg=BACKGROUND,
            fg=TEXT_PRIMARY,
            font=("Helvetica", 13, "bold"),
            padx=8,
            pady=4,
        )
        index_label.pack(side="left")

        time_label = tk.Label(
            row,
            text=f"{format_time(wake_time, now)}",
            anchor="w",
            bg=PANEL_BG,
            fg=TEXT_PRIMARY,
            font=("Helvetica", 15),
        )
        time_label.pack(side="left", expand=True, fill="x")

    footer = tk.Frame(root, bg=BACKGROUND)
    footer.pack(padx=24, pady=(0, 24), fill="x")

    time_footer = tk.Label(
        footer,
        text=f"Current time: {format_time(now, now)}",
        bg=BACKGROUND,
        fg=TEXT_SECONDARY,
        font=("Helvetica", 11),
    )
    time_footer.pack(side="left")

    close_hint = tk.Label(
        footer,
        text="(Press any key to close)",
        bg=BACKGROUND,
        fg="#64748b",
        font=("Helvetica", 9, "italic"),
    )
    close_hint.pack(side="right")

    center_window(root)
    root.mainloop()


if __name__ == "__main__":
    build_window()
