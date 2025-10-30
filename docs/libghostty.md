# Libghostty Integration

This project embeds the upstream [ghostty](https://github.com/ghostty-org/ghostty) terminal via the vendored `third_party/libghostty` submodule. The notes below capture how we build, link, and host libghostty inside Electron.

## Upstream Reference Points

- **C API**: `third_party/libghostty/include/ghostty.h` defines the public entry points consumed from Objective-C++.
- **Embedded defaults**: `third_party/libghostty/src/apprt/embedded.zig` provides the built-in config, fonts, and resources mapped into the static library.
- **macOS lifecycle**: `third_party/libghostty/macos/Sources/App/macOS/AppDelegate.swift` and `Ghostty.Surface.swift` show how the native app wires `ghostty_runtime_config_s`, surfaces, and render loops on the main thread.
- **Resources**: `third_party/libghostty/share/ghostty` (emitted by `zig build`) must be copied into the Electron bundle so libghostty can locate terminfo, themes, and shell-integration assets.

## Toolchain Requirements

- **Zig** `>= 0.14.0` (enforced by `build.zig`).
- **Xcode Command Line Tools** for `clang`, `lipo`, `dsymutil`, Metal headers, and `xcodebuild` helpers.
- **CMake` + `ninja` (optional)** when rebuilding vendor dependencies in the submodule.
- Run `zig fetch --global-cache-dir ~/.cache/zig` once per machine to warm the global cache, as suggested by upstream.

## Build Workflow

Use `scripts/build-libghostty.sh` (added by this plan) to compile universal macOS libraries:

1. Validates toolchain availability (`zig`, `lipo`).
2. Invokes `zig build -Dapp-runtime=none` for each architecture (`aarch64-macos`, `x86_64-macos`).
3. Produces architecture-specific static archives under `zig-out/lib/`.
4. Combines archives into `native-deps/lib/macos/libghostty.a` via `lipo`.
5. Copies the generated dynamic library (when available) into `native-deps/lib/macos/libghostty.dylib` along with `libghostty.dSYM` slices.
6. Stages headers in `native-deps/include/ghostty.h`.
7. Syncs upstream resources to `native-deps/share/ghostty` for packaging.

Rebuild with:

```bash
bun run build:libghostty
```

To update the submodule and rebuild in one flow:

```bash
git submodule update --remote --merge third_party/libghostty
bun run build:libghostty
```

## Runtime Environment

Set these environment variables before launching Electron so libghostty knows where to load assets and user config:

- `GHOSTTY_RESOURCES_DIR`: absolute path to the bundled `share/ghostty` directory (populated by the build script).
- `GHOSTTY_CONFIG_DIR`: optional override that points to the writable config directory for Ghostty profiles. If unset, libghostty falls back to `$XDG_CONFIG_HOME/ghostty` on macOS.
- `GHOSTTY_CACHE_DIR`: optional override for caches (defaults to standard macOS cache locations).

The Electron preload should inject these values for the renderer process that hosts the terminal surface.

## Callback & Threading Model

- `ghostty_runtime_config_s.wakeup_cb` triggers whenever libghostty has pending work. The host must schedule `ghostty_app_tick` on the main thread (see `Ghostty.App.appTick()` in Swift).
- `action_cb` delivers structured `ghostty_action_s` events (window title, bell, clipboard requests). Forward these through IPC to Electron.
- Clipboard callbacks (`read_clipboard_cb`, `confirm_read_clipboard_cb`, `write_clipboard_cb`) run on the main thread. Coordinate with the Electron main process to service pasteboard operations.
- `close_surface_cb` fires when the surface’s shell process exits. Notify the renderer so tabs can be disposed.
- libghostty assumes all API calls (creation, resize, draw, input) occur on the main queue. ObjC++ helpers should bounce work to `dispatch_get_main_queue()` when invoked off-thread.

## Surface Lifecycle Summary

1. `ghostty_init()` once per process to seed global state.
2. Construct a singleton `GhosttyAppController` that wraps `ghostty_app_new()` and holds onto the `ghostty_app_t`.
3. Create `ghostty_surface_t` instances per Electron tab via `ghostty_surface_new()` using the app config.
4. Attach surfaces to a `CAMetalLayer` hosted inside `GhosttySurfaceView` (an `NSView` subclass) and keep it in sync with window backing scale.
5. Drive rendering by calling `ghostty_surface_draw()` within a display link tick (e.g., `CVDisplayLink` or `CADisplayLink` on the main run loop).
6. Pipe input (`ghostty_surface_key`, `ghostty_surface_mouse_*`, `ghostty_surface_text`, `ghostty_surface_preedit`) from Electron events.
7. Tear down surfaces with `ghostty_surface_free()` when the tab closes.

## Resources & Packaging

- Copy the contents of `third_party/libghostty/share/ghostty` into the Electron app bundle (e.g., `Contents/Resources/ghostty`).
- Include `native-deps/lib/macos/libghostty.a` when linking the native Node module.
- Bundle `libghostty.dylib` and corresponding `.dSYM` (from `native-deps/lib/macos/`) for inspection builds when distributing debug symbols.
- Ensure the packaged app sets `GHOSTTY_RESOURCES_DIR` to the bundled resources at runtime.

## CI Recommendations

- Add a macOS CI job that runs `bun run build:libghostty` and asserts:
  - `file native-deps/lib/macos/libghostty.a` reports `Universal` with `arm64` + `x86_64` slices.
  - `otool -L native-deps/lib/macos/libghostty.dylib` references only system frameworks.
  - `zig version` output is cached to avoid surprises when upstream bumps the minimum.
- Persist `native-deps/share/ghostty` as an artifact for downstream packaging tests.

## Additional Reading

- Upstream macOS host implementation: `third_party/libghostty/macos/Sources/*`
- API documentation in `src/build/main.zig` and `include/ghostty.h`
- Ghostty configuration reference: `third_party/libghostty/src/config/` (mirrors CLI docs)
