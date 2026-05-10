pragma Singleton
pragma ComponentBehavior: Bound

// User Modules service
//
// Scans `~/.config/illogical-impulse/user_modules/<id>/module.json` and
// exposes the list as `modules`. Enabled module IDs come from
// `Config.options.userModules.enabled`.
//
// A module folder layout:
//   user_modules/<id>/module.json   (manifest)
//   user_modules/<id>/main.qml      (entry, or whatever `entry` points to)
//
// See ~/.config/quickshell/MODULES.md for the full spec.

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // [{ id, dir, entry, manifest: {...} }, ...]
    property var modules: []
    property string lastError: ""
    property string lastExportPath: ""
    property string _modulesSignature: ""

    // Loading state — exposed so the UI can show spinners.
    property bool loaderUpdating: false
    property bool refreshing: false
    property bool installing: false
    property bool rebaselining: false
    property string updatingModuleId: ""
    property var _updateQueue: []

    // Current loader version. install.sh ships a VERSION file alongside the
    // payload; we read it on startup. Drives compatibility checks against a
    // module manifest's `requiresLoader` field.
    property string loaderVersion: "1.4.10"

    // Available loader release tags fetched from GitHub (newest first).
    // Populated by fetchLoaderVersions(); the UI calls it lazily.
    property var availableLoaderVersions: []
    property bool fetchingLoaderVersions: false

    FileView {
        id: loaderVersionFile
        path: Quickshell.shellPath("VERSION")
        onLoaded: {
            const v = (loaderVersionFile.text || "").trim();
            if (v.length > 0) root.loaderVersion = v;
        }
        onLoadFailed: {}
    }

    // True if the module declares no compatibility, or its declared
    // requiresLoader matches the current loader version (semver-prefix).
    // Examples: "1.3" matches loader 1.3.x; "1" matches 1.x.x; "*" matches
    // anything. A missing field → true (unknown — assume ok).
    function isCompatible(id) {
        const m = root.modules.find(x => x.id === id);
        if (!m || !m.manifest) return true;
        const req = (m.manifest.requiresLoader || "").trim();
        return _versionPrefixMatches(req, root.loaderVersion);
    }

    function _versionPrefixMatches(req, ver) {
        if (!req || req === "*") return true;
        const rp = req.replace(/^v/, "").split(".");
        const vp = ver.replace(/^v/, "").split(".");
        for (let i = 0; i < rp.length; i++) {
            const a = rp[i], b = vp[i] || "";
            if (a === "*" || a === "x") continue;
            if (a !== b) return false;
        }
        return true;
    }

    // Flat list of bar widgets contributed by enabled modules:
    // [{ moduleId, url }]. Drop a `UserModulesBarSlot {}` somewhere in the
    // bar layout to render them.
    readonly property var barWidgets: {
        const out = [];
        for (const m of root.modules) {
            if (!root.isEnabled(m.id)) continue;
            const widgets = (m.manifest && m.manifest.barWidgets) || [];
            for (const w of widgets) {
                if (!w || !w.source) continue;
                out.push({ moduleId: m.id, url: `file://${m.dir}/${w.source}` });
            }
        }
        return out;
    }

    readonly property string modulesDir: Directories.userModulesDir
    readonly property string patchScript: `${Directories.scriptPath}/user_modules/patch.sh`
    readonly property string fetchScript: `${Directories.scriptPath}/user_modules/fetch.sh`

    function hasUpdateUrl(id) {
        const m = root.modules.find(x => x.id === id);
        return !!(m && m.manifest && typeof m.manifest.updateUrl === "string" && m.manifest.updateUrl.length > 0);
    }

    // Read/write per-module user notes. Storage is a JSON-encoded string in
    // Config (`notesJson`) for the same reason as seenVersionsJson — plain
    // `var` segfaults in JsonAdapter on nested-object reload.
    function getNote(id) {
        let map = {};
        try { map = JSON.parse(Config.options.userModules.notesJson || "{}"); } catch(e) {}
        return map[id] || "";
    }

    function setNote(id, text) {
        let map = {};
        try { map = JSON.parse(Config.options.userModules.notesJson || "{}"); } catch(e) {}
        const t = (text || "").trim();
        if (t.length === 0) {
            delete map[id];
        } else {
            map[id] = t;
        }
        Config.options.userModules.notesJson = JSON.stringify(map);
    }

    // Pop a "Open file" dialog and install whatever the user picks.
    function pickAndInstall() {
        root.installing = true;
        const cmd = `if command -v zenity >/dev/null 2>&1; then `
            + `  zenity --file-selection --title='Install module' `
            + `    --file-filter='*.qsmod *.zip' --file-filter='All files | *' 2>/dev/null;`
            + `elif command -v kdialog >/dev/null 2>&1; then `
            + `  kdialog --getopenfilename "$HOME" '*.qsmod *.zip' 2>/dev/null;`
            + `else echo ''; fi`;
        pickInstallProc.command = ["bash", "-c", cmd];
        pickInstallProc.running = true;
    }

    // Download (curl/git) the module's updateUrl and replace the local copy.
    // If the module is currently enabled and has patches, we revert first,
    // then re-apply after install.
    function updateModule(id) {
        const m = root.modules.find(x => x.id === id);
        if (!m || !m.manifest.updateUrl) return;
        const wasEnabled = root.isEnabled(id);
        const hadPatches = root.hasPatches(id);
        if (wasEnabled && hadPatches) {
            // Disable to revert patches before files change
            root.setEnabled(id, false);
        }
        root.updatingModuleId = id;
        updateProc.targetId = id;
        updateProc.wasEnabled = wasEnabled;
        updateProc.command = ["bash", root.fetchScript,
            m.manifest.updateUrl, `/tmp/qsmod-update-${id}`, root.loaderVersion];
        updateProc.running = true;
    }

    function updateAll() {
        const q = [];
        for (const m of root.modules) {
            if (root.hasUpdateUrl(m.id)) q.push(m.id);
        }
        root._updateQueue = q;
        root._runNextUpdate();
    }

    function _runNextUpdate() {
        if (root.updatingModuleId !== "" || root.installing) return;
        if (!root._updateQueue || root._updateQueue.length === 0) return;
        const q = root._updateQueue.slice();
        const next = q.shift();
        root._updateQueue = q;
        root.updateModule(next);
    }

    function isEnabled(id) {
        const list = Config.options?.userModules?.enabled ?? [];
        return list.indexOf(id) !== -1;
    }

    // True if the module declares any text patches in its manifest.
    function hasPatches(id) {
        const m = root.modules.find(x => x.id === id);
        return !!(m && m.manifest && Array.isArray(m.manifest.patches) && m.manifest.patches.length > 0);
    }

    // True if the module provides a settings page QML.
    function hasSettingsPage(id) {
        const m = root.modules.find(x => x.id === id);
        return !!(m && m.manifest && m.manifest.settingsPage);
    }

    // True if module has a changelog and current version wasn't seen yet.
    // Storage is a JSON-encoded string in Config (`seenVersionsJson`) because
    // JsonAdapter segfaults on `property var` for nested objects.
    function isNewVersion(id) {
        const m = root.modules.find(x => x.id === id);
        if (!m || !m.manifest.changelog) return false;
        let seen = {};
        try { seen = JSON.parse(Config.options.userModules.seenVersionsJson || "{}"); } catch(e) {}
        return seen[id] !== (m.manifest.version || "");
    }

    // Mark the current version of a module as seen.
    function markSeen(id) {
        const m = root.modules.find(x => x.id === id);
        if (!m) return;
        let seen = {};
        try { seen = JSON.parse(Config.options.userModules.seenVersionsJson || "{}"); } catch(e) {}
        seen[id] = m.manifest.version || "";
        Config.options.userModules.seenVersionsJson = JSON.stringify(seen);
    }

    // Returns the per-module writable data directory and ensures it exists.
    // Modules can use this path for their own config/state files.
    function moduleDataDir(id) {
        const path = `${Directories.shellConfig}/user_modules_state/${id}`;
        mkdirProc.command = ["bash", "-c", `mkdir -p '${path}'`];
        mkdirProc.running = true;
        return path;
    }

    function _writeEnabled(id, enabled) {
        const list = (Config.options.userModules.enabled ?? []).slice();
        const idx = list.indexOf(id);
        if (enabled && idx === -1) list.push(id);
        if (!enabled && idx !== -1) list.splice(idx, 1);
        Config.options.userModules.enabled = list;
    }

    function setEnabled(id, enabled) {
        if (!hasPatches(id)) {
            _writeEnabled(id, enabled);
            return;
        }
        // Run the patch helper first; flip the config only on success.
        patchProc.pendingId = id;
        patchProc.pendingEnabled = enabled;
        patchProc.command = ["bash", root.patchScript, enabled ? "enable" : "disable", id];
        patchProc.running = true;
    }

    function rebaselinePatches() {
        root.rebaselining = true;
        rebaselineProc.running = true;
    }

    // Self-update: download a new installer tarball / clone a repo and run
    // its install.sh, replacing the loader files in this shell. Pass a tag
    // (e.g. "v1.4.3") to install that specific release instead of latest.
    function updateLoader(versionTag) {
        let url = (Config.options?.userModules?.loaderUpdateUrl ?? "").trim();
        if (url.length === 0) {
            root.lastError = "Set userModules.loaderUpdateUrl in config.json first.";
            return;
        }
        const tag = (versionTag || "").trim();
        if (tag.length > 0) {
            // Rewrite "releases/latest/download/<asset>" → "releases/download/<tag>/<asset>"
            url = url.replace(/\/releases\/latest\/download\//, `/releases/download/${tag}/`);
        }
        root.loaderUpdating = true;
        loaderUpdateProc.command = ["bash", "-c",
              `set -e;`
            + `url='${StringUtils.shellSingleQuoteEscape(url)}';`
            + `tmp=$(mktemp -d -t qsmod-loader-XXXX);`
            + `cd "$tmp";`
            + `case "$url" in `
            + `  *.tar.gz|*.tgz) curl -fsSL --retry 2 "$url" -o pkg.tgz; tar xzf pkg.tgz ;;`
            + `  *.zip)          curl -fsSL --retry 2 "$url" -o pkg.zip; unzip -q pkg.zip ;;`
            + `  https://github.com/*|git@github.com:*) git clone --depth 1 "$url" repo >/dev/null 2>&1 ;;`
            + `  *)              curl -fsSL --retry 2 "$url" -o pkg.tgz; tar xzf pkg.tgz ;;`
            + `esac;`
            + `installer=$(find "$tmp" -maxdepth 5 -type f -name install.sh | head -1);`
            + `[ -n "$installer" ] || { echo "no install.sh found in payload" >&2; exit 2; };`
            + `bash "$installer";`
            + `rm -rf "$tmp"`
        ];
        loaderUpdateProc.running = true;
    }

    function refresh() {
        root.refreshing = true;
        scanProc.running = true;
    }

    // Pull the list of release tags from the loader's GitHub repo. Derives
    // the API URL from `loaderUpdateUrl` (must be a github.com URL) and fills
    // `availableLoaderVersions` newest-first.
    function fetchLoaderVersions() {
        const url = (Config.options?.userModules?.loaderUpdateUrl ?? "").trim();
        const m = url.match(/github\.com\/([^\/]+)\/([^\/]+)/);
        if (!m) {
            root.lastError = "loaderUpdateUrl is not a github.com URL — cannot list versions.";
            return;
        }
        root.fetchingLoaderVersions = true;
        const api = `https://api.github.com/repos/${m[1]}/${m[2]}/releases?per_page=30`;
        fetchVersionsProc.command = ["bash", "-c",
            `curl -sf '${api}' | python3 -c "import sys,json;`
            + `print('\\n'.join(r['tag_name'] for r in json.load(sys.stdin) if not r.get('draft')))"`
        ];
        fetchVersionsProc.running = true;
    }

    function openFolder() {
        Quickshell.execDetached(["xdg-open", root.modulesDir]);
    }

    function openModuleFolder(id) {
        Quickshell.execDetached(["xdg-open", `${root.modulesDir}/${id}`]);
    }

    function uninstall(id) {
        if (!id || id.indexOf("/") !== -1 || id.indexOf("..") !== -1) return;
        const m = root.modules.find(x => x.id === id);
        // Resolve the actual directory: legacy installs may sit in a folder
        // named differently from manifest.id (e.g. "foo-main"), so trust the
        // scanned dir over a synthesized path.
        const base = root.modulesDir.replace(/\/+$/, "");
        let dir = (m && m.dir) ? m.dir : `${base}/${id}`;
        if (dir.indexOf(base + "/") !== 0) return; // path-escape guard

        uninstallProc.targetDir = dir;
        uninstallProc.targetId = id;

        if (root.hasPatches(id) && root.isEnabled(id)) {
            // Revert patches first; rm fires from patchProc.onExited.
            uninstallProc.pendingPatchRevert = true;
            root.setEnabled(id, false);
        } else {
            if (root.isEnabled(id)) root._writeEnabled(id, false);
            uninstallProc.pendingPatchRevert = false;
            uninstallProc.command = ["bash", "-c",
                `rm -rf '${StringUtils.shellSingleQuoteEscape(dir)}'`];
            uninstallProc.running = true;
        }
    }

    // Pops a "Save As" dialog (zenity/kdialog) and zips the module folder
    // to the chosen path. If neither tool is available, falls back to
    // ~/Downloads/<id>.qsmod. Sets `lastExportPath` on success.
    function exportModule(id, destPath) {
        const fallback = `${FileUtils.trimFileProtocol(Directories.downloads)}/${id}.qsmod`;
        if (destPath && destPath.length > 0) {
            // Skip the picker — caller already knows where to put it.
            const dst = FileUtils.trimFileProtocol(destPath);
            exportProc.command = ["bash", "-c",
                  `mkdir -p '${StringUtils.shellSingleQuoteEscape(dst.substring(0, dst.lastIndexOf("/")))}' && `
                + `cd '${StringUtils.shellSingleQuoteEscape(root.modulesDir)}' && `
                + `zip -qr '${StringUtils.shellSingleQuoteEscape(dst)}' `
                + `'${StringUtils.shellSingleQuoteEscape(id)}' && `
                + `printf %s '${StringUtils.shellSingleQuoteEscape(dst)}'`];
            exportProc.running = true;
            return;
        }
        // Picker + zip in one go. The script prints the final path on stdout.
        const cmd = `set -e;`
            + `id='${StringUtils.shellSingleQuoteEscape(id)}';`
            + `default='${StringUtils.shellSingleQuoteEscape(fallback)}';`
            + `target='';`
            + `if command -v zenity >/dev/null 2>&1; then `
            + `  target=$(zenity --file-selection --save --confirm-overwrite `
            + `    --title="Export $id" --filename="$default" --file-filter='*.qsmod' 2>/dev/null) || exit 0;`
            + `elif command -v kdialog >/dev/null 2>&1; then `
            + `  target=$(kdialog --getsavefilename "$default" '*.qsmod' 2>/dev/null) || exit 0;`
            + `fi;`
            + `target="\${target:-$default}";`
            + `mkdir -p "$(dirname "$target")";`
            + `cd '${StringUtils.shellSingleQuoteEscape(root.modulesDir)}' && zip -qr "$target" "$id" >/dev/null;`
            + `printf %s "$target"`;
        exportProc.command = ["bash", "-c", cmd];
        exportProc.running = true;
    }

    // Detect URL-style sources and route them through the fetcher.
    function installFromUrlOrPath(source) {
        const s = (source || "").trim();
        if (s.length === 0) return;
        root.installing = true;
        if (/^https?:\/\//.test(s) || /^git@/.test(s)) {
            urlInstallProc.command = ["bash", root.fetchScript, s,
                `/tmp/qsmod-install-${Date.now()}`, root.loaderVersion];
            urlInstallProc.running = true;
        } else {
            root.install(s);
        }
    }

    // Install from a .qsmod (zip) or a plain folder. Source path may use file:// .
    function install(sourcePath) {
        const src = FileUtils.trimFileProtocol(sourcePath).trim();
        if (src.length === 0) return;
        root.installing = true;
        const cmd = `set -e; `
            + `src='${StringUtils.shellSingleQuoteEscape(src)}'; `
            + `dst='${StringUtils.shellSingleQuoteEscape(root.modulesDir)}'; `
            + `mkdir -p "$dst"; `
            + `tmp=$(mktemp -d); `
            + `if [ -d "$src" ]; then cp -r "$src" "$tmp/"; `
            + `else unzip -q "$src" -d "$tmp"; fi; `
            // Find any folder containing a module.json; copy each into dst.
            // Use the manifest's `id` as the destination folder name so that
            // re-installing a module (e.g. from github-default-branch zip
            // named "foo-main") overwrites the existing folder instead of
            // creating a parallel copy.
            + `find "$tmp" -name module.json -print0 | while IFS= read -r -d '' m; do `
            + `  d=$(dirname "$m"); `
            + `  n=$(python3 -c "import json,sys,re; mid=str(json.load(open(sys.argv[1])).get('id','')).strip(); print(mid if re.match(r'^[A-Za-z0-9._-]+$', mid) else '')" "$m" 2>/dev/null); `
            + `  [ -z "$n" ] && n=$(basename "$d"); `
            + `  rm -rf "$dst/$n"; cp -r "$d" "$dst/$n"; `
            + `done; `
            + `rm -rf "$tmp"`;
        installProc.command = ["bash", "-c", cmd];
        installProc.running = true;
    }

    Component.onCompleted: refresh()

    Connections {
        target: Config
        function onReadyChanged() { if (Config.ready) root.refresh(); }
    }

    Timer {
        id: rescanTimer
        interval: 250
        repeat: false
        onTriggered: root.refresh()
    }

    // Builds a single JSON array describing every installed module.
    Process {
        id: scanProc
        command: ["bash", "-c",
            `dir='${StringUtils.shellSingleQuoteEscape(root.modulesDir)}';`
            + `mkdir -p "$dir";`
            + `first=1; printf '[';`
            + `for d in "$dir"/*/; do `
            + `  [ -d "$d" ] || continue;`
            + `  m="$d/module.json"; [ -f "$m" ] || continue;`
            + `  id=$(basename "$d");`
            + `  if [ $first -eq 0 ]; then printf ','; fi; first=0;`
            + `  printf '{"_id":"%s","_dir":"%s","manifest":' "$id" "\${d%/}";`
            + `  cat "$m"; printf '}';`
            + `done;`
            + `printf ']'`
        ]
        stdout: StdioCollector {
            id: scanCollector
            onStreamFinished: {
                try {
                    const arr = JSON.parse(scanCollector.text || "[]");
                    const out = [];
                    for (const item of arr) {
                        const m = item.manifest || {};
                        const entry = (m.entry && m.entry.length > 0) ? m.entry : "main.qml";
                        out.push({
                            id: m.id || item._id,
                            dir: item._dir,
                            entry: entry,
                            entryUrl: `file://${item._dir}/${entry}`,
                            manifest: m
                        });
                    }
                    // Only reassign when content actually changes — otherwise
                    // every poll would re-instantiate every loaded module.
                    const newSig = JSON.stringify(out);
                    if (newSig !== root._modulesSignature) {
                        root._modulesSignature = newSig;
                        root.modules = out;
                    }
                    root.lastError = "";
                } catch (e) {
                    root.lastError = `Failed to parse modules: ${e}`;
                    console.warn("[UserModules]", root.lastError, scanCollector.text);
                    root.modules = [];
                }
                root.refreshing = false;
            }
        }
    }

    Process {
        id: installProc
        onExited: (code) => {
            if (code !== 0) console.warn("[UserModules] install failed, exit", code);
            root.installing = false;
            rescanTimer.restart();
            Qt.callLater(root._runNextUpdate);
        }
    }

    Process {
        id: exportProc
        stdout: StdioCollector { id: exportPathBuf }
        onExited: (code) => {
            const out = (exportPathBuf.text || "").trim();
            if (code === 0 && out.length > 0) {
                root.lastError = "";
                root.lastExportPath = out;
                console.log("[UserModules] exported to", out);
            } else if (code === 0 && out.length === 0) {
                // User pressed Cancel in the picker — silent no-op.
            } else {
                root.lastError = `Export failed (code ${code}). Is 'zip' installed?`;
                console.warn("[UserModules]", root.lastError);
            }
        }
    }

    Process {
        id: patchProc
        property string pendingId: ""
        property bool pendingEnabled: false
        property string stderrBuf: ""
        stderr: StdioCollector { id: patchStderr }
        onExited: (code) => {
            if (code === 0) {
                root.lastError = "";
                root._writeEnabled(patchProc.pendingId, patchProc.pendingEnabled);
            } else {
                root.lastError = `Patch ${patchProc.pendingEnabled ? "apply" : "revert"} failed for `
                    + `${patchProc.pendingId}: ${patchStderr.text || "exit " + code}`;
                console.warn("[UserModules]", root.lastError);
            }
            // If an uninstall was waiting on patch revert, fire the rm now —
            // even on revert failure, the user wants the module gone.
            if (uninstallProc.pendingPatchRevert
                && patchProc.pendingId === uninstallProc.targetId) {
                uninstallProc.pendingPatchRevert = false;
                uninstallProc.command = ["bash", "-c",
                    `rm -rf '${StringUtils.shellSingleQuoteEscape(uninstallProc.targetDir)}'`];
                uninstallProc.running = true;
            }
        }
    }

    Process {
        id: uninstallProc
        property string targetDir: ""
        property string targetId: ""
        property bool pendingPatchRevert: false
        onExited: (code) => {
            if (code !== 0) {
                root.lastError = `Uninstall failed (rm exit ${code}) for ${uninstallProc.targetId}`;
                console.warn("[UserModules]", root.lastError);
            }
            uninstallProc.targetDir = "";
            uninstallProc.targetId = "";
            rescanTimer.restart();
        }
    }

    Process {
        id: urlInstallProc
        stdout: StdioCollector { id: urlInstallBuf }
        stderr: StdioCollector { id: urlInstallErrBuf }
        onExited: (code) => {
            const path = (urlInstallBuf.text || "").trim();
            if (code === 0 && path.length > 0) {
                root.install(path);
            } else {
                root.installing = false;
                root.lastError = `Fetch failed: ${urlInstallErrBuf.text || "exit " + code}`;
            }
        }
    }

    Process {
        id: pickInstallProc
        stdout: StdioCollector { id: pickedInstallBuf }
        onExited: (code) => {
            const path = (pickedInstallBuf.text || "").trim();
            if (path.length > 0) root.install(path);
            else root.installing = false;
        }
    }

    Process {
        id: updateProc
        property string targetId: ""
        property bool wasEnabled: false
        stdout: StdioCollector { id: updateBuf }
        stderr: StdioCollector { id: updateErrBuf }
        onExited: (code) => {
            const id = updateProc.targetId;
            const wasEnabled = updateProc.wasEnabled;
            root.updatingModuleId = "";
            const path = (updateBuf.text || "").trim();
            if (code !== 0 || path.length === 0) {
                root.lastError = `Update failed for ${id}: `
                    + (updateErrBuf.text || `exit ${code}`);
                console.warn("[UserModules]", root.lastError);
                // Re-enable if it was disabled for patch revert but update failed.
                if (wasEnabled && root.hasPatches(id)) root.setEnabled(id, true);
                Qt.callLater(root._runNextUpdate);
                return;
            }
            // Reuse the install path. Rescan happens after install too.
            root.install(path);
            // Re-enable after a short delay so the rescan picks up the new files first.
            if (wasEnabled) reEnableTimer.scheduleId(id);
        }
    }
    QtObject {
        id: reEnableTimer
        // Each pending re-enable gets its own timer so concurrent updates
        // (queue) don't overwrite each other's target id.
        function scheduleId(id) {
            const t = Qt.createQmlObject(
                'import QtQuick; Timer { interval: 600; repeat: false; running: true }',
                reEnableTimer, "reEnable_" + id);
            t.triggered.connect(() => {
                if (id && !root.isEnabled(id)) root.setEnabled(id, true);
                t.destroy();
            });
        }
    }

    Process {
        id: loaderUpdateProc
        stdout: StdioCollector { id: loaderOutBuf }
        stderr: StdioCollector { id: loaderErrBuf }
        onExited: (code) => {
            root.loaderUpdating = false;
            if (code === 0) {
                root.lastError = "";
                console.log("[UserModules] loader updated", loaderOutBuf.text);
                fetchNoticeProc.running = true;
            } else {
                root.lastError = `Loader update failed: ${loaderErrBuf.text || "exit " + code}`;
                console.warn("[UserModules]", root.lastError);
            }
        }
    }

    // After a successful loader update, fetch release notes from GitHub and
    // write a notice file so the banner shows for the next 2 launches.
    readonly property string _noticeFile:
        `${Directories.shellConfig}/user_modules_state/.loader_notice.json`
    readonly property string _loaderApiUrl:
        "https://api.github.com/repos/Rom4ik-12/illogical-impulse-plugins/releases/latest"

    // After a successful loader update, fetch release notes from GitHub,
    // pick the section matching the user's locale (### en / ### ru blocks),
    // and write a notice file shown for the next 2 launches.
    Process {
        id: fetchNoticeProc
        command: ["bash", "-c",
            "set -e\n"
            + "tmp=$(mktemp /tmp/qsmod.XXXX.py)\n"
            + "cat > \"$tmp\" << 'PYEOF'\n"
            + "import sys, json, os, re\n"
            + "d = json.load(sys.stdin)\n"
            + "body = d.get('body', '').replace('\\r', '')\n"
            + "lang = os.environ.get('LANG', 'en').split('.')[0].lower()\n"
            + "ls = lang.split('_')[0]\n"
            + "secs = {}\n"
            + "cur = None\n"
            + "for line in body.split('\\n'):\n"
            + "    m = re.match(r'^###\\s+(\\S+)', line)\n"
            + "    if m:\n"
            + "        cur = m.group(1).lower()\n"
            + "        secs[cur] = []\n"
            + "    elif cur is not None:\n"
            + "        secs[cur].append(line)\n"
            + "def g(k):\n"
            + "    ll = list(secs.get(k, []))\n"
            + "    while ll and not ll[-1].strip(): ll.pop()\n"
            + "    return '\\n'.join(ll).strip()\n"
            + "text = g(lang) or g(ls) or g('en') or body.strip()\n"
            + "print(json.dumps({'showCount': 2, 'version': d.get('tag_name', ''), 'body': text}))\n"
            + "PYEOF\n"
            + `curl -sf '${root._loaderApiUrl}' | python3 "$tmp" > '${root._noticeFile}'\n`
            + "rm -f \"$tmp\"\n"
        ]
        onExited: (code) => {
            if (code === 0) noticeFileView.reload();
        }
    }

    // Read notice on startup and expose to UI. Decrement showCount each launch.
    property var loaderNotice: null

    FileView {
        id: noticeFileView
        path: root._noticeFile
        watchChanges: true
        onLoaded: {
            try {
                const n = JSON.parse(noticeFileView.text || "{}");
                if (n && (n.version || n.body)) root.loaderNotice = n;
            } catch(e) {}
        }
        onLoadFailed: {}
    }

    Process {
        id: fetchVersionsProc
        stdout: StdioCollector { id: versionsOutBuf }
        stderr: StdioCollector { id: versionsErrBuf }
        onExited: (code) => {
            root.fetchingLoaderVersions = false;
            if (code === 0) {
                const tags = (versionsOutBuf.text || "").split("\n")
                    .map(s => s.trim()).filter(s => s.length > 0);
                root.availableLoaderVersions = tags;
            } else {
                root.lastError = `Could not fetch loader versions: ${versionsErrBuf.text || "exit " + code}`;
            }
        }
    }

    Process {
        id: rebaselineProc
        command: ["bash", root.patchScript, "rebaseline"]
        onExited: (code) => {
            root.rebaselining = false;
            root.lastError = code === 0 ? "" : `Rebaseline failed (exit ${code})`;
        }
    }

    Process {
        id: mkdirProc
    }

    IpcHandler {
        target: "userModules"
        function refresh(): void { root.refresh() }
        function enable(id: string): void { root.setEnabled(id, true) }
        function disable(id: string): void { root.setEnabled(id, false) }
        function install(path: string): void { root.install(path) }
        function uninstall(id: string): void { root.uninstall(id) }
    }
}
