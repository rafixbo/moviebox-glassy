# MovieBox Glassy

A smooth, glassy, compact movie & TV streaming app for **Android and Windows**,
built in pure Flutter.

> **Note:** `apkUrl` / `windowsUrl` in `version.json` currently point at the
> GitHub Releases page (placeholder). Once the first real release is published,
> point them at the actual release asset URLs
> (e.g. `.../releases/download/v1.0.0/moviebox-glassy.apk`).

## Features

- **Home** — hero banner carousel + trending poster grid from the MovieBox API
- **Search** — debounced search, Movies / TV Shows / All filters, pagination,
  recent searches + trending shortcuts
- **Details** — rating, year, duration, genres, cast, seasons & episodes for
  series, language/dub picker
- **Player** — in-app playback (media_kit), quality switch mid-playback,
  speed 0.5x–2x, subtitles picker, sleep timer (15/30/60 min), double-tap
  ±10s seek, vertical swipe for brightness (left) / volume (right)
- **Continue Watching** — position saved per title/episode, resume prompt,
  progress bars on posters
- **Downloads** — download any source with progress + pause/resume (HTTP
  Range), play offline, delete — in Library → Downloads
- **Library** — Favorites, Continue Watching, Downloads, History (all local,
  no account)
- **In-app updates** — checks `version.json` on GitHub on startup and from
  About → Check for updates. Optional update dialog, or a forced full-screen
  update screen when below `minBuild`. Fails open offline.
- **Glassy design** — dark glass theme, frosted cards, smooth transitions,
  hero poster animations, skeleton loading, 60fps-feeling lists

No login screen, no ads, no account.

## API source

Streaming data comes from the **MovieBox API**, exactly as implemented by
[mesamirh/MovieBox-Tui](https://github.com/mesamirh/MovieBox-Tui)
(Rust TUI, MIT/Apache) — visitor login, signed requests (HMAC-MD5), search,
home feed (`tabId=2`), details, seasons, resources, play-info and captions.
See `flutter-app/lib/api/moviebox_api.dart`.

**This app hosts no media.** It is a third-party client for personal use only.
Some resource links are resolver links (e.g. `ugc-video.com`) and may not play
inside the app — the player offers an "Open externally" fallback for those.

## Build

```bash
cd flutter-app
flutter pub get
flutter analyze
flutter test
flutter build apk --release        # Android
flutter build windows --release    # Windows (on a Windows machine)
```

GitHub Actions (`.github/workflows/build.yml`) builds both on every push to
`main` and uploads the APK + Windows zip as artifacts.

## Update gate

`version.json` at the repo root:

```json
{
  "latestVersion": "1.0.0",
  "latestBuild": 1,
  "minBuild": 1,
  "apkUrl": "<release apk url>",
  "windowsUrl": "<release zip url>",
  "notes": "..."
}
```

Bump `latestBuild` (and `minBuild` to force) when a new release ships.
The app compares its installed build number and fails open if the file is
unreachable or malformed.
