# Libghostty QA Checklist

This checklist captures the current manual and automated verification steps for the libghostty integration. Run through it before publishing a release candidate.

## Automated

1. `bun run build:libghostty` – builds universal static/dynamic libraries and stages headers/resources.
2. `bun run build:native` – ensures the Node module links against `libghostty.a`.
3. `bun run build` – compiles the TypeScript bindings.
4. `bun run build:all` – runs the entire pipeline, including the libghostty build.
5. CI on macOS runs:
   - `bun run build:libghostty`
   - `bun run build:native`
   - `otool -L build/lib/macos/libghostty.dylib`
   - `lipo -info build/lib/macos/libghostty.a`

## Manual Smoke Test

1. `bun run build:all` to build JS and native outputs.
2. Run `bunx electron ./dist-examples/electron.js`.
3. In the demo window:
   - Confirm the Ghostty surface renders shell output (`ls` should produce directory listing).
   - Type text; verify glyphs render and echo.
   - Resize the window; surface should scale without redraw artifacts.
   - Toggle window occlusion (hide/show) and confirm redraw resumes.
4. Clipboard:
   - Copy text inside the terminal (`⌘C`).
   - Paste into a native app (Notes/TextEdit) – contents should match.
5. IME/Preedit:
   - Enable a non-Latin IME (e.g., Japanese).
   - Type and confirm preedit underline renders inside the terminal.
6. Title updates:
   - Run `printf '\033]0;hello from ghostty\a'` – window title should update.
7. Shell exit:
   - Run `exit`; verify the renderer receives a `surface-exit` event and closes the surface/tab.

## Packaging Verification

1. Build the production app bundle using `electron-builder` (or project packaging script).
2. Inspect the bundle contents:
  - `Contents/Resources/ghostty/**` should mirror `native-deps/share/ghostty`.
   - `Contents/Frameworks/*.node` should be linked against `libghostty.a`.
   - `Contents/Resources/libghostty.dylib` present for fallback debugging builds.
3. Launch the packaged app on both Apple Silicon and Intel macOS machines and repeat the manual smoke test.

## Upstream Sync

- When bumping the `third_party/libghostty` submodule, rerun this checklist.
- Add any upstream API changes and new callback wiring to this document for future releases.
