# NotchTube

A minimal YouTube video player for the MacBook notch area. The floating window sits at the top center of your screen — right where the notch is — and stays on top of all other windows.

## Features

- **Notch-area positioning** — The player window anchors itself to the top center of the screen, hugging the MacBook notch like a Dynamic Island.
- **Always on top** — Stays visible even when you switch apps or workspaces.
- **Resizable** — Use the `−` / `+` buttons to scale the player between 200px and 600px wide (16:9 aspect ratio).
- **Lightweight** — Single Swift file, no dependencies, no Xcode project required.
- **Keyboard shortcuts** — Cmd+V paste works in the URL field, along with all standard editing shortcuts.
- **Status bar menu** — Show/Hide the player or quit from the `▶ Notch` menu bar icon.
- **No Dock icon** — Runs as an accessory app, staying out of your way.

## How It Works

NotchTube spins up a tiny localhost HTTP server and loads a YouTube embed iframe from it. This gives the iframe a proper `http://` origin, which YouTube requires for embed playback — solving the common WKWebView embed errors (150/152/153).

## Requirements

- macOS 13+ (Ventura or later)
- Swift toolchain (Xcode Command Line Tools)

## Build & Run

```bash
chmod +x build.sh
./build.sh
open build/NotchPlayer.app
```

## Usage

1. Launch the app — a small black window appears at the top of your screen.
2. Paste a YouTube URL into the text field and press Enter.
3. The video starts playing.
4. Use `−` / `+` to resize, `✕` to hide, and the `▶ Notch` menu bar icon to show/hide or quit.

Supported URL formats:
- `https://www.youtube.com/watch?v=...`
- `https://youtu.be/...`
- `https://www.youtube.com/shorts/...`
- `https://www.youtube.com/live/...`
- `https://www.youtube.com/embed/...`
- Raw 11-character video IDs

## License

MIT
