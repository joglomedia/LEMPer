#!/usr/bin/env python3

# +-------------------------------------------------------------------------+
# | LEMPer Shared Security Helpers                                          |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+



# Reject control escapes before the native option reader's line-based output.
# The native reader remains authoritative for option syntax and value decoding.
import os
from pathlib import Path
import re
import stat
import sys


def trusted(path):
    current = path.absolute()
    while str(current) != "/":
        info = current.stat()
        if info.st_uid != os.geteuid():
            raise ValueError("untrusted owner")
        if info.st_mode & 0o022:
            if not (str(current) in ("/tmp", "/var/tmp") and info.st_mode & stat.S_ISVTX):
                raise ValueError("untrusted mode")
        current = current.parent


def validate(path, active, visited):
    trusted(path)
    path = path.resolve()
    trusted(path)
    if path in active or len(visited) >= 128:
        raise ValueError("recursive options")
    if path in visited:
        return
    if not path.is_file():
        raise ValueError("not an option file")
    active.add(path)
    visited.add(path)
    text = path.read_text(encoding="utf-8")
    if "\0" in text:
        raise ValueError("binary options")
    selected = False
    for line in text.split("\n"):
        line = (line[:-1] if line.endswith("\r") else line).lstrip()
        if not line or line.startswith(("#", ";")):
            continue
        if re.match(r"^!(include|includedir)\s+", line):
            directive, name = line.split(None, 1)
            name = name.strip()
            include = Path(name)
            if directive == "!includedir":
                trusted(include)
                for child in sorted(include.glob("*.cnf")):
                    validate(child, active, visited)
            else:
                validate(include, active, visited)
            continue
        if line.startswith("["):
            selected = bool(re.match(r"\[mariabackup\]", line))
            continue
        if not selected:
            continue
        value = line.split("=", 1)[-1].strip()
        index = 0
        while index < len(value):
            character = value[index]
            if ord(character) < 32 or ord(character) == 127:
                raise ValueError("control option")
            if character == "\\" and index + 1 < len(value):
                if value[index + 1] in "nrtb0":
                    raise ValueError("control escape")
                index += 2
            else:
                index += 1
    active.remove(path)


if __name__ == "__main__":
    try:
        validate(Path(sys.argv[1]), set(), set())
    except (OSError, ValueError, IndexError, UnicodeError):
        print("Unsafe or unsupported legacy MariaDB options (values redacted).", file=sys.stderr)
        sys.exit(1)
