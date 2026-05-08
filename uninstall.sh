#!/usr/bin/env bash
# Removes the User Modules system from a quickshell config.
# Reverts patches by reversing the find/replace pairs in patches.json.
# Does NOT delete user-installed modules or their patches' originals/.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CFG_DIR="${SHELL_CFG_DIR:-$HOME/.config/illogical-impulse}"
STATE_DIR="${QS_USER_MODULES_STATE:-$SHELL_CFG_DIR/user_modules_state}"

# Auto-detect the quickshell config dir (same logic as install.sh).
detect_qs_dir() {
    local candidates=()
    [ -n "${QS_DIR:-}" ] && candidates+=("$QS_DIR")
    candidates+=(
        "$HOME/.config/quickshell/ii"
        "$HOME/.config/quickshell"
    )
    for d in "${candidates[@]}"; do
        if [ -f "$d/shell.qml" ] && [ -d "$d/modules/common" ]; then
            QS_DIR="$d"
            return 0
        fi
    done
    return 1
}
if ! detect_qs_dir; then
    echo "error: no quickshell config found (set QS_DIR=/path)" >&2; exit 1
fi
echo ":: target shell: $QS_DIR"

# 0. If any patching modules are still applied, revert them first so we don't
#    leave file mods orphaned.
if [ -f "$STATE_DIR/applied.json" ]; then
    echo ":: reverting patches from active modules"
    while IFS= read -r id; do
        [ -n "$id" ] && bash "$QS_DIR/scripts/user_modules/patch.sh" disable "$id" || true
    done < <(jq -r 'keys[]?' "$STATE_DIR/applied.json" 2>/dev/null || true)
fi

# 1. Reverse text patches in patches.json (swap find/replace)
python3 - "$QS_DIR" "$HERE/patches.json" <<'PY'
import json, sys
from pathlib import Path
target = Path(sys.argv[1])
spec = json.loads(Path(sys.argv[2]).read_text())
for p in spec.get("patches", []):
    f = target / p["file"]
    if not f.exists(): continue
    text = f.read_text()
    rev_find, rev_replace = p["replace"], p["find"]
    if rev_find in text and rev_replace not in text.replace(rev_find, "", 1):
        text = text.replace(rev_find, rev_replace, 1)
        f.write_text(text)
        print(f"[-   ] {p['file']}")
    else:
        print(f"[skip] {p['file']}: not in patched state")
PY

# 2. Remove the new files
rm -rf "$QS_DIR/services/UserModules.qml" \
       "$QS_DIR/modules/userModules" \
       "$QS_DIR/modules/settings/ModulesConfig.qml" \
       "$QS_DIR/scripts/user_modules" \
       "$QS_DIR/MODULES.md" \
       "$QS_DIR/defaults/user_modules"

cat <<EOF

Uninstalled. Reload quickshell.
Kept (in case you want them):
  • $SHELL_CFG_DIR/user_modules         (your installed modules)
  • $STATE_DIR                          (originals + applied.json)
Delete those manually if you don't need them.
EOF
