# User Modules

A small plugin system for this quickshell config. A user module is just a
folder with a JSON manifest and a QML entry point. You can install, enable,
disable, share and remove modules from **Settings → Modules**, no shell
rebuild required.

---

## Where modules live

```
~/.config/illogical-impulse/user_modules/<module-id>/
    module.json     # manifest (required)
    main.qml        # entry point (default name; can be overridden)
    ...             # any extra QML/assets you need
```

A bundled example lives at `~/.config/quickshell/defaults/user_modules/example-hello/`.
Copy it into your user_modules folder to try it.

The list of enabled module IDs is stored in the shell config under
`userModules.enabled` (`~/.config/illogical-impulse/config.json`).

---

## Manifest (`module.json`)

```json
{
  "id": "my-cool-module",
  "name": "My Cool Module",
  "description": "Adds a floating clock that follows the cursor.",
  "version": "1.0.0",
  "author": "your-name",
  "entry": "main.qml"
}
```

| Field        | Required | Notes                                                        |
|--------------|----------|--------------------------------------------------------------|
| `id`         | yes      | Folder name and unique identifier. Letters/digits/`-`/`_`.   |
| `name`       | yes      | Pretty name shown in Settings.                               |
| `description`| no       | One short line.                                              |
| `version`    | no       | Free-form, e.g. `1.0.0`.                                     |
| `author`     | no       | Your handle.                                                 |
| `entry`      | no       | QML file to load. Defaults to `main.qml`.                    |
| `updateUrl`  | no       | Where Settings → Modules can pull a fresh copy from. See "Auto-update" below. |

---

## The entry QML

The entry file is loaded by a QML `Loader` inside the running shell. Keep
the root element a `QtObject` (or `Item`) and put everything you want to
spawn inside it. The shell's services and widgets are available:

```qml
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services           // Audio, Battery, Cliphist, ...
import qs.modules.common     // Config, Appearance, Directories, Translation
import qs.modules.common.widgets

QtObject {
    Component.onCompleted: console.log("[my-module] loaded")
    Component.onDestruction: console.log("[my-module] unloaded")

    // Global shortcut
    property var shortcut: GlobalShortcut {
        name: "myModuleAction"
        description: "Do the thing"
        onPressed: console.log("hi from my module")
    }

    // A panel — this works too
    // property var panel: PanelWindow { ... }
}
```

Things to know:

- The module is **mounted** when you flip its toggle on, and **unmounted**
  when you flip it off. Use `Component.onCompleted` / `onDestruction` for
  setup/teardown.
- Module load is async and isolated. A buggy module logs an error and
  does not break the rest of the shell.
- IDs collide on the folder name. Pick something unique.
- The full power of Qt/QML is available — you can ship your own
  `PanelWindow`s, `IpcHandler`s, `Process`es, timers, anything.

---

## Installing & sharing

The shareable format is **`.qsmod`** — literally a zip of the module folder.
A bare folder works too.

In **Settings → Modules** you can:

- **Install** — paste a path to a `.qsmod` file or a module folder, click Install.
- **Enable / disable** — toggle per module.
- **Export** — package any installed module to `~/Downloads/<id>.qsmod`.
- **Open folder** — opens the module's folder in your file manager.
- **Uninstall** — removes the module folder and disables it.

You can also do everything by hand:

```sh
# Install
unzip my-module.qsmod -d ~/.config/illogical-impulse/user_modules/

# Share
cd ~/.config/illogical-impulse/user_modules
zip -r my-module.qsmod my-module/
```

Or via IPC:

```sh
qs ipc call userModules install /path/to/foo.qsmod
qs ipc call userModules enable  my-module
qs ipc call userModules disable my-module
qs ipc call userModules refresh
```

---

## Auto-update from a URL

Set `updateUrl` in your manifest and Settings → Modules will show a small
download icon next to the module. Clicking it pulls a fresh copy and
re-installs in place. **Update all** in the header updates every module
that declares an `updateUrl`.

Three URL shapes are recognised:

```jsonc
// 1. Direct .qsmod / .zip file (recommended for releases)
"updateUrl": "https://github.com/me/my-mod/releases/latest/download/my-mod.qsmod"

// 2. GitHub repo (shallow git clone, .git stripped)
"updateUrl": "https://github.com/me/my-mod"

// 3. Specific branch
"updateUrl": "https://github.com/me/my-mod/tree/develop"
```

If the module is enabled and uses **patches**, the updater first reverts
its patches, replaces the files, then re-enables — so you don't end up
with stale patches against new code.

The same fetcher works for one-off installs: just paste any of the three
URL shapes into the **Install** field.

