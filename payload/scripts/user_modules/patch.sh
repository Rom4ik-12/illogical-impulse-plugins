#!/usr/bin/env bash
# user_modules/patch.sh — apply/revert text patches contributed by user modules.
#
# Usage:
#   patch.sh enable <id>      # apply patches declared in <id>/module.json
#   patch.sh disable <id>     # revert <id>'s patches; re-apply other modules
#   patch.sh reapply-all      # re-apply every module currently in applied.json
#                             # (use after a shell upgrade if originals are fresh)
#   patch.sh rebaseline       # discard backups; treat current files as pristine
#   patch.sh status           # print currently-applied module ids
#
# Patches are described in module.json:
#   { "patches": [ { "file": "shell.qml",
#                    "find": "EXACT TEXT",
#                    "replace": "NEW TEXT" } ] }
#
# Find must match the file exactly once.

set -euo pipefail

SHELL_DIR="${QS_SHELL_DIR:-$HOME/.config/quickshell}"
MODS_DIR="${QS_USER_MODULES_DIR:-$HOME/.config/illogical-impulse/user_modules}"
STATE_DIR="${QS_USER_MODULES_STATE:-$HOME/.config/illogical-impulse/user_modules_state}"
ORIG_DIR="$STATE_DIR/originals"
APPLIED="$STATE_DIR/applied.json"

mkdir -p "$ORIG_DIR"
[ -f "$APPLIED" ] || echo '{}' > "$APPLIED"

orig_path()  { echo "$ORIG_DIR/${1//\//__}"; }

backup_file() {
    local rel="$1"; local dst; dst=$(orig_path "$rel")
    [ -f "$SHELL_DIR/$rel" ] || { echo "[patch] missing target file: $rel" >&2; exit 4; }
    [ -f "$dst" ] || cp "$SHELL_DIR/$rel" "$dst"
}

restore_file() {
    local rel="$1"; local src; src=$(orig_path "$rel")
    [ -f "$src" ] && cp "$src" "$SHELL_DIR/$rel"
}

# Returns the patches array (or [])
get_patches() {
    local id="$1"; local m="$MODS_DIR/$id/module.json"
    [ -f "$m" ] || { echo "[]"; return; }
    jq -c '.patches // []' "$m"
}

# Apply one find/replace via python (handles multi-line, no escaping pain)
apply_patch_py() {
    local file="$1" find="$2" replace="$3"
    python3 - "$file" "$find" "$replace" <<'PY'
import sys
path, find, replace = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f: data = f.read()
n = data.count(find)
if n == 0:
    sys.stderr.write(f"[patch] anchor not found in {path}\n"); sys.exit(2)
if n > 1:
    sys.stderr.write(f"[patch] anchor matches {n} places in {path}, must be unique\n"); sys.exit(3)
with open(path, "w") as f: f.write(data.replace(find, replace, 1))
PY
}

apply_module() {
    local id="$1"
    # Already recorded as applied — skip so enable/reapply-all are idempotent.
    if jq -e --arg id "$id" 'has($id)' "$APPLIED" >/dev/null 2>&1; then
        return 0
    fi
    local patches; patches=$(get_patches "$id")
    [ "$patches" = "[]" ] && return 0
    local n; n=$(jq 'length' <<< "$patches")
    local touched=()
    for ((i=0; i<n; i++)); do
        local rel find replace
        rel=$(jq -r ".[$i].file"    <<< "$patches")
        find=$(jq -r ".[$i].find"    <<< "$patches")
        replace=$(jq -r ".[$i].replace" <<< "$patches")
        backup_file "$rel"
        apply_patch_py "$SHELL_DIR/$rel" "$find" "$replace"
        touched+=("$rel")
    done
    # Record touched files for this id
    local list_json; list_json=$(printf '%s\n' "${touched[@]}" | jq -R . | jq -s 'unique')
    local tmp; tmp=$(mktemp)
    jq --arg id "$id" --argjson v "$list_json" '.[$id] = $v' "$APPLIED" > "$tmp" && mv "$tmp" "$APPLIED"
}

revert_module() {
    local id="$1"
    local files; files=$(jq -r --arg id "$id" '.[$id] // [] | .[]' "$APPLIED" || true)
    [ -z "$files" ] && return 0
    while IFS= read -r rel; do [ -n "$rel" ] && restore_file "$rel"; done <<< "$files"
    local tmp; tmp=$(mktemp)
    jq --arg id "$id" 'del(.[$id])' "$APPLIED" > "$tmp" && mv "$tmp" "$APPLIED"
    # Re-apply patches from any still-active module (in stable order).
    local others; others=$(jq -r 'keys_unsorted[]' "$APPLIED" || true)
    while IFS= read -r other; do [ -n "$other" ] && apply_module "$other"; done <<< "$others"
}

reapply_all() {
    local ids; ids=$(jq -r 'keys[]' "$APPLIED" || true)
    # Restore every file any active module has touched before re-applying,
    # so repeated reapply-all calls don't stack patches on a half-patched file.
    local all_files; all_files=$(jq -r '[.[]] | flatten | unique | .[]' "$APPLIED" || true)
    while IFS= read -r rel; do [ -n "$rel" ] && restore_file "$rel"; done <<< "$all_files"
    echo '{}' > "$APPLIED"
    while IFS= read -r id; do [ -n "$id" ] && apply_module "$id"; done <<< "$ids"
}

case "${1:-}" in
    enable)      apply_module  "${2:?need module id}" ;;
    disable)     revert_module "${2:?need module id}" ;;
    reapply-all) reapply_all ;;
    rebaseline)
        rm -rf "$ORIG_DIR"; mkdir -p "$ORIG_DIR"
        echo '{}' > "$APPLIED"
        echo "rebaselined." ;;
    status)      jq -r 'keys[]' "$APPLIED" ;;
    *) echo "Usage: $0 {enable|disable|reapply-all|rebaseline|status} [id]" >&2; exit 1 ;;
esac
