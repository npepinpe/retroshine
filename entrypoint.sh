#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR=/config

# ── Directories ──────────────────────────────────────────────────────────────
mkdir -p \
    "${CONFIG_DIR}/sunshine" \
    "${CONFIG_DIR}/sunshine/covers" \
    "${CONFIG_DIR}/retroarch/saves" \
    "${CONFIG_DIR}/retroarch/states" \
    "${CONFIG_DIR}/retroarch/screenshots" \
    "${CONFIG_DIR}/retroarch/cores" \
    "${CONFIG_DIR}/retroarch/info" \
    "${CONFIG_DIR}/dolphin/Config" \
    "${CONFIG_DIR}/dusklight" \
    "${CONFIG_DIR}/es-de/ES-DE/settings" \
    "${CONFIG_DIR}/logs" \
    /tmp/runtime/pulse
chmod 700 /tmp/runtime

# ── Seed helper ───────────────────────────────────────────────────────────
# Set RESEED_CONFIG=true to overwrite all seeded files on this boot, which
# makes it easy to test config changes without wiping the volume manually.
seed() {
    local src="$1" dst="$2"
    if [ ! -f "$dst" ] || [ "${RESEED_CONFIG:-false}" = "true" ]; then
        cp "$src" "$dst"
    fi
}

# ── Seed default configs ───────────────────────────────────────────────────
# sunshine.conf goes in /config/ root (Sunshine's default config location).
# apps.json is looked up relative to file_state, so it goes in /config/sunshine/.
seed /etc/retroshine/sunshine.conf "${CONFIG_DIR}/sunshine.conf"
# apps.json is managed via git; always overwrite so deploys take effect without
# manual intervention. (Do NOT use the web UI to add apps — it won't persist.)
cp /etc/retroshine/apps.json "${CONFIG_DIR}/sunshine/apps.json"

seed /etc/retroshine/retroarch.cfg "${CONFIG_DIR}/retroarch/retroarch.cfg"

for f in Dolphin.ini GFX.ini; do
    seed "/etc/retroshine/dolphin/${f}" "${CONFIG_DIR}/dolphin/Config/${f}"
done

# ── ROM symlink tree (/roms → /games) ────────────────────────────────────
# /games is read-only; /roms is a writable view with ES-DE's expected names.
# Only n3ds differs from the NAS folder name (NAS: 3ds, ES-DE: n3ds).
mkdir -p /roms
for sys in gba gbc gc n64 nds ps2 psp psx snes; do
    ln -sfn "/games/${sys}" "/roms/${sys}"
done
ln -sfn /games/3ds /roms/n3ds

# ── ES-DE config → /config volume ────────────────────────────────────────
seed /etc/retroshine/es-de/settings/es_settings.xml \
     "${CONFIG_DIR}/es-de/ES-DE/settings/es_settings.xml"
# Patch critical settings (ROM path, wizard bypass) without clobbering user prefs
patch-esde-settings "${CONFIG_DIR}/es-de/ES-DE/settings/es_settings.xml" 2>/dev/null || true

# ── Sunshine default config dir → /config volume ──────────────────────────
# Symlink the entire ~/.config/sunshine to the volume so all Sunshine files
# (TLS cert/key, client certs, state, apps.json, covers) persist across
# container restarts. Without this, Sunshine regenerates its TLS certificate
# on every start and all paired clients must re-pair.
mkdir -p "${CONFIG_DIR}/sunshine/covers" /root/.config
ln -sfn "${CONFIG_DIR}/sunshine" /root/.config/sunshine

# ── Dusklight saves → /config volume ─────────────────────────────────────
mkdir -p /root/.local/share/TwilitRealm
ln -sfn "${CONFIG_DIR}/dusklight" /root/.local/share/TwilitRealm/Dusklight
seed /etc/retroshine/dusklight.json "${CONFIG_DIR}/dusklight/config.json"

# ── DuckStation (PSX) → /config volume ───────────────────────────────────
mkdir -p "${CONFIG_DIR}/duckstation"
ln -sfn "${CONFIG_DIR}/duckstation" /root/.local/share/duckstation
seed /etc/retroshine/duckstation.ini "${CONFIG_DIR}/duckstation/settings.ini"

# ── PPSSPP (PSP) → /config volume ────────────────────────────────────────
mkdir -p "${CONFIG_DIR}/ppsspp/PSP/SYSTEM"
ln -sfn "${CONFIG_DIR}/ppsspp" /root/.config/ppsspp
seed /etc/retroshine/ppsspp.ini "${CONFIG_DIR}/ppsspp/PSP/SYSTEM/ppsspp.ini"

# ── udevd (hot-plug for Xorg keyboard/mouse + SDL2 gamepad) ──────────────
# Docker blocks udevd-filtered netlink from the host; run our own daemon so
# the container receives enriched input events when Sunshine creates virtual
# devices via uinput at Moonlight connect time.
mkdir -p /run/udev
/lib/systemd/systemd-udevd &
sleep 2
udevadm trigger --action=add --subsystem-match=input 2>/dev/null || true
udevadm settle --timeout=5 2>/dev/null || true

# ── Sunshine credentials ──────────────────────────────────────────────────
# Set via SUNSHINE_USER / SUNSHINE_PASS env vars.
# --creds writes a bcrypt-hashed entry to the credentials file and exits.
SUNSHINE_USER="${SUNSHINE_USER:-admin}"
SUNSHINE_PASS="${SUNSHINE_PASS:-changeme}"

/usr/bin/sunshine "${CONFIG_DIR}/sunshine.conf" \
    --creds "${SUNSHINE_USER}" "${SUNSHINE_PASS}" \
    || true   # non-fatal if credentials are already set

# ── VAAPI / Intel driver ──────────────────────────────────────────────────
export LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-iHD}"

# ── PulseAudio: ensure module-native-protocol-unix socket dir exists ──────
export PULSE_RUNTIME_PATH=/tmp/runtime/pulse

# ── Exec supervisord ──────────────────────────────────────────────────────
exec /usr/bin/supervisord -c /etc/retroshine/supervisord.conf
