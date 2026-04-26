#!/usr/bin/env bash
# install-battery-tooltip.sh
#
# Extends Omarchy's waybar battery tooltip with a full readout:
# icon, percentage, time remaining, power draw, and auto-detected
# battery capacity in Wh. Also adds an accent-colored border and
# padding to the tooltip box so it matches the active theme.
#
# Idempotent — safe to re-run any time (e.g. to refresh the Wh
# number as the battery degrades).
#
# Usage:
#     ./install-battery-tooltip.sh              # uses design capacity
#     ./install-battery-tooltip.sh --current    # uses current full-charge capacity

set -euo pipefail

CONFIG="${HOME}/.config/waybar/config.jsonc"
STYLE="${HOME}/.config/waybar/style.css"

die() { printf '✗ %s\n' "$*" >&2; exit 1; }

# --- Laptop detection (skip cleanly on desktops/servers) ---
#
# Strategy: try the most reliable source first, fall back through less reliable
# signals. Any positive match → laptop. All negatives / no data → skip.
# Override with --force for testing or unusual hardware.
is_laptop() {
    # 1. systemd's hostnamectl — merges DMI with heuristics, most reliable.
    if command -v hostnamectl >/dev/null 2>&1; then
        case "$(hostnamectl chassis 2>/dev/null)" in
            laptop|portable|convertible|tablet|handset) return 0 ;;
            desktop|server|embedded|vm|container) return 1 ;;
            # empty / unknown → fall through to next method
        esac
    fi
    # 2. Raw SMBIOS chassis_type. Mobile form factors:
    #    8=Portable 9=Laptop 10=Notebook 11=Handheld 14=Sub-Notebook
    #    30=Tablet 31=Convertible 32=Detachable
    if [[ -r /sys/class/dmi/id/chassis_type ]]; then
        case "$(cat /sys/class/dmi/id/chassis_type)" in
            8|9|10|11|14|30|31|32) return 0 ;;
            3|4|5|6|7|15|16|17|23|24|25|28) return 1 ;;
        esac
    fi
    # 3. Last resort: presence of a battery.
    compgen -G '/sys/class/power_supply/BAT*' >/dev/null && return 0
    return 1
}

# --- Argument parsing ---
FORCE=false
MODE=design
for arg in "$@"; do
    case "$arg" in
        --force)            FORCE=true ;;
        --current|current)  MODE=current ;;
        design)             MODE=design ;;
        -h|--help)
            sed -n '2,10p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) die "Unknown argument: $arg  (use: --current, --force)" ;;
    esac
done

if ! $FORCE && ! is_laptop; then
    echo "ℹ  Not a laptop (per hostnamectl/DMI) — skipping battery tooltip install."
    echo "   Use --force to install anyway."
    exit 0
fi

# --- Pre-flight ---
[[ -f "$CONFIG" ]]       || die "No $CONFIG — Omarchy/Waybar not set up?"
[[ -f "$STYLE" ]]        || die "No $STYLE — Omarchy/Waybar not set up?"
command -v python3 >/dev/null || die "python3 required."

# --- Detect battery capacity (Wh) ---
BAT=$(find /sys/class/power_supply -maxdepth 1 -name 'BAT*' -printf '%f\n' 2>/dev/null | sort | head -n1)
[[ -n "$BAT" ]] || die "No battery found under /sys/class/power_supply/."
P="/sys/class/power_supply/$BAT"

read_sysfs() { [[ -r "$1" ]] || die "Can't read $1"; cat "$1"; }

# Design mode (default) = rated spec, never changes.
# Current mode = current full-charge capacity, reflects degradation.
if [[ "$MODE" == "design" ]]; then
    if [[ -r "$P/energy_full_design" ]]; then
        WH=$(awk -v e="$(read_sysfs "$P/energy_full_design")" 'BEGIN { printf "%.0f", e/1000000 }')
    else
        charge=$(read_sysfs "$P/charge_full_design")
        voltage=$(cat "$P/voltage_min_design" 2>/dev/null || read_sysfs "$P/voltage_now")
        WH=$(awk -v c="$charge" -v v="$voltage" 'BEGIN { printf "%.0f", (c*v)/1e12 }')
    fi
else
    if [[ -r "$P/energy_full" ]]; then
        WH=$(awk -v e="$(read_sysfs "$P/energy_full")" 'BEGIN { printf "%.0f", e/1000000 }')
    else
        charge=$(read_sysfs "$P/charge_full")
        voltage=$(cat "$P/voltage_min_design" 2>/dev/null || read_sysfs "$P/voltage_now")
        WH=$(awk -v c="$charge" -v v="$voltage" 'BEGIN { printf "%.0f", (c*v)/1e12 }')
    fi
fi

[[ "$WH" =~ ^[0-9]+$ && "$WH" -gt 0 ]] || die "Couldn't compute a sensible Wh value (got '$WH')."

echo "→ $BAT: ${WH}Wh (${MODE} capacity)"

