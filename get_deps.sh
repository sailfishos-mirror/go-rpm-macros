#!/bin/bash
set -euo pipefail

branch="rhel9"

while getopts 'b:' opt; do
    case "${opt}" in
        b)
            branch="${OPTARG}"
            ;;
        *)
            exit 1
            ;;
    esac
done

podman run --rm \
    -v ~/.cache/fedrq:/fedrq-cache/fedrq:z \
    -ti \
    quay.io/gotmax23/fedrq:ubi9 \
wr -X -b "${branch}" -r @epel -s -F line:name,repoid:@ go-rpm-macros go-rpm-macros-epel \
    | grep 'epel-source' | sponge | cut -d@ -f1
