#!/usr/bin/bash

# Tag an epel9 release

set -euo pipefail

usage() {
    echo "USAGE: tag.sh -h (help) -r [remote (default: origin)] -s (do not push) TAG"
}

GIT="${GIT-git}"
remote="origin"
push="true"

while getopts "r:sh" OPT; do
    case "${OPT}" in
        r)
            remote="${OPTARG}"
            ;;
        s)
            push=""
            ;;
        h)
            usage
            exit 1
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

shift "$((OPTIND-1))"
if [ "$#" -ne "1" ]; then
    usage
    exit 1
fi

version="${1}"
tag="epel9-${version}"
branch="release/epel9/${tag}"


"${GIT}" tag -a -s -m "go-rpm-macros-epel ${tag}" "${tag}"
if [ "${push}" = "true" ]; then
    "${GIT}" push --force-with-lease "${remote}" "epel9"
    "${GIT}" switch -c "${branch}"
    "${GIT}" push -u "${remote}" "${branch}"
    "${GIT}" push "${remote}" "${tag}"
    "${GIT}" switch -
fi
