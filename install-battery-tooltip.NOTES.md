# install-battery-tooltip.sh — design notes

Notes to travel with the script when copying it to another machine for
the omarchy PR.

## What it does

Enriches Omarchy's stock waybar battery tooltip from a minimal
`5W↓ 69%` into a full readout:

    󰁿 Battery 69% · 03h:49m left · ↓10.3W/57Wh

Wrapped in an accent-colored border that matches the active theme.

Two files are patched:

| File                              | What changes                                        |
| --------------------------------- | --------------------------------------------------- |
| `~/.config/waybar/config.jsonc`   | 5 keys in the `"battery"` block                     |
| `~/.config/waybar/style.css`      | `@import` of walker.css + tooltip rules (markered)  |

## Design decisions

1. **Laptop detection (layered, skip cleanly on desktops):**
   - `hostnamectl chassis` (primary — systemd's DMI + heuristics)
   - `/sys/class/dmi/id/chassis_type` (SMBIOS fallback)
   - Battery presence (last resort)
   - `--force` to override

2. **Idempotent by construction:**
   - `config.jsonc`: Python regex + brace-depth parser finds the
     `"battery"` block, replaces known keys in-place, inserts missing
     ones. Safe on stock omarchy AND on already-patched systems.
   - `style.css`: `/* >>> battery-tooltip */` marker block — any re-run
     replaces between markers instead of accumulating. The walker.css
     `@import` is only added if not already present.

3. **Capacity modes:**
   - Default `design` — rated spec from `energy_full_design`
     (or `charge_full_design × voltage_min_design` if only mAh files exist).
     Never changes, never needs refreshing.
   - `--current` — uses `energy_full` / `charge_full`, reflects battery
     degradation. Drifts over time; user re-runs when they want a
     refreshed number.

4. **Theme following:**
   - Border color uses `@selected-text` from the theme's walker.css.
     `omarchy-theme-set` swaps the `~/.config/omarchy/current/theme`
     symlink → border updates automatically on next waybar reload.
   - Font follows because `omarchy-font-set` rewrites both waybar's
     `style.css` font-family AND fontconfig's `monospace` alias, which
     our `<span face='monospace'>` wrapper picks up.

5. **Zero-padded time (`03h:49m` not ` 3h 49m`):**
   - `format-time: "{H:02}h:{M:02}m"` keeps the tooltip a constant width
     with no leading-space that would compound with template spacing.

6. **Monospace wrapper forces stable width:**
   - `<span face='monospace'>...</span>` around the dynamic fields so
     digit-count transitions (5W → 10W, etc.) don't rewidth the tooltip.
     `<tt>` was unreliable in GTK tooltips; `face='monospace'` is honored
     consistently.

## Output matrix

| Scenario                       | Result                    | Exit |
| ------------------------------ | ------------------------- | ---- |
| Laptop                         | Installs                  | 0    |
| Desktop / VM / server          | Skips with info message   | 0    |
| Desktop with `--force`         | Installs anyway           | 0    |
| `--current`                    | Uses degraded capacity    | 0    |
| `--help`                       | Prints header comment     | 0    |
| Missing waybar / no python3    | Errors with hint          | 1    |
| Laptop but unreadable sysfs    | Errors with path          | 1    |
| Laptop but no `"battery"` block| Errors with hint          | 1    |

## Dependencies

- `bash`, `awk`, `find`, `python3` — all in omarchy's base install.
- `omarchy-restart-waybar` — optional; if present, waybar is restarted
  automatically. If absent, the installer just reports completion.

## Tested on

- Acer laptop, BAT1 (charge-based sysfs, Li-ion, ~57Wh design, 18 cycles).
- Fresh stock omarchy configs (both config.jsonc and style.css).
- Re-runs (3× identical checksums → idempotent).
- Simulated desktop via `hostnamectl` override.
- Unknown-flag and missing-battery paths.

## PR suggestions for the omarchy distro

- If adding to the install flow, call the installer non-interactively.
  It handles "not a laptop" internally as a zero-exit skip, so no guards
  needed at the caller.
- If omarchy adds a global install-time hook mechanism, this could live
  there. Otherwise place it in the laptop-specific install path.
- Backup files (`*.bak.<timestamp>`) accumulate on each re-run.
  Consider adding the installer to a path where backups are either
  swept, or add a `--no-backup` flag if the install flow doesn't want
  them.

## Caveats / known edge cases

- Capacity padding `{capacity:>3}` means `Battery  5%` at single-digit
  %, `Battery100%` at 100%. Width stays constant; visible gap varies.
  Zero-padding (`005%`) was rejected as uglier.
- Similarly `↓{power:>4.1f}` shows `↓ 5.2W` vs `↓10.3W`.
- Full/plugged tooltips don't have `{time}` available so they use a
  simpler format without the monospace span.
- `{icon}` is NOT supported in `tooltip-format-*` for the battery
  module (waybar errors "argument not found"). We use static state
  glyphs instead — still theme-consistent since all omarchy-managed
  fonts are Nerd Fonts.

## File layout after install

```
~/.config/waybar/
├── config.jsonc              # battery block patched
├── config.jsonc.bak.<ts>     # timestamped backup per run
├── style.css                 # walker.css import + marker block
└── style.css.bak.<ts>        # timestamped backup per run
```