# --- Patch config.jsonc and style.css ---
TS=$(date +%s)
cp "$CONFIG" "${CONFIG}.bak.${TS}"
cp "$STYLE"  "${STYLE}.bak.${TS}"

python3 - "$CONFIG" "$STYLE" "$WH" << 'PY'
import re, sys
from pathlib import Path

config_path = Path(sys.argv[1])
style_path  = Path(sys.argv[2])
wh          = int(sys.argv[3])

# =========================================================================
# config.jsonc — battery module tooltip keys
# =========================================================================
src = config_path.read_text()
m = re.search(r'"battery"\s*:\s*\{', src)
if not m:
    sys.exit('✗ No battery block in config.jsonc')

start = m.end()
depth, j = 1, start
while j < len(src) and depth > 0:
    if src[j] == '{': depth += 1
    elif src[j] == '}': depth -= 1
    j += 1
end = j - 1

block = src[start:end]
indent_m = re.search(r'\n([ \t]+)"', block)
indent = indent_m.group(1) if indent_m else '    '

desired = [
    ('format-time',
     '"format-time": "{H:02}h:{M:02}m"'),
    ('tooltip-format-discharging',
     f'"tooltip-format-discharging": "<span face=\'monospace\'>󰁿 Battery{{capacity:>3}}% · {{time}} left · ↓{{power:>4.1f}}W/{wh}Wh</span>"'),
    ('tooltip-format-charging',
     f'"tooltip-format-charging": "<span face=\'monospace\'>󰂄 Battery{{capacity:>3}}% · {{time}} to full · ↑{{power:>4.1f}}W/{wh}Wh</span>"'),
    ('tooltip-format-full',
     f'"tooltip-format-full": "󰂅 Battery {{capacity}}% · Full · {wh}Wh"'),
    ('tooltip-format-plugged',
     f'"tooltip-format-plugged": "󰚥 Battery {{capacity}}% · Plugged in · {wh}Wh"'),
]

for key, new_line in desired:
    key_re = re.compile(rf'^([ \t]*)"{re.escape(key)}"\s*:\s*"[^"]*"(,?)\s*$',
                        re.MULTILINE)
    if key_re.search(block):
        block = key_re.sub(lambda m: f'{m.group(1)}{new_line}{m.group(2) or ","}', block, count=1)
    else:
        trailing_m = re.search(r'\s*$', block)
        ip = trailing_m.start() if trailing_m else len(block)
        block = (block[:ip].rstrip() + '\n' + indent + new_line + ',' + block[ip:])

config_path.write_text(src[:start] + block + src[end:])
print(f'  · config.jsonc: patched {len(desired)} battery keys')

# =========================================================================
# style.css — walker.css import + tooltip rules in a marker block
# =========================================================================
style = style_path.read_text()

# 1. Ensure walker.css is imported (for @selected-text)
if 'walker.css' not in style:
    new_style, n = re.subn(
        r'(@import\s+"[^"]*/waybar\.css";)(\s*\n)',
        r'\1\2@import "../omarchy/current/theme/walker.css";\n',
        style,
        count=1,
    )
    if n == 0:
        # No existing waybar.css import — prepend both.
        new_style = ('@import "../omarchy/current/theme/waybar.css";\n'
                     '@import "../omarchy/current/theme/walker.css";\n\n' + style)
    style = new_style

# 2. Tooltip rules inside a marker block (idempotent replace)
MARKER_START = '/* >>> battery-tooltip */'
MARKER_END   = '/* <<< battery-tooltip */'
tooltip_block = (
    f'{MARKER_START}\n'
    'tooltip,\n'
    'tooltip box,\n'
    'tooltip label,\n'
    'tooltip * {\n'
    '  margin: 0;\n'
    '  padding: 0;\n'
    '}\n\n'
    'tooltip {\n'
    '  padding: 7px;\n'
    '  border: 2px solid @selected-text;\n'
    '}\n'
    f'{MARKER_END}\n'
)

block_re = re.compile(re.escape(MARKER_START) + r'.*?' + re.escape(MARKER_END) + r'\n?', re.DOTALL)
if block_re.search(style):
    style = block_re.sub(tooltip_block, style)
else:
    style = style.rstrip() + '\n\n' + tooltip_block

style_path.write_text(style)
print('  · style.css:    walker.css import + tooltip rules in place')
PY

# --- Reload ---
if command -v omarchy-restart-waybar >/dev/null; then
    if omarchy-restart-waybar >/dev/null 2>&1; then
        echo "→ Waybar restarted."
    else
        echo "⚠  omarchy-restart-waybar failed — reload manually."
    fi
fi

cat << EOF

✓ Done. Hover the battery icon to see:

    󰁿 Battery XX% · HHh:MMm left · ↓X.XW/${WH}Wh

Inside an accent-colored border matching the active theme.

Backups (this run): ${CONFIG}.bak.${TS}
                    ${STYLE}.bak.${TS}

Re-run with  --current  to use the degraded (current full-charge) capacity
instead of design capacity.
EOF
