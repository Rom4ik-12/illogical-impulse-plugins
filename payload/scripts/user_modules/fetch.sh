#!/usr/bin/env bash
# fetch.sh <url> <dest> [<loader-version>]
#
# Downloads a module from a remote URL.
#   • *.qsmod / *.zip / *.tar.gz URL → curl into <dest> (a file path).
#   • https://github.com/owner/repo[.git][/tree/branch] → shallow git clone
#     into <dest> (a directory path), .git stripped.
#   • anything else → curl into <dest>.
#
# When <loader-version> is supplied AND the URL points to a github repo
# (or a `releases/latest/download/<asset>` direct asset), we ask the GitHub
# API for the list of releases and pick the highest-version release whose
# tagged module.json declares a compatible `requiresLoader`. If none match,
# we still install the latest and emit `NOT_TESTED` to stderr — the loader
# picks that up and shows a warning under the module.
#
# Prints the local install path on stdout. Exits non-zero on failure.

set -euo pipefail

url="${1:?usage: fetch.sh <url> <dest> [loader-version]}"
dest="${2:?usage: fetch.sh <url> <dest> [loader-version]}"
loader_version="${3:-}"

mkdir -p "$(dirname "$dest")"

is_archive() { case "$1" in *.qsmod|*.zip|*.tar.gz|*.tgz) return 0;; esac; return 1; }

# When a github URL + loader_version is given, ask Python to pick the best
# release. Python prints up to two lines on stdout:
#   <chosen-tag>\t<asset-url-or-empty>
#   NOT_TESTED   (only if no compatible release was found)
pick_compatible() {
    local owner_repo="$1" loader="$2" asset_hint="$3"
    python3 - "$owner_repo" "$loader" "$asset_hint" <<'PYEOF'
import sys, json, urllib.request, re

owner_repo, loader, asset_hint = sys.argv[1], sys.argv[2], sys.argv[3]

def matches(req, ver):
    if not req or req == "*": return True
    rp = req.lstrip("v").split(".")
    vp = ver.lstrip("v").split(".")
    for i, a in enumerate(rp):
        if a in ("*", "x"): continue
        b = vp[i] if i < len(vp) else ""
        if a != b: return False
    return True

def fetch_json(url, timeout=6):
    req = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "qsmod-fetch",
    })
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)

try:
    releases = fetch_json(f"https://api.github.com/repos/{owner_repo}/releases?per_page=20")
except Exception as e:
    sys.stderr.write(f"fetch: cannot list releases: {e}\n")
    sys.exit(2)

releases = [r for r in releases if not r.get("draft") and not r.get("prerelease")]
if not releases:
    sys.exit(3)

chosen, not_tested = None, False
for r in releases:
    tag = r["tag_name"]
    raw = f"https://raw.githubusercontent.com/{owner_repo}/{tag}/module.json"
    try:
        with urllib.request.urlopen(raw, timeout=4) as resp:
            mj = json.load(resp)
    except Exception:
        continue
    if matches(mj.get("requiresLoader", ""), loader):
        chosen = r
        break

if not chosen:
    chosen = releases[0]
    not_tested = True

asset_url = ""
hint_re = re.compile(re.escape(asset_hint), re.I) if asset_hint else None
for a in chosen.get("assets", []):
    n = a["name"].lower()
    if hint_re and hint_re.search(a["name"]):
        asset_url = a["browser_download_url"]
        break
    if n.endswith(".qsmod") or n.endswith(".zip") or n.endswith(".tar.gz") or n.endswith(".tgz"):
        asset_url = a["browser_download_url"]
        # don't break — let the hinted name win if it appears later
print(f"{chosen['tag_name']}\t{asset_url}")
if not_tested:
    print("NOT_TESTED")
PYEOF
}

# Detect URL shapes we can route through GitHub's releases API:
#   github.com/owner/repo/releases/latest/download/<asset>  → swap latest for picked tag
#   github.com/owner/repo/releases                          → "give me the best release"
#   github.com/owner/repo/releases/                         → same
#   github.com/owner/repo/releases/tag/<tag>                → user pinned this tag, no auto-pick
#   github.com/owner/repo[.git]                             → repo root, fall back to clone
github_owner_repo=""
github_asset_hint=""
forced_tag=""
if [[ "$url" =~ ^https://github\.com/([^/]+/[^/]+)/releases/tag/(.+)$ ]]; then
    github_owner_repo="${BASH_REMATCH[1]}"
    forced_tag="${BASH_REMATCH[2]}"
elif [[ "$url" =~ ^https://github\.com/([^/]+/[^/]+)/releases/?$ ]]; then
    github_owner_repo="${BASH_REMATCH[1]}"
elif [[ "$url" =~ ^https://github\.com/([^/]+/[^/]+)/releases/(latest|download)/([^/]+/)?([^/]+)$ ]]; then
    github_owner_repo="${BASH_REMATCH[1]}"
    github_asset_hint="${BASH_REMATCH[4]}"
elif [[ "$url" =~ ^https://github\.com/([^/]+/[^/]+?)(\.git)?/?$ ]]; then
    github_owner_repo="${BASH_REMATCH[1]}"
fi
github_owner_repo="${github_owner_repo%.git}"

chosen_tag=""
chosen_asset=""
not_tested=0
if [ -n "$forced_tag" ]; then
    # User pinned a specific tag — honour it, look up assets explicitly.
    if assets_json=$(curl -fsSL -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$github_owner_repo/releases/tags/$forced_tag" 2>/dev/null); then
        chosen_tag="$forced_tag"
        chosen_asset=$(printf '%s' "$assets_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for a in d.get('assets', []):
    n = a['name'].lower()
    if n.endswith('.qsmod') or n.endswith('.zip') or n.endswith('.tar.gz') or n.endswith('.tgz'):
        print(a['browser_download_url']); break
" 2>/dev/null)
    fi
elif [ -n "$github_owner_repo" ] && [ -n "$loader_version" ]; then
    if out=$(pick_compatible "$github_owner_repo" "$loader_version" "$github_asset_hint" 2>/dev/null); then
        chosen_tag=$(printf '%s\n' "$out" | head -1 | cut -f1)
        chosen_asset=$(printf '%s\n' "$out" | head -1 | cut -f2)
        if printf '%s\n' "$out" | grep -q '^NOT_TESTED$'; then
            not_tested=1
        fi
    fi
fi

# If we picked a release with a downloadable asset, fetch THAT.
if [ -n "$chosen_asset" ]; then
    curl -fsSL --retry 2 "$chosen_asset" -o "$dest"
elif [ -n "$chosen_tag" ]; then
    # Release found but no asset — clone at the tag.
    rm -rf "$dest"
    git clone --depth 1 --branch "$chosen_tag" "https://github.com/$github_owner_repo.git" "$dest" >/dev/null 2>&1
    rm -rf "$dest/.git"
elif is_archive "$url"; then
    curl -fsSL --retry 2 "$url" -o "$dest"
elif [[ "$url" =~ ^(https://|git@)github\.com[:/] ]]; then
    repo="$url"
    branch=""
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

if [ "$not_tested" -eq 1 ]; then
    echo "NOT_TESTED" >&2
fi
printf %s "$dest"
