# Terminal Color Scheme Issue - Debug Notes

## Problem
Terminal displays light theme instead of dark, even when Dark mode is selected in settings.

## Root Cause
The user's Ghostty config file at `~/Library/Application Support/com.mitchellh.ghostty/config` contains:
```
theme = Apple System Colors Light
```

This config file setting **overrides** all programmatic attempts to set the color scheme via `ghostty_app_set_color_scheme()`.

## Attempts Made

### Attempt 1: Pass `initialColorScheme` to `GhosttyRuntime.init()`
**File:** `supacode/App/supacodeApp.swift`

Passed `initialSettings.appearanceMode.colorScheme` to `GhosttyRuntime(initialColorScheme:)` which calls `ghostty_app_set_color_scheme()` immediately after `ghostty_app_new()`.

**Result:** Failed - config file theme overrides programmatic setting.

### Attempt 2: Add `--theme` CLI argument
**File:** `supacode/App/supacodeApp.swift`

Added `--theme=Apple System Colors Dark` to the Ghostty CLI arguments.

**Result:** Failed - config file still takes precedence.

### Attempt 3: Add `--config-default-files=false`
**File:** `supacode/App/supacodeApp.swift`

Added `--config-default-files=false` to skip loading default config files.

**Result:** Failed - default files are loaded BEFORE CLI args are processed in `GhosttyRuntime.loadConfig()`.

### Attempt 4: Reorder config loading
**File:** `supacode/Infrastructure/Ghostty/GhosttyRuntime.swift`

Changed order to: `load_cli_args` → `load_default_files` → `load_recursive_files`

**Result:** Failed - config file still loaded.

### Attempt 5: Use custom config file
**File:** `supacode/App/supacodeApp.swift`

Created minimal config at `/tmp/supacode-ghostty-config` with:
```
# Minimal Ghostty config for Supacode
# Theme is set via command-line arguments
```

Then used `--config-file=/tmp/supacode-ghostty-config` and `--config-default-files=false`.

**Result:** Still showing light theme.

## Debug Logs Show
```
[Supacode] Ghostty: using minimal config, theme=Apple System Colors
[GhosttyRuntime] Applying initial color scheme: dark
[GhosttyRuntime] setColorScheme: GHOSTTY_COLOR_SCHEME_DARK (ghostty_color_scheme_e(rawValue: 1))
```

Both the CLI theme AND the programmatic `setColorScheme` are being called with the correct dark value, but the terminal still displays light.

## Theme Names Discovered
- **Dark:** `Apple System Colors` (has `background = #1e1e1e`)
- **Light:** `Apple System Colors Light` (has `background = #feffff`)
- **Note:** There is NO `Apple System Colors Dark` theme

## Hypothesis
The Ghostty config system may have multiple layers of precedence that we're not fully understanding:
1. Config file (`theme = ...`)
2. CLI args (`--theme=...`)
3. Runtime calls (`ghostty_app_set_color_scheme()`)

Even with all three set to dark, the terminal still shows light.

## Possible Solutions Not Yet Tried

1. **Directly modify the user's config file** - Read the user's config, remove/comment the `theme` line, write it back

2. **Use a completely different approach** - Instead of fighting the config system, create a custom theme that respects the color scheme

3. **Check if there's a config override environment variable** - Something like `GHOSTTY_CONFIG_DIR`

4. **Investigate the actual surface creation** - The color scheme might be getting reset when surfaces are created

5. **Check if the issue is in the surface registration** - `registerSurface()` applies `lastColorScheme` but maybe surfaces are created before this

## Files Modified
- `supacode/App/supacodeApp.swift` - CLI arguments, config file creation
- `supacode/Infrastructure/Ghostty/GhosttyRuntime.swift` - Debug logging, config loading order
