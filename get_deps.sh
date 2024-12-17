#!/bin/bash
set -euo pipefail

podman run --rm \
    -v ~/.cache/fedrq:/fedrq-cache/fedrq:z \
    -ti \
    quay.io/gotmax23/fedrq:ubi9 \
wr -b rhel9 -r @epel -s -F line:name,repoid:@ go-rpm-macros go-rpm-macros-epel \
    | grep 'epel-source' | sponge | cut -d@ -f1
