#!/usr/bin/env bash
# Grubwaita GRUB Theme - portable, conservative GRUB installer.
# Supports conventional GRUB/grub2 layouts without distro-name guessing.
set -Eeuo pipefail

export PATH="${PATH}:/usr/local/sbin:/usr/sbin:/sbin"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RES='1920x1080'
CONFIG_REQUEST=''
DRY_RUN=0
SHOW_MENU=0
RES_GIVEN=0

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }
usage() {
  cat <<'HELP'
Usage: sudo ./scripts/select-resolution.sh [RESOLUTION] [OPTIONS]

Resolution (default: 1920x1080):
  3840x2160 | 2560x1440 | 1920x1080

Options:
  --config /absolute/path/to/grub.cfg  Explicit GRUB configuration to update
  --show-menu                         Set menu style and 10-second timeout
  --dry-run                           Report decisions; change no files
  -h, --help                          Show this help

Default behavior preserves your existing GRUB timeout and default boot entry.
The installer REFUSES ambiguous GRUB configurations or EFI stub targets.
Successful installs create a backup under /var/backups/grubwaita/.

Requires an installed GRUB 2 and grub-mkconfig or grub2-mkconfig.
Does not install, replace, sign, or modify any EFI executable.
HELP
}

while (($#)); do
  case "$1" in
    3840x2160|2560x1440|1920x1080)
      ((RES_GIVEN == 0)) || fail 'Provide the resolution only once.'
      RES="$1"
      RES_GIVEN=1
      shift ;;
    --config)
      (($# >= 2)) || fail '--config requires an absolute path.'
      CONFIG_REQUEST="$2"
      shift 2 ;;
    --show-menu) SHOW_MENU=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; fail "Unknown option: $1" ;;
  esac
done

[[ -f "${ROOT}/variants/${RES}/theme.txt" ]] ||
  fail "Missing variants/${RES}/theme.txt. Run ./scripts/build-variants.sh first."
SRC="${ROOT}/variants/${RES}"
for asset in background.png panel.png countdown-pill.png select_c.png; do
  [[ -s "${SRC}/${asset}" ]] || fail "Missing or empty variant asset: $asset"
done
shopt -s nullglob
FONTS=("${SRC}"/*.pf2)
((${#FONTS[@]} > 0)) || fail "No PF2 fonts in ${SRC}"
for font in "${FONTS[@]}"; do
  [[ -s "$font" ]] || fail "Empty font: $font"
  base="$(basename "$font")"
  [[ "$base" =~ ^[A-Za-z0-9._-]+\.pf2$ ]] ||
    fail "Unsafe font filename: $base"
done

if has grub-mkconfig; then
  MKCONFIG="$(command -v grub-mkconfig)"
elif has grub2-mkconfig; then
  MKCONFIG="$(command -v grub2-mkconfig)"
else
  fail 'Neither grub-mkconfig nor grub2-mkconfig is installed.'
fi

if [[ -n "$CONFIG_REQUEST" ]]; then
  [[ "$CONFIG_REQUEST" = /* ]] || fail '--config requires an absolute path.'
  [[ -f "$CONFIG_REQUEST" ]] || fail "GRUB config not found: $CONFIG_REQUEST"
  CONFIG="$(readlink -f -- "$CONFIG_REQUEST")"
else
  # Do not assume which grub.cfg is active if both layouts are present.
  CONFIGS=()
  for candidate in /boot/grub/grub.cfg /boot/grub2/grub.cfg; do
    if [[ -f "$candidate" ]]; then
      resolved="$(readlink -f -- "$candidate")"
      found=0
      for existing in "${CONFIGS[@]}"; do
        if [[ "$existing" == "$resolved" ]]; then found=1; break; fi
      done
      ((found == 1)) || CONFIGS+=("$resolved")
    fi
  done
  case "${#CONFIGS[@]}" in
    0) fail 'No standard GRUB configuration found. Use --config with the active grub.cfg.' ;;
    1) CONFIG="${CONFIGS[0]}" ;;
    *) fail 'More than one GRUB configuration exists. Choose the active one with --config.' ;;
  esac
fi

[[ -f "$CONFIG" && "$(basename "$CONFIG")" == 'grub.cfg' ]] ||
  fail "The target must be an existing grub.cfg file: $CONFIG"
case "$CONFIG" in
  */EFI/*|*/efi/*|/efi/*)
    fail 'Refusing an EFI partition/configuration stub. Use the real /boot/grub[2]/grub.cfg.' ;;
esac

GRUB_DIR="$(dirname -- "$CONFIG")"
[[ -d "$GRUB_DIR" ]] || fail "GRUB directory unavailable: $GRUB_DIR"
DEST="${GRUB_DIR}/themes/grubwaita"
DEFAULT='/etc/default/grub'
FONT_HELPER='/etc/grub.d/09_grubwaita_fonts'
LEGACY='/etc/default/grub.d/90-grubwaita.cfg'

[[ -f "$DEFAULT" && ! -L "$DEFAULT" ]] ||
  fail 'Expected a regular /etc/default/grub file, not a missing file or symlink.'
[[ -d /etc/grub.d ]] || fail '/etc/grub.d is missing.'
[[ ! -L "$DEST" ]] || fail "Refusing a symlink theme destination: $DEST"
[[ ! -e "$DEST" || -d "$DEST" ]] || fail "Non-directory theme destination: $DEST"
[[ ! -L "$FONT_HELPER" ]] || fail "Refusing a symlink helper: $FONT_HELPER"

# An older Grubwaita release used a drop-in file. Migrate only that exact file;
# otherwise refuse to alter a user-owned file with the same filename.
MIGRATE_LEGACY=0
if [[ -e "$LEGACY" ]]; then
  [[ -f "$LEGACY" && ! -L "$LEGACY" ]] || fail "Unexpected legacy path: $LEGACY"
  if grep -Fq '/themes/grubwaita/theme.txt' "$LEGACY"; then
    MIGRATE_LEGACY=1
  else
    fail "Unrecognized $LEGACY. Rename it manually before installing."
  fi
fi

# Most GRUB versions source /etc/default/grub; some source additional .cfg
# drop-ins afterward. Refuse a conflicting theme assignment rather than
# incorrectly claiming installation succeeded.
for snippet in /etc/default/grub.d/*.cfg; do
  [[ -f "$snippet" ]] || continue
  if [[ "$snippet" == "$LEGACY" && "$MIGRATE_LEGACY" == 1 ]]; then continue; fi
  if grep -Eq '^[[:space:]]*(export[[:space:]]+)?GRUB_THEME[[:space:]]*=' "$snippet"; then
    fail "Conflicting GRUB_THEME in $snippet. Disable or reconcile it first."
  fi
done

printf 'Theme variant : %s\n' "$RES"
printf 'GRUB generator: %s\n' "$MKCONFIG"
printf 'GRUB config   : %s\n' "$CONFIG"
printf 'Install theme : %s\n' "$DEST"
printf 'Settings file : %s (managed block)\n' "$DEFAULT"
((SHOW_MENU == 0)) || printf 'Menu behavior : visible, 10-second timeout\n'
((MIGRATE_LEGACY == 0)) || printf 'Migration     : old Grubwaita drop-in will be backed up\n'

if grep -Eq '^[[:space:]]*(export[[:space:]]+)?GRUB_TERMINAL[[:space:]]*=' "$DEFAULT"; then
  printf 'Warning: GRUB_TERMINAL may override gfxterm; review console/serial settings.\n' >&2
fi
if ((SHOW_MENU == 0)) && grep -Eq '^[[:space:]]*GRUB_TIMEOUT_STYLE[[:space:]]*=[[:space:]]*["\x27]?hidden' "$DEFAULT"; then
  printf 'Note: the existing hidden timeout might prevent the theme from appearing.\n' >&2
  printf '      Re-run with --show-menu if that is intended.\n' >&2
fi
if ((DRY_RUN)); then
  printf '\nDry run only; no files changed.\n'
  exit 0
fi

((EUID == 0)) || fail 'Installation requires root. Run with sudo, or use --dry-run.'
for command in awk mktemp install cp mv rm readlink grep; do
  has "$command" || fail "Missing required command: $command"
done

BACKUP_ROOT='/var/backups/grubwaita'
install -d -m 0700 "$BACKUP_ROOT"
BACKUP="$(mktemp -d "${BACKUP_ROOT}/install-XXXXXXXX")"

# Store exactly the original objects needed for a lossless rollback.
cp -a -- "$DEFAULT" "${BACKUP}/default-grub"
cp -a -- "$CONFIG" "${BACKUP}/grub.cfg"
OLD_THEME=0
OLD_HELPER=0
if [[ -d "$DEST" ]]; then
  cp -a -- "$DEST" "${BACKUP}/theme"
  OLD_THEME=1
fi
if [[ -e "$FONT_HELPER" ]]; then
  cp -a -- "$FONT_HELPER" "${BACKUP}/font-helper"
  OLD_HELPER=1
fi
if ((MIGRATE_LEGACY)); then
  cp -a -- "$LEGACY" "${BACKUP}/old-dropin.cfg"
fi

CHANGED=0
SUCCEEDED=0
STAGE=''
rollback_if_needed() {
  local status=$?
  trap - EXIT
  if [[ -n "$STAGE" && -d "$STAGE" ]]; then
    rm -rf -- "$STAGE" || :
  fi
  if ((CHANGED && !SUCCEEDED)); then
    printf '\nInstallation failed; restoring saved GRUB files...\n' >&2
    cp -a -- "${BACKUP}/default-grub" "$DEFAULT" || :
    cp -a -- "${BACKUP}/grub.cfg" "$CONFIG" || :
    rm -rf -- "$DEST" || :
    if ((OLD_THEME)); then cp -a -- "${BACKUP}/theme" "$DEST" || :; fi
    if ((OLD_HELPER)); then
      cp -a -- "${BACKUP}/font-helper" "$FONT_HELPER" || :
    else
      rm -f -- "$FONT_HELPER" || :
    fi
    if ((MIGRATE_LEGACY)); then
      cp -a -- "${BACKUP}/old-dropin.cfg" "$LEGACY" || :
    fi
    printf 'Recovery copies retained at: %s\n' "$BACKUP" >&2
  fi
  exit "$status"
}
trap rollback_if_needed EXIT

# Detect malformed or multiply nested blocks before touching the original.
FILTERED="$(mktemp "${BACKUP}/default-filtered-XXXXXX")"
awk '
  $0 == "# BEGIN GRUBWAITA MANAGED" {
    if (inside || seen) exit 2
    inside=1; seen=1; next
  }
  $0 == "# END GRUBWAITA MANAGED" {
    if (!inside) exit 3
    inside=0; next
  }
  !inside { print }
  END { if (inside) exit 4 }
' "$DEFAULT" > "$FILTERED" || fail 'Malformed managed block in /etc/default/grub.'

cat >> "$FILTERED" <<SETTINGS

# BEGIN GRUBWAITA MANAGED
GRUB_THEME="${DEST}/theme.txt"
GRUB_GFXMODE="${RES},auto"
GRUB_TERMINAL_OUTPUT="gfxterm"
SETTINGS
if ((SHOW_MENU)); then
  cat >> "$FILTERED" <<'SETTINGS'
GRUB_TIMEOUT_STYLE="menu"
GRUB_TIMEOUT="10"
SETTINGS
fi
printf '# END GRUBWAITA MANAGED\n' >> "$FILTERED"

# Check the generated defaults file before installing it.
/bin/sh -n "$FILTERED" || fail 'Generated /etc/default/grub failed shell syntax check.'

mkdir -p -- "${GRUB_DIR}/themes"
STAGE="$(mktemp -d "${GRUB_DIR}/themes/.grubwaita-stage-XXXXXX")"
cp -a -- "${SRC}/." "$STAGE/"
[[ -s "$STAGE/theme.txt" ]] || fail 'Staged theme is incomplete.'

HELPER_TEMP="$(mktemp "${BACKUP}/font-helper-XXXXXX")"
{
  cat <<'GRUB_START'
#!/bin/sh
# Generated by Grubwaita. This emits GRUB-language commands during mkconfig.
cat <<'GRUBWAITA_FONT_COMMANDS'
GRUB_START
  for font in "${FONTS[@]}"; do
    base="$(basename "$font")"
    printf 'if [ -f "$prefix/themes/grubwaita/%s" ]; then\n  loadfont "$prefix/themes/grubwaita/%s"\nfi\n' "$base" "$base"
  done
  printf 'GRUBWAITA_FONT_COMMANDS\n'
} > "$HELPER_TEMP"
/bin/sh -n "$HELPER_TEMP" || fail 'Generated font helper failed shell syntax check.'

# All mutations from here are covered by the EXIT rollback trap.
CHANGED=1
if ((MIGRATE_LEGACY)); then rm -f -- "$LEGACY"; fi
rm -rf -- "$DEST"
mv -- "$STAGE" "$DEST"
STAGE=''
chown -R root:root "$DEST"
chmod -R u=rwX,go=rX "$DEST"

# Keep the prior main-config ownership/mode while switching to the new block.
chown --reference="$DEFAULT" "$FILTERED"
chmod --reference="$DEFAULT" "$FILTERED"
mv -- "$FILTERED" "$DEFAULT"
install -m 0755 "$HELPER_TEMP" "$FONT_HELPER"

printf '\nRegenerating %s...\n' "$CONFIG"
"$MKCONFIG" -o "$CONFIG"

if has grub-script-check; then
  grub-script-check "$CONFIG"
elif has grub2-script-check; then
  grub2-script-check "$CONFIG"
fi

SUCCEEDED=1
printf '\nGrubwaita %s installed.\n' "$RES"
printf 'Backup (restore if needed): %s\n' "$BACKUP"
printf 'Reboot to test. Firmware may not support every requested graphics mode.\n'
