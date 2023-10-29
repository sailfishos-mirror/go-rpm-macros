#!/usr/bin/bash -x

# Replace lua imports to our own go_epel.lua

set -euo pipefail

sed -Ei '/require "fedora.s?rpm.go"/s/go"$/go_epel"/' \
    rpm/macros.d/macros.zzz-go-*rpm-macros-epel \
    rpm/lua/*/*.lua
