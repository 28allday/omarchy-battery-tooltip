# omarchy-battery-tooltip

Replace Omarchy's minimal waybar battery tooltip with a richer one:

```
󰁿 Battery 69% · 03h:49m left · ↓10.3W/57Wh
```

…wrapped in an accent-coloured border that follows the active Omarchy theme.

The default tooltip on a stock Omarchy install shows just `5W↓ 69%`. This installer adds time remaining, power direction, formatted power draw, and your battery's capacity in Wh — auto-detected from `/sys/class/power_supply/`.

## Requirements

- [Omarchy](https://omarchy.org) (waybar set up at `~/.config/waybar/`)
- A laptop. The script auto-detects via `hostnamectl` / SMBIOS chassis type and exits cleanly on desktops, VMs, and servers (use `--force` to install anyway).
- `bash`, `awk`, `find`, `python3` — all in Omarchy's base install.

## Install

One-liner:

```bash
curl -fsSL https://git.no-signal.uk/nosignal/omarchy-battery-tooltip/raw/branch/main/install-battery-tooltip.sh | bash
```

GitHub mirror:

```bash
curl -fsSL https://raw.githubusercontent.com/28allday/omarchy-battery-tooltip/main/install-battery-tooltip.sh | bash
```

Or clone and run:

```bash
git clone https://git.no-signal.uk/nosignal/omarchy-battery-tooltip.git
cd omarchy-battery-tooltip
./install-battery-tooltip.sh
```

Hover the battery icon in waybar to see the new tooltip.

## Options

| Flag         | Effect                                                                                       |
| ------------ | -------------------------------------------------------------------------------------------- |
| *(none)*     | Use the battery's **design capacity** (rated spec, never changes).                           |
| `--current`  | Use the **current full-charge capacity** instead — reflects degradation. Re-run to refresh. |
| `--force`    | Install even if the script doesn't think this is a laptop.                                   |
| `--help`     | Print the script's header.                                                                   |

## Safe to re-run

The script is idempotent:

- `config.jsonc` — finds the existing `"battery"` block and replaces the tooltip keys in place (or inserts them if missing). Stock or already-patched configs both work.
- `style.css` — uses a `/* >>> battery-tooltip */` marker block, so re-runs replace what's between the markers rather than accumulating.

A timestamped backup of each file is written next to it on every run:

```
~/.config/waybar/config.jsonc.bak.<unix-ts>
~/.config/waybar/style.css.bak.<unix-ts>
```

## Theme follows automatically

- Border colour pulls `@selected-text` from the active theme's `walker.css`. Switching themes with `omarchy-theme-set` updates the border on the next waybar reload.
- Font follows because the tooltip wraps dynamic fields in `<span face='monospace'>`, which picks up whatever font `omarchy-font-set` configured.

## Uninstall / revert

Restore the most recent backups:

```bash
cd ~/.config/waybar
ls -t config.jsonc.bak.* | head -1 | xargs -I{} cp {} config.jsonc
ls -t style.css.bak.*    | head -1 | xargs -I{} cp {} style.css
omarchy-restart-waybar
```

## Design notes

See [`install-battery-tooltip.NOTES.md`](./install-battery-tooltip.NOTES.md) for the why-it-works-this-way: laptop detection layering, idempotency strategy, capacity-mode trade-off, the GTK-tooltip monospace-wrapper workaround, and known edge cases.

## Tested on

Acer Nitro laptop with Realtek BAT1 (Li-ion, ~57Wh design, charge-based sysfs), fresh stock Omarchy configs and already-patched configs, plus simulated desktop / unknown-flag / missing-battery paths.

## License

MIT.
