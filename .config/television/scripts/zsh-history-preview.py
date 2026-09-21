#!/usr/bin/env python3
import base64
import sys


def main() -> None:
    args = sys.argv[1:]
    decode_base64 = bool(args and args[0] == "--base64")
    if decode_base64:
        args = args[1:]
    elif args and args[0] == "--":
        args = args[1:]

    text = " ".join(args) if args else sys.stdin.read()
    if decode_base64:
        text = base64.b64decode(text).decode()

    sys.stdout.write(text.replace("\\n", "\n"))
    if not text.endswith("\\n") and not text.endswith("\n"):
        sys.stdout.write("\n")


if __name__ == "__main__":
    main()
