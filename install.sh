#!/usr/bin/env bash
# Installs the User Modules system into a quickshell config.
#
# Defaults to ~/.config/quickshell. Override with QS_DIR=/some/path ./install.sh
# Bar slot insertion (BarContent.qml) is optional — skipped if upstream
# anchors are not present.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CFG_DIR="${SHELL_CFG_DIR:-$HOME/.config/illogical-impulse}"

# Auto-detect the quickshell config dir. The illogical-impulse setup can put
# the actual files in either ~/.config/quickshell/ (flat) or
# ~/.config/quickshell/ii/ (the upstream layout). Honour QS_DIR if set.
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
    cat >&2 <<EOF
error: could not find a quickshell config (looked for shell.qml + modules/common in:
  \$QS_DIR (${QS_DIR:-unset})
  \$HOME/.config/quickshell/ii
  \$HOME/.config/quickshell
)
Pass QS_DIR=/path/to/quickshell ./install.sh to override.
EOF
    exit 1
fi
command -v python3 >/dev/null || { echo "error: python3 required" >&2; exit 1; }
command -v jq      >/dev/null || echo "warn: jq not found — patch.sh runtime ops will fail until installed" >&2

echo ":: target shell:  $QS_DIR"
echo ":: modules dir:   $SHELL_CFG_DIR/user_modules"

# 1. Copy payload (new files). -n keeps user edits if they re-run.
cp -rn "$HERE/payload/." "$QS_DIR/"

# Refresh files we always want current from the installer.
# (Pre-create parent dirs so cp can't fail on a fresh install.)
REFRESH=(
    services/UserModules.qml
    modules/userModules/UserModulesHost.qml
    modules/userModules/UserModulesBarSlot.qml
    modules/userModules/qmldir
    modules/settings/ModulesConfig.qml
    modules/common/widgets/Md3Spinner.qml
    modules/common/widgets/RippleButtonWithIcon.qml
    scripts/user_modules/patch.sh
    scripts/user_modules/fetch.sh
    MODULES.md
    VERSION
)
for f in "${REFRESH[@]}"; do
    mkdir -p "$QS_DIR/$(dirname "$f")"
    cp "$HERE/payload/$f" "$QS_DIR/$f"
done
chmod +x "$QS_DIR/scripts/user_modules/patch.sh" \
         "$QS_DIR/scripts/user_modules/fetch.sh"

# 2. Patch existing files
python3 "$HERE/apply_patches.py" "$QS_DIR"

# 2a. Rebaseline user-module patch backups so each module applies against the
# freshly-reverted upstream files (prevents stacked/drifted patches after a
# loader update).
if [ -x "$QS_DIR/scripts/user_modules/patch.sh" ]; then
    echo ":: rebaselining user module patches"
    bash "$QS_DIR/scripts/user_modules/patch.sh" rebaseline
fi

# 2b. Merge our translation strings into existing locale files (additive —
# we never clobber an existing key, only fill in missing ones).
if [ -d "$HERE/payload/translations" ] && [ -d "$QS_DIR/translations" ]; then
    for src in "$HERE/payload/translations"/*.json; do
        [ -f "$src" ] || continue
        dst="$QS_DIR/translations/$(basename "$src")"
        if [ -f "$dst" ]; then
            python3 - "$src" "$dst" <<'PYEOF'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f: a = json.load(f)
with open(dst) as f: b = json.load(f)
changed = False
for k, v in a.items():
    if k not in b:
        b[k] = v
        changed = True
if changed:
    with open(dst, 'w') as f:
        json.dump(b, f, ensure_ascii=False, indent=2)
        f.write('\n')
PYEOF
        else
            cp "$src" "$dst"
        fi
    done
fi

# 3. User-modules dir
mkdir -p "$SHELL_CFG_DIR/user_modules"

# 4. Verify the critical files actually exist after install
echo
echo ":: verify"
missing=0
for f in "${REFRESH[@]}"; do
    if [ -f "$QS_DIR/$f" ]; then
        echo "  ok   $f"
    else
        echo "  FAIL $f" >&2
        missing=$((missing + 1))
    fi
done
if [ "$missing" -gt 0 ]; then
    echo "error: $missing file(s) missing — install likely failed." >&2
    exit 2
fi
# Also confirm the shell.qml patch survived
if ! grep -q "UserModulesHost" "$QS_DIR/shell.qml"; then
    echo "warn: shell.qml does not reference UserModulesHost — patch may not have applied" >&2
    echo "      (your shell.qml might use a non-default layout)" >&2
fi

cat <<EOF

Done. Reload quickshell to pick up the changes.
  • Settings → Modules to manage user modules
  • Bundled examples live under: $QS_DIR/defaults/user_modules/
  • Read $QS_DIR/MODULES.md for the format and patch system.
EOF
