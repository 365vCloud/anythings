# Anythings

Anythings is a native macOS file search app inspired by voidtools Everything. It builds a local filename/path index for folders you choose and filters results instantly as you type.

## Features

- Native SwiftUI macOS app.
- User-selected folder indexing.
- Fast in-memory search over file names and paths.
- Everything-style wildcard matching with `*` and `?`.
- Quoted phrase support, for example `"project report"`.
- Optional full-path matching.
- Finder integration: open item, reveal in Finder, copy path.
- Re-index command for refreshing results.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools
- Swift 5.9 or later

## Run from source

```bash
swift run Anythings
```

## Build a `.dmg`

Run this on macOS:

```bash
bash scripts/package-dmg.sh
```

The generated installer image will be written to:

```text
dist/Anythings.dmg
```

The script creates a release build, wraps it in `Anythings.app`, and packages it with `hdiutil`.

You can also run the "Build macOS DMG" GitHub Actions workflow to produce the same DMG as a downloadable artifact on a macOS runner.

## Notes

The app indexes folders that you explicitly add. Unlike Everything on Windows, macOS does not expose an NTFS USN journal, so Anythings uses native macOS file APIs to enumerate selected directories and keep searches local.
