#!/usr/bin/env bash
# Generate all three Grubwaita themes from a 4K asset master.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
S="${ROOT}/source"
for cmd in ffmpeg magick inkscape grub-mkfont fc-match sed; do
    command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" >&2; exit 1; }
done
[[ -f "$S/background/adwaita-d.jxl" ]] || {
    echo "Place the original adwaita-d.jxl at source/background/adwaita-d.jxl" >&2; exit 1;
}
[[ -f "$ROOT/templates/theme.txt.in" ]] || { echo "Missing template" >&2; exit 1; }
for asset in panel countdown-pill select_nw select_n select_ne select_w select_c select_e select_sw select_s select_se; do
    [[ -f "$S/overlays/${asset}.png" ]] || { echo "Missing 4K master overlay: ${asset}.png" >&2; exit 1; }
done
for icon in debian fedora arch ubuntu; do
    [[ -f "$S/icons/os/${icon}.svg" ]] || { echo "Missing SVG: source/icons/os/${icon}.svg" >&2; exit 1; }
done
for icon in back settings terminal timer; do
    [[ -f "$S/icons/controls/${icon}.svg" ]] || { echo "Missing SVG: source/icons/controls/${icon}.svg" >&2; exit 1; }
done

# Fonts are built locally; do not place font source files in the public release.
CANTARELL="$(fc-match -f '%{file}\n' 'Cantarell:style=Bold' | head -n 1)"
FIRACODE="$(fc-match -f '%{file}\n' 'Fira Code:style=Retina' | head -n 1)"
[[ -f "$CANTARELL" && -f "$FIRACODE" ]] || { echo "Install fonts-cantarell and fonts-firacode" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
ffmpeg -hide_banner -loglevel error -y -i "$S/background/adwaita-d.jxl" \
    -frames:v 1 -update 1 "$TMP/wallpaper.png"

for RES in 3840x2160 2560x1440 1920x1080; do
    case "$RES" in
       3840x2160) W=3840; H=2160; SCALE='100%'; BLUR=80 ;;
       2560x1440) W=2560; H=1440; SCALE='66.6667%'; BLUR=53 ;;
       1920x1080) W=1920; H=1080; SCALE='50%'; BLUR=40 ;;
    esac
    # Integer sizes scaled from the 1920x1080 design baseline.
    TITLE=$((52 * W / 1920))
    ITEM=$((28 * W / 1920))
    TIMEOUT=$((26 * W / 1920))
    TERM=$((22 * W / 1920))
    ICON=$((48 * W / 1920))
    ICON_GAP=$((18 * W / 1920))
    ITEM_HEIGHT=$((61 * W / 1920))
    ITEM_PADDING=$((7 * W / 1920))
    ITEM_SPACING=$((10 * W / 1920))
    OUT="$ROOT/variants/$RES"
    mkdir -p "$OUT/icons"
    echo "Generating $RES assets..."

    magick "$TMP/wallpaper.png" -resize "${W}x${H}^" \
        -gravity center -extent "${W}x${H}" -blur "0x${BLUR}" \
        -evaluate multiply 0.5 -depth 8 -strip "$OUT/background.png"
    for file in "$S"/overlays/*.png; do
        magick "$file" -resize "$SCALE" -depth 8 -strip "$OUT/$(basename "$file")"
    done
    for icon in debian fedora arch ubuntu; do
        inkscape "$S/icons/os/${icon}.svg" --export-width="$ICON" \
            --export-height="$ICON" --export-filename="$OUT/icons/${icon}.png" >/dev/null 2>&1
    done
    for icon in back settings terminal timer; do
        inkscape "$S/icons/controls/${icon}.svg" --export-width="$ICON" \
            --export-height="$ICON" --export-filename="$OUT/${icon}.png" >/dev/null 2>&1
    done
    # Flat next to theme.txt so GRUB can discover the generated PF2 assets.
    grub-mkfont -s "$TITLE" -n "Cantarell Bold $TITLE" -o "$OUT/Cantarell-Bold-${TITLE}.pf2" "$CANTARELL"
    grub-mkfont -s "$ITEM" -n "Cantarell Bold $ITEM" -o "$OUT/Cantarell-Bold-${ITEM}.pf2" "$CANTARELL"
    grub-mkfont -s "$TIMEOUT" -n "Cantarell Bold $TIMEOUT" -o "$OUT/Cantarell-Bold-${TIMEOUT}.pf2" "$CANTARELL"
    grub-mkfont -s "$TERM" -n "Fira Code Retina $TERM" -o "$OUT/Fira-Code-Retina-${TERM}.pf2" "$FIRACODE"

    sed \
      -e "s/@TITLE_FONT@/$TITLE/g" \
      -e "s/@ITEM_FONT@/$ITEM/g" \
      -e "s/@TIMEOUT_FONT@/$TIMEOUT/g" \
      -e "s/@TERMINAL_FONT@/$TERM/g" \
      -e "s/@ICON_SIZE@/$ICON/g" \
      -e "s/@ICON_GAP@/$ICON_GAP/g" \
      -e "s/@ITEM_HEIGHT@/$ITEM_HEIGHT/g" \
      -e "s/@ITEM_PADDING@/$ITEM_PADDING/g" \
      -e "s/@ITEM_SPACING@/$ITEM_SPACING/g" \
       "$ROOT/templates/theme.txt.in" > "$OUT/theme.txt"
    echo "Built $OUT"
done
