#!/usr/bin/env python3
import base64
import sys


def main() -> None:
    for line in sys.stdin:
        entry = line.rstrip("\n")
        encoded = base64.b64encode(entry.encode()).decode("ascii")
        print(f"{encoded}:{entry}")


if __name__ == "__main__":
    main()
