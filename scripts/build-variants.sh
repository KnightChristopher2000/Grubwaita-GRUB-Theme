#!/usr/bin/env bash
# Grubwaita GRUB Theme - distro-independent asset builder.
# Generates all three variants from the project source assets.
set -Eeuo pipefail

export PATH="${PATH}:/usr/local/sbin:/usr/sbin:/sbin"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE="${ROOT}/source"
VARIANTS="${ROOT}/variants"

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'HELP'
Usage: ./scripts/build-variants.sh [--help]

Build 3840x2160, 2560x1440, and 1920x1080 theme variants.

Optional font overrides (absolute paths to installed font files):
  GRUBWAITA_CANTARELL_FONT=/path/to/Cantarell-Bold.ttf
  GRUBWAITA_FIRACODE_FONT=/path/to/FiraCode-Retina.ttf

The builder never installs anything to /boot or modifies GRUB.
HELP
}

case "${1:-}" in
  '') ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

for cmd in sed fc-match mktemp basename cp mv; do
  has "$cmd" || fail "Missing command: $cmd"
done

if has magick; then
  IM="$(command -v magick)"
elif has convert; then
  IM="$(command -v convert)"
else
  fail 'Install ImageMagick (magick on v7, or convert on v6).'
fi

if has grub-mkfont; then
  MKFONT="$(command -v grub-mkfont)"
elif has grub2-mkfont; then
  MKFONT="$(command -v grub2-mkfont)"
else
  fail 'Install the GRUB font-generation tools (grub-mkfont or grub2-mkfont).'
fi

if has inkscape; then
  SVG_RENDERER=inkscape
elif has rsvg-convert; then
  SVG_RENDERER=rsvg-convert
else
  fail 'Install Inkscape or librsvg (rsvg-convert) to render SVG icons.'
fi

[[ -f "${SOURCE}/background/adwaita-d.jxl" ]] ||
  fail 'Missing source/background/adwaita-d.jxl'
[[ -f "${ROOT}/templates/theme.txt.in" ]] ||
  fail 'Missing templates/theme.txt.in'

for asset in panel countdown-pill \
  select_nw select_n select_ne select_w select_c select_e \
  select_sw select_s select_se; do
  [[ -f "${SOURCE}/overlays/${asset}.png" ]] ||
    fail "Missing source/overlays/${asset}.png"
