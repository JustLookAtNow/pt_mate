#!/usr/bin/env python3
"""Capture large and mobile screenshots from this Flutter Linux project."""

from __future__ import annotations

import argparse
import ctypes
import os
import queue
import re
import shutil
import subprocess
import threading
import time
from pathlib import Path


def parse_size(value: str) -> tuple[int, int]:
    match = re.fullmatch(r"(\d+)x(\d+)", value)
    if not match:
        raise argparse.ArgumentTypeError("size must be WIDTHxHEIGHT")
    return int(match.group(1)), int(match.group(2))


def require_command(name: str) -> None:
    if shutil.which(name) is None:
        raise SystemExit(f"required command not found: {name}")


def read_output(proc: subprocess.Popen[str], output: queue.Queue[str]) -> None:
    assert proc.stdout is not None
    for line in proc.stdout:
        output.put(line)


def find_window(pattern: str) -> str | None:
    result = subprocess.run(
        ["xwininfo", "-root", "-tree"],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        return None

    title_re = re.compile(pattern, re.IGNORECASE)
    line_re = re.compile(r"^\s*(0x[0-9a-fA-F]+)\s+.*?\s+(\d+)x(\d+)[+-]")
    best: tuple[int, str] | None = None
    for line in result.stdout.splitlines():
        if not title_re.search(line):
            continue
        match = line_re.search(line)
        if match is None:
            continue
        width = int(match.group(2))
        height = int(match.group(3))
        if width < 100 or height < 100:
            continue
        area = width * height
        if best is None or area > best[0]:
            best = (area, match.group(1))
    return best[1] if best else None


def resize_window(window_id: str, width: int, height: int, x: int, y: int) -> None:
    x11 = ctypes.cdll.LoadLibrary("libX11.so.6")
    x11.XOpenDisplay.restype = ctypes.c_void_p
    display_name = os.environ.get("DISPLAY")
    display = x11.XOpenDisplay(display_name.encode() if display_name else None)
    if not display:
        raise RuntimeError("failed to open X11 display")
    try:
        x11.XMoveResizeWindow(
            ctypes.c_void_p(display),
            ctypes.c_ulong(int(window_id, 16)),
            ctypes.c_int(x),
            ctypes.c_int(y),
            ctypes.c_uint(width),
            ctypes.c_uint(height),
        )
        x11.XFlush(ctypes.c_void_p(display))
    finally:
        x11.XCloseDisplay(ctypes.c_void_p(display))


def capture_window(window_id: str, path: Path, attempts: int = 6) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    last_error = ""
    for attempt in range(1, attempts + 1):
        result = subprocess.run(
            ["import", "-window", window_id, str(path)],
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode == 0 and path.exists() and path.stat().st_size > 0:
            return
        last_error = result.stderr.strip() or f"empty screenshot: {path}"
        time.sleep(0.6 * attempt)
    raise RuntimeError(last_error)


def stop_flutter(proc: subprocess.Popen[str]) -> None:
    if proc.poll() is not None:
        return
    try:
        if proc.stdin:
            proc.stdin.write("q")
            proc.stdin.flush()
        proc.wait(timeout=10)
    except Exception:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", default="lib/main.dart")
    parser.add_argument("--output-dir", default="/tmp/pt_mate_screenshots")
    parser.add_argument("--device-id", default="linux")
    parser.add_argument("--large-size", default="1280x720", type=parse_size)
    parser.add_argument("--mobile-size", default="393x852", type=parse_size)
    parser.add_argument(
        "--window-pattern",
        default=r"pt_mate|com\.github\.justlookatnow\.ptmate",
    )
    parser.add_argument("--startup-timeout", default=120.0, type=float)
    parser.add_argument("--settle-seconds", default=1.2, type=float)
    args = parser.parse_args()

    for command in ("flutter", "xwininfo", "import"):
        require_command(command)

    root = Path.cwd()
    target = Path(args.target)
    if not target.is_absolute():
        target = root / target
    if not target.exists():
        raise SystemExit(f"target entrypoint does not exist: {target}")

    output_dir = Path(args.output_dir)
    large_path = output_dir / "large.png"
    mobile_path = output_dir / "mobile.png"

    flutter_cmd = ["flutter", "run", "-d", args.device_id, "-t", str(target)]
    print("Starting:", " ".join(flutter_cmd))
    proc = subprocess.Popen(
        flutter_cmd,
        cwd=root,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    output: queue.Queue[str] = queue.Queue()
    threading.Thread(target=read_output, args=(proc, output), daemon=True).start()
    logs: list[str] = []

    try:
        deadline = time.time() + args.startup_timeout
        window_id = None
        while time.time() < deadline:
            while not output.empty():
                line = output.get_nowait()
                logs.append(line.rstrip())
                print(line, end="")
            if proc.poll() is not None:
                raise RuntimeError(
                    "flutter run exited before window appeared:\n"
                    + "\n".join(logs[-80:])
                )
            window_id = find_window(args.window_pattern)
            if window_id:
                break
            time.sleep(0.5)
        if not window_id:
            raise RuntimeError(
                "timed out waiting for app window:\n" + "\n".join(logs[-80:])
            )

        print(f"Using window: {window_id}")
        resize_window(window_id, *args.large_size, 80, 80)
        time.sleep(args.settle_seconds)
        capture_window(window_id, large_path)

        resize_window(window_id, *args.mobile_size, 100, 80)
        time.sleep(args.settle_seconds)
        capture_window(window_id, mobile_path)

        print("\nCreated screenshots:")
        print(f"large={large_path}")
        print(f"mobile={mobile_path}")
        return 0
    finally:
        stop_flutter(proc)


if __name__ == "__main__":
    raise SystemExit(main())
