<div align="center">
    <h1>KOKUKOKU</h1>
    <img src="./kokukoku.webp" width="256" />
    <p>
    <h3>刻刻</h3>
    <div>A native macOS app for tracking time spent on each project.</div>
    </p>
    <p>
        English | <a href="./README.ja.md">日本語</a>
    </p>
    <p>
        <a href="https://github.com/tadashi-aikawa/kokukoku/actions/workflows/ci.yml">
          <img src="https://github.com/tadashi-aikawa/kokukoku/actions/workflows/ci.yml/badge.svg" alt="CI" />
        </a>
        <a href="https://github.com/tadashi-aikawa/kokukoku/blob/main/LICENSE">
          <img src="https://img.shields.io/github/license/tadashi-aikawa/kokukoku" alt="License" />
        </a>
    </p>
</div>

---

- **Timer**: Track time spent on each project individually
- **UI Panel**: Show a panel at the center of the screen where the mouse cursor is, to select projects and view elapsed time
- **Continuous Timer**: Always display continuous work time as `HH:MM:SS`; idle, break, and reset states show `00:00:00`
- **Alert**: Send macOS notifications when continuous work time exceeds configured thresholds
- **Persistence**: Save timer state to JSON so it survives restarts
- **Clipboard Copy**: Copy measurement results as bulleted text to clipboard
- **Keyboard Shortcuts**: Select projects by number keys, navigate with j/k or arrow keys, break with 0, confirm reset with r
- **Inline Time Editing**: Edit accumulated or continuous time directly in the panel
- **Customization**: Configure project icons (emoji, URL, or file path), names, and fonts

## Setup

### Install via Homebrew (Recommended)

```bash
brew install --cask tadashi-aikawa/tap/kokukoku
open -a KOKUKOKU
```

> [!NOTE]
> KOKUKOKU is a self-signed (non-notarized) app. If the first launch is blocked, allow it via
> System Settings → Privacy & Security → "Open Anyway".

To launch it automatically at login, add KOKUKOKU to
System Settings → General → Login Items & Extensions → Open at Login.

To update:

```bash
brew upgrade --cask kokukoku
```

### Install manually

Download `KOKUKOKU-<version>.zip` from [Releases](https://github.com/tadashi-aikawa/kokukoku/releases/latest), unzip it, and move `KOKUKOKU.app` to `/Applications`. Then remove the quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/KOKUKOKU.app
```

(Not needed when installed via Homebrew.)

## Configuration

KOKUKOKU reads `~/.config/kokukoku/config.toml` at launch. Restart the app after editing it.

```toml
[[projects]]
id = "dev"
name = "Development"
icon = "💻"

[[projects]]
id = "meeting"
name = "Meeting"
icon = "🗓"

[breakItem]
name = "Break"
icon = "☕"

[hotkey]
modifiers = ["alt"]
key = "t"
```

### Configuration Options

Complete sample including all options (default values):

```toml
# Project definitions (required)
[[projects]]
id = "work"    # Unique string identifier (required)
name = "Work"  # Display name (required)
icon = "💼"    # Emoji text, image URL (http/https), or file path (/ or ~/) (optional)

# Break button settings (optional; defaults: name="休憩", icon="☕")
[breakItem]
name = "休憩"
icon = "☕"

# Hotkey to toggle the panel (optional; omit to disable)
[hotkey]
modifiers = ["alt"]  # Modifier keys: "command"/"cmd", "option"/"alt", "control"/"ctrl", "shift"
key = "t"            # Key: a character or a key name such as "f18"

# UI settings (optional)
[ui]
fontName = ".AppleSystemUIFont"             # Font for text (default: system font)
monoFontName = "Menlo"                      # Monospace font for time display (default: Menlo)
showVersionByDefault = false                # Show the version in the header by default
copyTextFormat = "- {name}: {hh}:{mm}:{ss}" # Line format for clipboard copy
copyTextSeparator = "\n"                    # Line separator for clipboard copy
closeOnSwitch = true                        # Auto-close panel when switching projects

# Panel keymap settings (optional; each key is individually optional)
[keymap]
startBreak = "0"         # Start break
reset = "r"              # Reset confirmation
toggleVersion = "v"      # Toggle version display
editTime = "e"           # Edit accumulated time
editContinuousTime = "E" # Edit continuous work time
copyToClipboard = "c"    # Copy to clipboard

# Alert settings (optional)
[alert.continuousWork]
thresholds = [1500, 3000, 4500]                  # Alert thresholds in seconds
message = "%d分経過しました。休憩しましょう"     # Message template (%d = minutes)
```

Timer state is saved to `~/.local/state/kokukoku/state.json`.

### Copy Format Placeholders

Placeholders available in `copyTextFormat`:

| Placeholder | Description | Example (for 3665 seconds) |
|-------------|-------------|---------------------------|
| `{name}` | Project name | `Work` |
| `{hh}` | Hours (zero-padded) | `01` |
| `{mm}` | Minutes (zero-padded) | `01` |
| `{ss}` | Seconds (zero-padded) | `05` |
| `{h}` | Hours | `1` |
| `{m}` | Minutes | `1` |
| `{s}` | Seconds | `5` |

### Icon Types

The `icon` field in project definitions supports three formats:

| Format | Example | Description |
|--------|---------|-------------|
| Emoji | `"💼"` | Displayed as text |
| URL | `"https://example.com/icon.png"` | Downloaded and displayed as image |
| File path | `"/path/to/icon.png"` or `"~/icons/work.png"` | Loaded from local file |

## Keyboard Shortcuts

These shortcuts are available while the panel is open:

#### Fixed Keys

| Key | Action |
|-----|--------|
| `1`-`9` | Select the corresponding project |
| `j` / `Down` | Move selection down |
| `k` / `Up` | Move selection up |
| `Enter` | Execute selected action |
| `Escape` | Close panel |

#### Configurable Keys (customizable via `keymap`)

| Key (default) | Config key | Action |
|---------------|-----------|--------|
| `0` | `startBreak` | Break |
| `e` | `editTime` | Edit accumulated time of selected project |
| `E` | `editContinuousTime` | Edit continuous work time, even while idle or on break |
| `c` | `copyToClipboard` | Copy measurement results to clipboard as bulleted text |
| `r` | `reset` | Enter reset confirmation; press again to reset all timers |
| `v` | `toggleVersion` | Toggle version display in the header |

Time editing happens inline on the panel: press `e` or `E`, type a value such as `01:23:45` (or `83:45`, or plain seconds), then press `Enter` to apply or `Escape` to cancel.

Breaking resets the continuous work timer to `00:00:00`. If you edit that value while idle or on break, the edited value is used when you start the next project.

## Development

```bash
swift run Kokukoku               # Run directly
swift run Kokukoku --show-panel  # Run and immediately show the panel
./scripts/make-app.sh            # Build KOKUKOKU.app into .build/
```

## Test

```bash
swift test
```

## License

MIT
