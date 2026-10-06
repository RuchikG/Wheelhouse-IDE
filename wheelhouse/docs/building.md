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

The build also sets a few preferences (`wheelhouse/defaults.sh`) that hide cmux's own account
control, its Pro upgrade prompts, the phone pairing button and the red dev-build label. They are
ordinary cmux switches, so they can be turned back on from the app's debug menu.