done
# OS icon filenames map to GRUB menuentry classes. Automatically include any
# additional distro/OS icons contributed to the project, not just the starter four.
shopt -s nullglob
OS_SVGS=("${SOURCE}"/icons/os/*.svg)
((${#OS_SVGS[@]} > 0)) || fail 'No SVG icons found in source/icons/os/'
for file in "${OS_SVGS[@]}"; do
  name="$(basename "$file" .svg)"
  [[ "$name" =~ ^[A-Za-z0-9._+-]+$ ]] || fail "Unsafe OS icon name: $name"
done
for icon in back settings terminal timer; do
  [[ -f "${SOURCE}/icons/controls/${icon}.svg" ]] ||
    fail "Missing source/icons/controls/${icon}.svg"
done
CONTROL_SVGS=("${SOURCE}"/icons/controls/*.svg)

find_font() {
  local override="$1" family="$2" desired="$3" path actual_family actual_style
  if [[ -n "$override" ]]; then
    [[ -f "$override" ]] || fail "Font override does not exist: $override"
    printf '%s\n' "$override"
    return
  fi
  actual_family="$(fc-match -f '%{family}\n' "$desired" | sed -n '1p')"
  actual_style="$(fc-match -f '%{style}\n' "$desired" | sed -n '1p')"
  path="$(fc-match -f '%{file}\n' "$desired" | sed -n '1p')"
  case "${actual_family,,}" in
    *"${family,,}"*) ;;
    *) fail "Font '$family' not installed (Fontconfig selected '${actual_family:-nothing}')." ;;
  esac
  [[ -f "$path" ]] || fail "Font file not found: $path"
  if [[ "$desired" == *Retina* && "${actual_style,,}" != *retina* ]]; then
    printf 'Warning: Fira Code Retina not reported by Fontconfig (found style: %s).\n' "$actual_style" >&2
    printf '         Set GRUBWAITA_FIRACODE_FONT to select the exact font file.\n' >&2
  fi
  printf '%s\n' "$path"
}

CANTARELL="$(find_font "${GRUBWAITA_CANTARELL_FONT:-}" 'Cantarell' 'Cantarell:style=Bold')"
FIRACODE="$(find_font "${GRUBWAITA_FIRACODE_FONT:-}" 'Fira Code' 'Fira Code:style=Retina')"

render_svg() {
  local in="$1" out="$2" size="$3"
  if [[ "$SVG_RENDERER" == inkscape ]]; then
    inkscape "$in" --export-width="$size" --export-height="$size" \
      --export-filename="$out" >/dev/null 2>&1
  else
    rsvg-convert --width="$size" --height="$size" --output="$out" "$in"
  fi
  [[ -s "$out" ]] || fail "SVG rasterization failed: $in"
}

mkdir -p -- "$VARIANTS"
TMP="$(mktemp -d "${VARIANTS}/.build-XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT

# Prefer ffmpeg for JPEG XL decoding; fall back to ImageMagick if it supports JXL.
if has ffmpeg && ffmpeg -hide_banner -loglevel error -y \
    -i "${SOURCE}/background/adwaita-d.jxl" -frames:v 1 -update 1 \
    "${TMP}/wallpaper.png" && [[ -s "${TMP}/wallpaper.png" ]]; then
  :
elif "$IM" "${SOURCE}/background/adwaita-d.jxl" -depth 8 "PNG32:${TMP}/wallpaper.png"; then
  [[ -s "${TMP}/wallpaper.png" ]] || fail 'Wallpaper conversion produced no output.'
else
  fail 'Could not decode JPEG XL. Install ffmpeg with JXL support or ImageMagick with JXL support.'
fi

for RES in 3840x2160 2560x1440 1920x1080; do
  case "$RES" in
    3840x2160) W=3840; H=2160; SCALE='100%'; BLUR=80 ;;
    2560x1440) W=2560; H=1440; SCALE='66.6667%'; BLUR=53 ;;
    1920x1080) W=1920; H=1080; SCALE='50%'; BLUR=40 ;;
  esac

  TITLE=$((52 * W / 1920))
  ITEM=$((28 * W / 1920))
  TIMEOUT=$((26 * W / 1920))
  TERM=$((22 * W / 1920))
  ICON=$((48 * W / 1920))
  ICON_GAP=$((18 * W / 1920))
  ITEM_HEIGHT=$((61 * W / 1920))
  ITEM_PADDING=$((7 * W / 1920))
  ITEM_SPACING=$((10 * W / 1920))

  OUT="${TMP}/${RES}"
  mkdir -p "${OUT}/icons"
  printf 'Building %s...\n' "$RES"

  "$IM" "${TMP}/wallpaper.png" -resize "${W}x${H}^" \
    -gravity center -extent "${W}x${H}" -blur "0x${BLUR}" \
    -evaluate multiply 0.5 -depth 8 -strip "PNG32:${OUT}/background.png"

  # Every source overlay is a transparent, tightly cropped 4K master.
  for file in "${SOURCE}"/overlays/*.png; do
    "$IM" "$file" -resize "$SCALE" -depth 8 -strip \
      "PNG32:${OUT}/$(basename "$file")"
  done

  for file in "${OS_SVGS[@]}"; do
    icon="$(basename "$file" .svg)"
    render_svg "$file" "${OUT}/icons/${icon}.png" "$ICON"
  done
  for file in "${CONTROL_SVGS[@]}"; do
    icon="$(basename "$file" .svg)"
    render_svg "$file" "${OUT}/${icon}.png" "$ICON"
  done

  "$MKFONT" -s "$TITLE" -n "Cantarell Bold $TITLE" \
    -o "${OUT}/Cantarell-Bold-${TITLE}.pf2" "$CANTARELL"
  "$MKFONT" -s "$ITEM" -n "Cantarell Bold $ITEM" \
    -o "${OUT}/Cantarell-Bold-${ITEM}.pf2" "$CANTARELL"
  "$MKFONT" -s "$TIMEOUT" -n "Cantarell Bold $TIMEOUT" \
    -o "${OUT}/Cantarell-Bold-${TIMEOUT}.pf2" "$CANTARELL"
  "$MKFONT" -s "$TERM" -n "Fira Code Retina $TERM" \
    -o "${OUT}/Fira-Code-Retina-${TERM}.pf2" "$FIRACODE"

  sed \
    -e "s/@TITLE_FONT@/${TITLE}/g" \
    -e "s/@ITEM_FONT@/${ITEM}/g" \
    -e "s/@TIMEOUT_FONT@/${TIMEOUT}/g" \
    -e "s/@TERMINAL_FONT@/${TERM}/g" \
    -e "s/@ICON_SIZE@/${ICON}/g" \
    -e "s/@ICON_GAP@/${ICON_GAP}/g" \
    -e "s/@ITEM_HEIGHT@/${ITEM_HEIGHT}/g" \
    -e "s/@ITEM_PADDING@/${ITEM_PADDING}/g" \
    -e "s/@ITEM_SPACING@/${ITEM_SPACING}/g" \
    "${ROOT}/templates/theme.txt.in" > "${OUT}/theme.txt"

  [[ -s "${OUT}/theme.txt" && -s "${OUT}/background.png" ]] ||
    fail "Incomplete build for $RES"
  for font in "${OUT}"/*.pf2; do
    [[ -s "$font" ]] || fail "Missing or empty PF2 file: $font"
  done
  if grep -Eq '@[A-Z_]+@' "${OUT}/theme.txt"; then
    fail "Unexpanded placeholder in ${OUT}/theme.txt"
  fi

  # Rebuild cleanly; do not leave old files from a previous design version.
  DEST="${VARIANTS}/${RES}"
  rm -rf -- "$DEST"
  mv -- "$OUT" "$DEST"
  printf 'Ready: %s\n' "$DEST"
done

printf '\nAll three Grubwaita variants built successfully.\n'
