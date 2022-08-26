#!/usr/bin/python3 -s

# Parse modules.txt files into rpm .spec file Provides for bundled dependencies.
# Written by Fabio "decathorpe" Valentini <decathorpe@fedoraproject.org> for
# the fedora syncthing package: https://src.fedoraproject.org/rpms/syncthing
# SPDX-License-Identifier: CC0-1.0 OR Unlicense

# Modified by @gotmax23 to be used as a dependency generator
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2022 Maxwell G <gotmax@e.email>

import os
import re
import sys


def process(path: str):
    with open(path, encoding="utf-8") as file:
        contents = file.read()

    lines = contents.split("\n")

    # dependencies = filter lines for "# package version"
    dependencies = list(filter(lambda line: line.startswith("# "), lines))

    # parse vendored dependencies into (import path, version) pairs
    vendored = list()
    # Handle => style replace directives
    replace_regex = re.compile("^.+( v[0-9-\.]+)? => ")
    for dep in dependencies:
        ipath, version = replace_regex.sub("", dep[2:]).split(" ")[:2]

        # check for git snapshots
        if len(version) > 27:
            # return only 7 digits of git commit hash
            version = version[-12:-1][0:7]
        else:
            # strip off leading "v"
            version = version.lstrip("v")

        vendored.append((ipath, version))

    for ipath, version in vendored:
        print(f"bundled(golang({ipath})) = {version}")


def main() -> None:
    files = sys.stdin.read().splitlines()
    for file in files:
        process(file)


if __name__ == "__main__":
    main()
