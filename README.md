![FlacNest icon](docs/iconflac.png)

# FlacNest

A native macOS app for playing FLAC albums with CUE sheets, plus a companion **iPhone/iPad** app for listening on the go. FlacNest scans a folder of music, builds a library from your CUE files, and gives you a focused player for gapless album playback—with library management, metadata editing, barcode-based album loading, optional menu bar controls, and export to mobile.

![FlacNest screenshot](docs/screenshot.png)

## Goals

FlacNest is built for listening to **single-file FLAC rips split by CUE sheets**—the kind of library many audiophile collections use, without converting files or splitting tracks on disk. The app aims to:

- Play albums accurately using **CUE track boundaries** (INDEX 01), not arbitrary file splits
- Keep your files **where they are**—scan a folder, play from the original paths
- Offer a **simple, native experience** on Mac and iOS: separate player and library windows (Mac), keyboard shortcuts, media keys, and an optional menu bar controller
- Persist **library metadata and playback state** between launches, including fast player restore on startup

## How It Works

### Library (macOS)

1. Choose a **library home folder** in Settings. FlacNest scans it for `.cue` files and their companion `.flac` files.
2. Album and track info is stored in **`flacnest.xml`** (by default inside the library folder, or in a custom location you choose). User metadata includes artwork paths, **barcodes**, and **favorites**.
3. Open **FlacNest Library** to browse albums, sort/group the list, refresh after adding new music, and edit album metadata or artwork.

**Browsing and selection**

- Use the **filter field** above the album list to search by artist, album title, or track name (updates as you type)
- Single-click to select an album; double-click to play
- **↑ / ↓** and **Page Up / Page Down** move the selection when the album list is focused (respects the current filter)
- The **now playing** album is highlighted and scrolled into view when you open the library
- **Star** an album on the right side of each row; use the toolbar **star** button to show **favorites only** or all albums
- Toggle a read-only **metadata preview** pane (toolbar **info** icon). The preview runs the full height of the window; the docked mini player stays in the album list column only
- **Play Selected** and **Edit Metadata…** sit in a bar below the list, alongside the loaded album count

Use the themed mini player strip at the bottom of the library column when the main player window is closed.

Large libraries load asynchronously—a spinning CD overlay appears while scanning, loading, or preparing the list.

### Player (macOS)

**FlacNest Player** shows album art, an optional spinning CD (with realistic spin-up and spin-down), track and album progress bars (with seek), and transport controls. You can:

- **Attach / detach** the player from the library—detach opens the standalone player; attach closes it and brings the library forward
- Toggle the **library window** from the player toolbar (⌘2)
- Toggle a **track list** for the current album (window size and album art height are remembered separately for compact and expanded layouts)
- Drag the divider below the artwork to resize album art
- See the current track as **TRACK 01**, **TRACK 02**, etc. above the track progress bar
- Use accent-colored **play/pause** (larger than the other transport buttons); previous, stop, next, and eject use the default text color
- Control playback via **keyboard shortcuts**, **media keys**, or the optional **status menu**

### Eject (barcode scan)

Press **Eject** in the player or library transport controls (or **⌘⇧E**) to scan a CD barcode with your Mac’s camera:

1. Hold the barcode in the highlighted scan area
2. If the barcode is **not yet linked**, choose the matching album from a searchable list
3. On later scans, the linked album **loads and plays automatically**

Barcodes are saved in `flacnest.xml`. You can choose which camera to use when multiple are available.

### Playback

- One FLAC file per album; tracks are defined by the CUE sheet
- Auto-advance at track boundaries; previous/next track and seek within the album
- Optional **continuous album play**—when enabled, the next album in the current library sort order starts after the last track finishes
- Optional **save last played album and position**—caches the full album entry so the player can restore immediately on launch without waiting for the library to finish loading
- **Now Playing** info for system media controls when an album is loaded

### Metadata editor

Open **Edit Metadata…** from the library to change album details, artwork references, and track titles. **Import from clipboard** pastes one track title per line and strips trailing durations (for example `Track Name\t3:52`).

### Status menu

Enable **Show status menu** in Settings for a menu bar icon with:

