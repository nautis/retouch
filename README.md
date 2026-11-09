# Retouch

A small native Mac photo editor that covers a handful of everyday fixes and nothing else: spot healing, magic eraser, rectangle select and crop, resize, rotate, sharpening, the pixelate filters, auto adjustments and export. Swift, AppKit and SwiftUI, Core Image; no dependencies.

**Opens:** JPG, PNG, HEIC, TIFF, and camera raw files through Apple's raw pipeline (any raw format macOS can decode; developed and tested with Canon CR3).
**Exports:** JPG or PNG, full size or scaled, sRGB. The original file is never modified.

Launching the app opens an empty workspace window. Open one or more images with ⌘O (the panel allows multiple selection), by dropping them on the window, or with Open With in Finder; each image opens in its own tab. Closing the last image brings the empty workspace back.

## Download

Grab `Retouch-<version>.zip` from the [latest release](https://github.com/nautis/retouch/releases/latest), unzip it and drag Retouch.app to Applications. It's a universal binary (Apple silicon and Intel) and needs macOS 26 or later. The app is signed with a Developer ID and notarized by Apple.

## Tools

| Tool | Key | What it does |
|------|-----|--------------|
| Rectangle Select | M | Drag to select, drag inside to move it, Shift for a square, Return crops. Ratio presets in the options bar. |
| Spot Healing Brush | J | Paint over a spot or scratch; the area is filled from its surroundings. `[` and `]` change the brush size. |
| Magic Eraser | E | Click a color to make the contiguous area transparent (tolerance, anti-alias, contiguous options). |
| Hand | H | Pan. Space also pans with any tool. Scroll to pan, Option/Command-scroll or pinch to zoom. |

## Menus

- **Image:** Auto Tone (⇧⌘L), Auto Contrast (⌥⇧⌘L), Auto Color (⇧⌘B), Hue/Saturation (⌘U), Image Size (⌥⌘I), Crop to Selection, Image Rotation (180°, 90° either way, Arbitrary).
- **Filter:** Sharpen, Unsharp Mask, Crystallize, Mosaic, Pointillize. Filters apply to the selection when there is one.
- **File:** Open (⌘O), Save (⌘S re-exports to the last export), Export As (⌥⇧⌘W), Close (⌘W).
- **Edit:** Undo (⌘Z), Redo (⇧⌘Z). **Select:** All (⌘A), Deselect (⌘D). **View:** Zoom In/Out (⌘= / ⌘-), Fit on Screen (⌘0), 100% (⌘1).

Shortcuts follow Photoshop's where it has one, so the muscle memory carries over.

Filters with a live preview open in a panel floating over the canvas (macOS dims the window behind a sheet, which makes sharpening hard to judge). You can still zoom and pan while one is open; Esc cancels it and Return applies it even after the canvas has taken the focus. OK can be pressed while a preview is still rendering. Dialog values are remembered between uses.

## Opening a raw file

A raw file opens in a Camera Raw step first: pick a look (Standard, Vivid, Landscape, Flat), toggle lens correction, then Open Image. The look and lens setting are remembered for the next file. Colors come from Apple's raw processing and will not match the camera maker's or Adobe's profiles exactly.

## Building

Requires macOS 26 or later and Xcode 27. The script sets `DEVELOPER_DIR` to `/Applications/Xcode.app`.

```sh
scripts/build-app.sh            # builds build/Retouch.app
scripts/build-app.sh install    # also copies to /Applications and registers it for Open With
scripts/release.sh 1.0.0        # universal build zipped for a release (see the script for notarizing)
```

## Checks

Both take any photo, raw or not; positions scale with the image.

```sh
# Engine checks: raw develop (raw input only), heal, magic eraser, filters, auto adjustments, geometry, export, history
swift run -c release retouch-check <photo> /tmp/retouch-check

# In-app self-test: drives the canvas with synthetic mouse and key events, writes window snapshots and selftest.txt
build/Retouch.app/Contents/MacOS/Retouch --selftest /tmp/retouch-ui <photo>
```

The self-test captures windows with `screencapture`, so the terminal that launches it needs Screen Recording permission.

## Layout

- `Sources/RetouchCore` is the engine (no UI): pixel buffer, raw develop and file I/O, heal (multi-scale PatchMatch), magic eraser, filters, auto adjustments, transforms, undo history.
- `Sources/Retouch` is the app: AppKit shell and canvas, SwiftUI for the tool strip, options bar, status bar, Camera Raw panel and dialogs.
- `Sources/retouch-check` is the engine test executable.

## Known limits

- The healing brush is soft on thin scratches and doesn't continue hard edges across the fill.
- Pointillize leaves white gaps between dots, like Photoshop's default background color.
- No layers, text, brushes, PSD, generative fill, plugins or batch processing. That was the point.

## License

MIT. See `LICENSE`.
