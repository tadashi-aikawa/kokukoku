<div align="center">
    <h1>KOKUKOKU</h1>
    <img src="./kokukoku.webp" width="256" />
    <p>
    <h3>刻刻</h3>
    <div>A Hammerspoon Spoon for tracking time spent on each project.</div>
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
- **Customization**: Configure project icons (emoji, URL, or file path), names, and fonts

## Setup

### Prerequisites

If you do not have Hammerspoon yet:

```bash
brew install --cask hammerspoon
open -a Hammerspoon
```

Then install SpoonInstall:

```bash
mkdir -p ~/.hammerspoon/Spoons
curl -L https://github.com/Hammerspoon/Spoons/raw/master/Spoons/SpoonInstall.spoon.zip -o /tmp/SpoonInstall.spoon.zip
unzip -o /tmp/SpoonInstall.spoon.zip -d ~/.hammerspoon/Spoons
```

### Install via SpoonInstall (Recommended)

Add this to `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("SpoonInstall")

spoon.SpoonInstall.repos.kokukoku = {
  url = "https://github.com/tadashi-aikawa/kokukoku",
  desc = "KOKUKOKU Spoon repository",
  branch = "spoons",
}

spoon.SpoonInstall:andUse("Kokukoku", {
  repo = "kokukoku",
  fn = function(s)
    s:setup({
      projects = {
        { id = "work", name = "Work", icon = "💼" },
        { id = "meeting", name = "Meeting", icon = "🗓" },
        { id = "break", name = "Break", icon = "☕", isBreak = true },
      },
      hotkey = { modifiers = { "alt" }, key = "t" },
    })
  end,
})
```

> [!TIP]
> To install a specific version, change the `branch` value to `spoons-v{VERSION}` (e.g., `"spoons-v0.3.0"`).
> The Spoon is downloaded only on the first install; subsequent launches load it locally without network access.

To update an already installed Spoon (run once in Hammerspoon Console):

```lua
spoon.SpoonInstall:updateRepo("kokukoku")
spoon.SpoonInstall:installSpoonFromRepo("Kokukoku", "kokukoku")
hs.reload()
```

> [!WARNING]
> Do not put these three lines in `~/.hammerspoon/init.lua`. `hs.reload()` will rerun the same update block on each reload and cause a loop. Keep only persistent setup in `init.lua`, and run this block manually only when updating.

### Install from source (for development)

```bash
git clone https://github.com/tadashi-aikawa/kokukoku /path/to/kokukoku
ln -sfn /path/to/kokukoku/Kokukoku.spoon ~/.hammerspoon/Spoons/Kokukoku.spoon
```

Add this to `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("Kokukoku")

spoon.Kokukoku:setup({
  projects = {
    { id = "work", name = "Work", icon = "💼" },
    { id = "meeting", name = "Meeting", icon = "🗓" },
    { id = "break", name = "Break", icon = "☕", isBreak = true },
  },
  hotkey = { modifiers = { "alt" }, key = "t" },
})
```

To update:

```bash
git -C /path/to/kokukoku pull
```

## Configuration Example

```lua
hs.loadSpoon("Kokukoku")

spoon.Kokukoku:setup({
  projects = {
    { id = "dev", name = "Development", icon = "💻" },
    { id = "review", name = "Code Review", icon = "👀" },
    { id = "meeting", name = "Meeting", icon = "🗓" },
    { id = "docs", name = "Documentation", icon = "📝" },
    { id = "break", name = "Break", icon = "☕", isBreak = true },
  },
  hotkey = {
    modifiers = { "alt" },
    key = "t",
  },
  ui = {
    fontName = "HackGen Console NF",
    monoFontName = "HackGen Console NF",
    showVersionByDefault = false,
    copyTextFormat = "- {name}: {hh}:{mm}",
    copyTextSeparator = "\n",
    closeOnSwitch = true,
  },
  keymap = {
    startBreak = "0",
    reset = "r",
    toggleVersion = "v",
    editTime = "e",
    editContinuousTime = "E",
    copyToClipboard = "c",
  },
  alert = {
    continuousWork = {
      thresholds = { 1500, 3000, 4500 },
      message = "%d minutes have passed. Take a break!",
    },
  },
  persistence = {
    path = os.getenv("HOME") .. "/.kokukoku/state.json",
  },
  tickInterval = 1,
})
```

## Configuration Options

Complete sample including all options (default values):

```lua
{
  -- Project definitions (required)
  projects = {
    {
      id = "work",       -- Unique string identifier (required)
      name = "Work",     -- Display name (required)
      icon = "💼",       -- Emoji text, image URL (http/https), or file path (/ or ~/) (optional)
      isBreak = false,   -- true to mark as break project (optional)
    },
  },

  -- Hotkey to toggle the panel (optional; omit to disable)
  hotkey = {
    modifiers = { "alt" }, -- Modifier keys
    key = "t",             -- Key
  },

  -- UI settings (optional)
  ui = {
    fontName = ".AppleSystemUIFont",              -- Font for text (default: system font)
    monoFontName = "Menlo",                       -- Monospace font for time display (default: Menlo)
    showVersionByDefault = false,                 -- Show the version in the header by default
    copyTextFormat = "- {name}: {hh}:{mm}:{ss}",  -- Line format for clipboard copy (default: "- {name}: {hh}:{mm}:{ss}")
    copyTextSeparator = "\n",                     -- Line separator for clipboard copy (default: "\n")
    closeOnSwitch = true,                         -- Auto-close panel when switching projects (default: true)
  },

  -- Panel keymap settings (optional; each key is individually optional)
  keymap = {
    startBreak = "0",       -- Start break (default: "0")
    reset = "r",            -- Reset confirmation (default: "r")
    toggleVersion = "v",    -- Toggle version display (default: "v")
    editTime = "e",         -- Edit accumulated time (default: "e")
    editContinuousTime = "E", -- Edit continuous work time (default: "E")
    copyToClipboard = "c",  -- Copy to clipboard (default: "c")
  },

  -- Alert settings (optional)
  alert = {
    continuousWork = {
      thresholds = {},                              -- Alert thresholds in seconds (e.g. { 1500, 3000 })
      message = "%d分経過しました。休憩しましょう", -- Message template (%d = minutes)
    },
  },

  -- Persistence settings (optional)
  persistence = {
    path = "~/.kokukoku/state.json", -- File path for saving timer state
  },

  -- Timer tick interval in seconds (default: 1)
  tickInterval = 1,
}
```

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

Breaking resets the continuous work timer to `00:00:00`. If you edit that value while idle or on break, the edited value is used when you start the next project.

## Development

If you install from source with symlink, editing files under `Kokukoku.spoon/` and running `Reload Config` in Hammerspoon reflects changes immediately.

## Test

Run unit tests with `busted`.

```bash
busted
```

If you want to run specific tests:

```bash
busted spec/timer_engine_spec.lua
busted spec/persistence_spec.lua
```

## License

MIT
