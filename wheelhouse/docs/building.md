# Building from source

Requirements: macOS 14 or later, Xcode 26 or later with the Metal toolchain component, Zig and
Rust. Rebuilding the web bundle also needs [bun](https://bun.sh).

```sh
git clone https://github.com/RuchikG/Wheelhouse-IDE.git
cd Wheelhouse-IDE
./scripts/setup.sh
wheelhouse/build.sh     # first build: around 25 minutes
wheelhouse/open.sh
```

`wheelhouse/build.sh` produces `Wheelhouse IDE.app`. It is a tagged dev build of cmux with its own
bundle id, settings and socket, so it runs next to an installed cmux without touching it. Drive it
from a terminal with `wheelhouse/cli`, which is the `cmux` command pointed at this app:

```sh
wheelhouse/cli open path/to/file.go
```

The build stays off the cmux cloud backend. Sign-in, cloud machines and mobile pairing are upstream
features that need Manaflow's services and are not part of what this fork is for.

`WHEELHOUSE_TAG` (default `wheelhouse`) names the build; a different tag is a separate app with
separate settings.

The app starts with a few preferences of its own (`Sources/WheelhouseDefaults.swift`): cmux's
account control, its Pro upgrade prompts, the phone pairing button and the red dev-build label
are hidden, and telemetry is off. They are ordinary cmux switches, so they can be turned back on
from Settings or the app's debug menu.

## A build for other people

`wheelhouse/build.sh` makes a developer build that only runs on the Mac that built it.
`wheelhouse/release.sh <version>` makes one that runs anywhere:

```sh
wheelhouse/release.sh 0.1.0
# wheelhouse/dist/Wheelhouse-IDE-0.1.0-macos-universal.zip and its .sha256
```

It is a Release build with its own bundle id (`com.cmuxterm.app.staging.wheelhouse`), so it has
its own settings, runs next to an installed cmux, and never updates itself from cmux's release
feed. The board command `proj` is inside it. It is signed for local use only, without an Apple
Developer ID, so a downloaded copy has to be approved once: open it, then choose "Open Anyway"
under System Settings → Privacy & Security.
