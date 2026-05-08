#!/usr/bin/env bash
# fetch.sh <url> <dest>
#
# Downloads a module from a remote URL.
#   • *.qsmod or *.zip URL → curl into <dest> (a file path).
#   • https://github.com/owner/repo[.git][/tree/branch] → shallow git clone
#     into <dest> (a directory path), .git stripped.
#   • anything else → curl into <dest>.
#
# Prints the local path on stdout. Exits non-zero on failure.

set -euo pipefail

url="${1:?usage: fetch.sh <url> <dest>}"
dest="${2:?usage: fetch.sh <url> <dest>}"

mkdir -p "$(dirname "$dest")"

is_archive() { case "$1" in *.qsmod|*.zip|*.tar.gz|*.tgz) return 0;; esac; return 1; }

if is_archive "$url"; then
    curl -fsSL --retry 2 "$url" -o "$dest"
elif [[ "$url" =~ ^(https://|git@)github\.com[:/] ]]; then
    repo="$url"
    branch=""
    # https://github.com/foo/bar/tree/main → repo=foo/bar, branch=main
    if [[ "$url" =~ ^https://github\.com/([^/]+/[^/]+)/tree/(.+)$ ]]; then
        repo="https://github.com/${BASH_REMATCH[1]}.git"
        branch="${BASH_REMATCH[2]}"
    fi
    rm -rf "$dest"
    if [ -n "$branch" ]; then
        git clone --depth 1 --branch "$branch" "$repo" "$dest" >/dev/null 2>&1
    else
        git clone --depth 1 "$repo" "$dest" >/dev/null 2>&1
    fi
    rm -rf "$dest/.git"
else
    curl -fsSL --retry 2 "$url" -o "$dest"
fi

printf %s "$dest"