- Now playing info and transport controls
- **Show Player** (⌘P), **Settings**, and **Quit** as icon buttons on the right

### Settings (macOS)

- Library folder and optional custom `flacnest.xml` location
- Theme: **System**, **Light**, **Dark**, **Nest**, or **Dark Nest** (Nest themes use FlacNest cream, green, and brown tones)
- Save last played position, spinning CD, continuous album play, status menu toggle
- **Export Library for iPhone/iPad…** — quick metadata + artwork package (see Mobile below)
- Player window sizes and artwork height are saved per layout (mini vs. track list open)

FlacNest runs as a **single instance**—launching again activates the existing app.

### Mobile (iPhone / iPad)

The **FlacNestMobile** target is a companion app for listening to albums exported from your Mac library.

**Getting music onto your device**

1. On Mac, use **Library → Prepare Export…** to convert each album FLAC to a single MP3 (track boundaries from CUE metadata, same as desktop). Choose bitrate and export folder; conversion can be resumed—albums listed in `process.txt` are skipped.
2. Copy the export folder to your iPhone/iPad (USB, Files, etc.) into the app **Documents** folder, or choose a custom library folder in mobile Settings.
3. Optionally use **Settings → Export Library for iPhone/iPad…** on Mac for a lightweight metadata-only `.flacnestexport` package (artwork + `flacnestmobile.xml`; no audio).

**Using the mobile app**

- Browse albums with sort, group, and **favorites only** (toolbar menu)
- **Filter** by artist, album, or track using the search field above the list
- Open an album for its track list; tap to play
- Player shell with artwork, progress, and transport controls; **Now Playing** integration
- Theme: **Nest**, **Dark Nest**, or **System**
- iPad supports a split layout with library and player side by side

### Themes

Both Mac and iOS support custom **Nest** and **Dark Nest** palettes (warm cream/brown backgrounds with green accents). Mac also offers standard Light, Dark, and System appearances.

## Requirements

### macOS (FlacNest)

- **macOS 14** or later
- FLAC files with accompanying CUE sheets in your library folder
- Camera access (for barcode scanning only)
- **FFmpeg** (bundled via project scripts for Prepare Export, or available on `PATH`)

### iOS (FlacNestMobile)

- **iOS 17** or later
- A prepared export folder from the Mac app (MP3 + `flacnestmobile.xml` + artwork)

## Keyboard Shortcuts (macOS)

### Playback

| Action | Shortcut |
|--------|----------|
| Play / Pause | Space |
| Stop | ⌘. |
| Next track | ⌘→ |
| Previous track | ⌘← |
| Eject — scan barcode | ⌘⇧E |

### Windows

| Action | Shortcut |
|--------|----------|
| FlacNest Player | ⌘1 |
| FlacNest Library (toggle) | ⌘2 |

### Library

| Action | Shortcut |
|--------|----------|
| Play selected album | Return |
| Edit metadata | ⌘E |
| Refresh library | ⌘R |
| Prepare export | Library menu |
| Cancel scan | Esc |
| Move selection up / down | ↑ / ↓ |
| Move selection by page | Page Up / Page Down |

### Status menu

| Action | Shortcut |
|--------|----------|
| Show Player | ⌘P |

## Project Structure

```
FlacNest/
├── FlacNest/              # macOS app (SwiftUI views, playback, library scanner, export)
├── FlacNestMobile/        # iOS app (library browser, player, settings)
├── Shared/                # Shared models, themes, mobile library loader
│   ├── Models/
│   ├── Services/
│   ├── Theme/
│   └── UI/
├── Scripts/               # FFmpeg fetch/bundle helpers
└── FlacNest.xcodeproj/    # FlacNest + FlacNestMobile targets
```

Open `FlacNest.xcodeproj` in Xcode. Select the **FlacNest** or **FlacNestMobile** scheme to build for Mac or iOS.

## Attributions

- Portions of this project were written and refined with [Cursor](https://cursor.sh), an AI-powered code editor.
- UI imagery includes assets from [Vecteezy.com](https://www.vecteezy.com) and [PNG ARTS](https://www.pngarts.com/)
