#!/usr/bin/env python3
"""Idempotent text-patch applier for the User Modules installer.

Reads patches from patches.json, applies them to files in the target shell
directory. A patch is skipped if its `skip_if_present` substring is already
present. Translation keys are merged into existing JSONs without
overwriting values the user already set.
"""

from __future__ import annotations
import json, os, re, sys
from pathlib import Path

LOADER_URL = "https://github.com/Rom4ik-12/illogical-impulse-plugins/releases/latest/download/illogical-impulse-plugins.tar.gz"

def migrate_user_modules_block(text: str) -> tuple[str, list[str]]:
    """Ensure the userModules JsonObject contains loaderUpdateUrl and
    seenVersionsJson. Old installs only had `enabled`, so without this an
    update would leave them stuck on "Set userModules.loaderUpdateUrl…" or
    a JsonAdapter segfault from a stale `seenVersions: var` property.
    Returns (new_text, list-of-added-property-names)."""
    m = re.search(
        r"(property JsonObject userModules: JsonObject \{)(?P<body>[^{}]*?)(?P<tail>\n\s*\})",
        text, flags=re.S)
    if not m:
        return text, []
    body = m.group("body")
    indent_match = re.search(r"\n([ \t]+)property\b", body)
    indent = indent_match.group(1) if indent_match else "                "
    added: list[str] = []
    new_body = body
    if "loaderUpdateUrl" not in body:
        new_body += f'\n{indent}property string loaderUpdateUrl: "{LOADER_URL}"'
        added.append("loaderUpdateUrl")
    if "seenVersionsJson" not in body:
        new_body += f'\n{indent}property string seenVersionsJson: "{{}}"'
        added.append("seenVersionsJson")
    # Strip the legacy broken `property var seenVersions: ...` line — it
    # caused JsonAdapter segfaults on nested-object deserialisation.
    new_body, n_drop = re.subn(
        r"\n[ \t]+property var seenVersions:[^\n]*", "", new_body)
    if n_drop:
        added.append("-seenVersions")
    if new_body == body:
        return text, []
    return text[:m.start()] + m.group(1) + new_body + m.group("tail") + text[m.end():], added

def apply(target: Path, payload_dir: Path, patches_file: Path) -> int:
    spec = json.loads(patches_file.read_text())
    rc = 0

    # Run schema migrations on Config.qml first — these handle older installs
    # whose userModules block was patched in before new properties existed.
    cfg = target / "modules/common/Config.qml"
    if cfg.exists():
        text = cfg.read_text()
        new_text, added = migrate_user_modules_block(text)
        if added:
            cfg.write_text(new_text)
            print(f"[mig ] Config.qml userModules: {', '.join(added)}")

    for p in spec.get("patches", []):
        rel = p["file"]
        f = target / rel
        if not f.exists():
            if p.get("optional"):
                print(f"[skip] {rel} (not found, optional)")
                continue
            print(f"[ERR ] {rel} not found", file=sys.stderr); rc = 1; continue

        text = f.read_text()
        if p.get("skip_if_present") and p["skip_if_present"] in text:
            print(f"[ok  ] {rel}: already patched")
            continue

        find = p["find"]
        n = text.count(find)
        if n == 0:
            print(f"[ERR ] {rel}: anchor not found", file=sys.stderr); rc = 1; continue
        if n > 1:
            print(f"[ERR ] {rel}: anchor matches {n} times, must be unique", file=sys.stderr); rc = 1; continue

        f.write_text(text.replace(find, p["replace"], 1))
        print(f"[+   ] {rel}")

    # Translations: merge keys, never overwrite existing
    tr_dir = target / "translations"
    if tr_dir.is_dir():
        for lang, kv in spec.get("translations", {}).items():
            tf = tr_dir / f"{lang}.json"
            if not tf.exists():
                continue
            try:
                data = json.loads(tf.read_text())
            except Exception as e:
                print(f"[ERR ] {tf}: invalid JSON: {e}", file=sys.stderr); rc = 1; continue
            added = 0
            for k, v in kv.items():
                if k not in data:
                    data[k] = v; added += 1
            if added:
                tf.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
                print(f"[+   ] translations/{lang}.json (+{added})")
            else:
                print(f"[ok  ] translations/{lang}.json: nothing to add")
    return rc

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: apply_patches.py <quickshell-dir>", file=sys.stderr); sys.exit(2)
    target = Path(sys.argv[1]).expanduser().resolve()
    here = Path(__file__).resolve().parent
    sys.exit(apply(target, here / "payload", here / "patches.json"))
