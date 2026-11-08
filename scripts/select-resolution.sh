#!/usr/bin/env bash
# Installs the chosen prebuilt theme variant on Debian/Ubuntu-based GRUB systems.
set -Eeuo pipefail
RES="${1:-1920x1080}"
case "$RES" in
    3840x2160|2560x1440|1920x1080) ;;
    *) echo "Usage: sudo $0 {3840x2160|2560x1440|1920x1080}" >&2; exit 2 ;;
esac
[[ "${EUID}" -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/variants/$RES"
DEST='/boot/grub/themes/grubwaita'
[[ -f "$SRC/theme.txt" ]] || { echo "Build the theme first: $SRC/theme.txt not found." >&2; exit 1; }
command -v update-grub >/dev/null || { echo "Debian/Ubuntu update-grub command not found." >&2; exit 1; }
install -d -m 0755 "$DEST" /etc/default/grub.d
cp -R "$SRC/." "$DEST/"
chown -R root:root "$DEST"
chmod -R u=rwX,go=rX "$DEST"
# Keep generated theme configuration separate from the user's main GRUB config.
cat >/etc/default/grub.d/90-grubwaita.cfg <<CFG
GRUB_THEME="$DEST/theme.txt"
GRUB_GFXMODE="$RES,auto"
GRUB_TERMINAL_OUTPUT="gfxterm"
GRUB_TIMEOUT_STYLE="menu"
GRUB_TIMEOUT="10"
CFG
# Explicitly register fonts before the boot menu is shown.
cat >/etc/grub.d/09_grubwaita_fonts <<'HEAD'
#!/bin/sh
cat <<'GRUB_FONT_COMMANDS'
HEAD
for font in "$SRC"/*.pf2; do
    name="$(basename "$font")"
    printf 'if [ -f "$prefix/themes/grubwaita/%s" ]; then\n  loadfont "$prefix/themes/grubwaita/%s"\nfi\n' "$name" "$name" >> /etc/grub.d/09_grubwaita_fonts
done
cat >>/etc/grub.d/09_grubwaita_fonts <<'TAIL'
GRUB_FONT_COMMANDS
TAIL
chmod 0755 /etc/grub.d/09_grubwaita_fonts
update-grub
printf 'Installed Grubwaita %s. Reboot to test.\n' "$RES"
