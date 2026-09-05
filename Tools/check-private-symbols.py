#!/usr/bin/env python3
"""Reject plaintext navigation SPI names in compiled artifacts."""

import argparse
from pathlib import Path
import sys

PRIVATE_NAMES = (
    b"_UINavigationParallaxTransition",
    b"initWithCurrentOperation:",
    b"_setShouldReverseLayoutDirection:",
)

# Mach-O (32/64-bit, either endianness) and universal binary magic values.
MACHO_MAGIC = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path, nargs="+", help="Mach-O file or app bundle to inspect")
    args = parser.parse_args()
    checked = 0
    leaks = []

    for artifact in args.artifact:
        if not artifact.exists():
            parser.error(f"Artifact does not exist: {artifact}")
        candidates = sorted(artifact.rglob("*")) if artifact.is_dir() else [artifact]
        for candidate in candidates:
            if not candidate.is_file():
                continue
            data = candidate.read_bytes()
            if data[:4] not in MACHO_MAGIC:
                continue
            checked += 1
            for name in PRIVATE_NAMES:
                if name in data:
                    leaks.append(f"{candidate}: {name.decode('ascii')}")

    if not checked:
        parser.error("No Mach-O artifacts were inspected")
    if leaks:
        print("\n".join(leaks), file=sys.stderr)
        return 1
    print(f"Checked {checked} Mach-O artifacts: no plaintext navigation SPI names")
    return 0


if __name__ == "__main__":
    sys.exit(main())