---

## Quick start: make your own module

```sh
ID=hello-bar
mkdir -p ~/.config/illogical-impulse/user_modules/$ID
cat > ~/.config/illogical-impulse/user_modules/$ID/module.json <<EOF
{ "id": "$ID", "name": "Hello Bar", "version": "0.1.0", "entry": "main.qml" }
EOF
cat > ~/.config/illogical-impulse/user_modules/$ID/main.qml <<'EOF'
import QtQuick
import Quickshell
QtObject {
    Component.onCompleted: console.log("[hello-bar] hi!")
}
EOF
```

Open **Settings → Modules**, click **Refresh**, flip the toggle on. Done.

---

## Adding widgets to the bar

The bar exposes a single extension slot — drop an element into it from any
module without touching bar code. In your `module.json`:

```json
{
  "id": "my-bar-clock",
  "name": "My Bar Clock",
  "version": "1.0.0",
  "barWidgets": [
    { "source": "Clock.qml" }
  ]
}
```

Then create `Clock.qml` next to the manifest. Whatever the file's root
element is, it goes straight into the bar's slot:

```qml
// Clock.qml
import QtQuick
import qs.modules.common
import qs.modules.common.widgets

StyledText {
    text: Qt.formatDateTime(new Date(), "hh:mm")
    color: Appearance.colors.colOnLayer0
    font.pixelSize: Appearance.font.pixelSize.normal
}
```

That's it. Multiple widgets per module are fine — list more entries in
`barWidgets`. Widgets show in the order modules load (alphabetical by ID),
to the left of the system tray. Toggling the module on/off in Settings
adds/removes the widget instantly — no patches involved.

If you'd rather inject the widget into a different spot of the bar,
fall back to the patches mechanism below.

---

## Patching existing files

Sometimes "drop in a panel" isn't enough — you actually need a hook inside an
existing shell file (e.g. add a child to `BarContent`, register a service,
etc.). A module can declare **text patches** that get applied to the live
shell files when the module is enabled, and reverted when it's disabled.

Add a `patches` array to your `module.json`:

```json
{
  "id": "extra-bar-button",
  "name": "Extra Bar Button",
  "version": "1.0.0",
  "patches": [
    {
      "file": "modules/ii/bar/BarContent.qml",
      "find": "// END OF BAR ITEMS",
      "replace": "MyExtraButton {}\n            // END OF BAR ITEMS"
    }
  ]
}
```

How patches behave:

- **Find must be unique.** The string in `find` must appear **exactly once**
  in the target file. Multi-line strings are fine; pick something specific.
- **Backups are made.** The first time a file is patched, the pristine copy
  is saved to `~/.config/illogical-impulse/user_modules_state/originals/`.
- **Disable reverts.** Disabling a module restores the originals and re-applies
  patches from any other still-enabled modules (alphabetical order).
- **Uninstall reverts first.** A patched module is automatically disabled
  before its folder is removed.
- **The shell auto-reloads** because you just changed its files.

### Caveats — read these

- **Don't manually edit a patched file** while a patching module is enabled.
  Your edits will be wiped on the next disable/re-enable cycle.
- **Two modules patching the same hunk will conflict.** The second to enable
  will fail because its `find` no longer matches uniquely. Pick anchors
  carefully or coordinate.
- **Upstream upgrades invalidate the baseline.** If you update the original
  shell, the saved `originals/` are stale. After upgrade:
  1. Disable all patching modules (this restores the *old* originals).
  2. Apply the upstream update.
  3. Click **Rebaseline patches** in Settings → Modules (this drops the
     baseline). Re-enable your modules.
- **A failed patch leaves you in a partial state.** The error appears in the
  Modules page. Fix the `find` string in the manifest and re-enable.
- **Patches are best for additive snippets** (add a line, append to a list,
  inject a child). Heavy refactors are easier as a fork than as a patch.

### Manual control

A CLI helper is available:

```sh
~/.config/quickshell/scripts/user_modules/patch.sh status
~/.config/quickshell/scripts/user_modules/patch.sh enable  my-mod
~/.config/quickshell/scripts/user_modules/patch.sh disable my-mod
~/.config/quickshell/scripts/user_modules/patch.sh reapply-all
~/.config/quickshell/scripts/user_modules/patch.sh rebaseline
```

---

## Tips

- Prefer reading config through `Config.options` rather than your own files.
- For shortcuts, pick unique `name`s so they don't clash with the shell's.
- For panels, use the existing widgets in `qs.modules.common.widgets` so
  your module looks native.
- If your module needs persistent state, store it under
  `${Directories.state}/user/<your-id>/`.
