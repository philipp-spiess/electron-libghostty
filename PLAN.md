# Libghostty Integration Plan

## 1. Repository Preparation
- [ ] Record `third_party/libghostty` as a Git submodule (already added); document update flow in CONTRIBUTING (e.g., `git submodule update --remote --merge`).
- [ ] Capture upstream references in docs: `include/ghostty.h`, `README.md`, `src/apprt/embedded.zig`, `macos/Sources/*`. Note key Zig version requirement (`>= 0.14.0`).
- [ ] Pin host prerequisites: Zig toolchain, Xcode CLTs, Metal headers, CMake/Ninja if needed. Confirm CI hosts.
- [ ] Add onboarding note: run `zig fetch --global-cache-dir` (once Zig installed) to warm dependencies.

## 2. Understand Native Mac Embedding
- [ ] Work through `macos/Sources/App/macOS/AppDelegate.swift`, `Ghostty.Surface.swift`, and related GhosttyKit code to map the lifecycle of `Ghostty.App` and `ghostty_surface_t` objects.
- [ ] Trace how callbacks (`ghostty_runtime_config_s`) are set up in Swift, documenting wakeup/action/clipboard flows and threading assumptions.
- [ ] Identify key Cocoa integrations (menu sync, window focus, CAMetalLayer usage) to inform our ObjC++ bridge design.
- [ ] Summarize data flow between Swift wrappers and low-level C API for later reference in Electron implementation notes.

## 3. Build System Integration
- [ ] Author `docs/libghostty.md` describing the build artifacts, config flags, and runtime environment variables required.
- [ ] Create `scripts/build-libghostty.sh` to:
  - Invoke `zig build -Dapp-runtime=none` for both `aarch64-macos` and `x86_64-macos`.
  - Produce universal static (`libghostty.a`) and, if viable, shared (`libghostty.dylib`) libraries via `lipo`.
  - Copy headers to `build/include` and libraries to `build/lib/macos`.
  - Fail fast when Zig missing, and respect incremental rebuilds.
- [ ] Add `npm run build:libghostty` in `package.json` delegating to the script.
- [ ] Wire `binding.gyp` to link against `build/lib/macos/libghostty.a` (static) and embed the dynamic lib for runtime fallback.
- [ ] Update CI to run the build script on macOS and artifact-check (presence, architecture slices, `otool -L`).

## 4. Objective-C++ Host Layer
- [ ] Replace `src/overlay_view.mm` with a new `GhosttySurfaceView` that hosts the CAMetalLayer used by libghostty.
- [ ] Implement a `GhosttyAppController` ObjC++ singleton:
  - Initialize global state (`ghostty_init`), load default configs, and manage a `ghostty_app_t`.
  - Map `ghostty_runtime_config_s` callbacks to Objective-C blocks/selectors.
  - Maintain an event pump that responds to `wakeup_cb` by scheduling `ghostty_app_tick` on the main thread.
- [ ] Manage per-surface structs holding `ghostty_surface_t`, NSView refs, tracking areas, and render loop handles.
- [ ] Forward size/scale/focus events from the host NSView into `ghostty_surface_set_size`, `ghostty_surface_set_content_scale`, `ghostty_surface_set_focus`, etc.
- [ ] Bridge clipboard interactions and window-title updates back into Electron (via native->JS messaging) when libghostty requests actions.

## 5. Rendering & Input Pipeline
- [ ] Ensure CAMetalLayer setup matches Ghostty expectations (pixel format, presentsWithTransaction, drawable size).
- [ ] Create a display link or CADisplayLink-like loop to call `ghostty_surface_draw` and flush rendered frames.
- [ ] Translate Electron keyboard events into `ghostty_input_key_s` objects (keycode, action, modifiers) before calling `ghostty_surface_key`.
- [ ] Map mouse move/scroll/button events into corresponding libghostty API calls, handling momentum and precise scrolling flags.
- [ ] Pipe IME/preedit events through to `ghostty_surface_preedit` and `ghostty_surface_text` as appropriate.

## 6. Node/Electron Binding Changes
- [ ] Extend `src/native_overlay.cc` to expose new N-API entry points for creating/destroying Ghostty surfaces, injecting input, and retrieving state (title, clipboard, selection).
- [ ] Ensure asynchronous native calls safely marshal data between Node threads and the ObjC++ controller (use `uv_async_t` or napi async work).
- [ ] Update the renderer process code to:
  - Initialize native surfaces when tabs are created.
  - Forward resize/focus/visibility events to native.
  - React to libghostty action callbacks (e.g., title changes) via IPC messages.
- [ ] Remove or gate the old demo overlay functionality in favour of the terminal view.

## 7. Configuration & Runtime Features
- [ ] Expose Ghostty configuration options (command, env vars, font size, theme) through Electron settings and pass through to `ghostty_surface_config_s`.
- [ ] Handle shell command execution results, watching `ghostty_surface_process_exited` and notifying the JS layer for tab cleanup.
- [ ] Implement optional inspector access (developer toggle) based on libghostty inspector APIs.
- [ ] Document required runtime env vars (`GHOSTTY_RESOURCES_DIR`, `GHOSTTY_CONFIG_DIR`) and resource bundle expectations; copy Ghostty `share/ghostty` assets into the app bundle.

## 8. QA & Tooling
- [ ] Add a smoke-test sample under `examples/` that spawns a surface, runs `ls`, and asserts expected output via snapshot or log capture.
- [ ] Integrate automated checks into CI (launch minimal app, send input, verify exit codes) if feasible.
- [ ] Document manual verification steps (rendering quality, clipboard, IME, window resizing, multi-surface) in release checklist.
- [ ] Ensure packaging (`electron-builder` or similar) bundles `libghostty` artifacts and resources for distribution.

## 9. Maintenance Strategy
- [ ] Establish a schedule to pull upstream libghostty changes, rerun build script, and note any Zig API shifts.
- [ ] Track Zig compiler updates and adjust minimum version in documentation/CI.
- [ ] Monitor Ghostty’s macOS app changes for new APIs or action callbacks to mirror in our bridge.

