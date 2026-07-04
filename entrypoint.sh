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

# ── Seed default configs (only on first boot) ─────────────────────────────
# sunshine.conf goes in /config/ root (Sunshine's default config location).
# apps.json is looked up relative to file_state, so it goes in /config/sunshine/.
if [ ! -f "${CONFIG_DIR}/sunshine.conf" ]; then
    cp /etc/retroshine/sunshine.conf "${CONFIG_DIR}/sunshine.conf"
fi
# apps.json is managed via git; always overwrite so deploys take effect without
# manual intervention. (Do NOT use the web UI to add apps — it won't persist.)
cp /etc/retroshine/apps.json "${CONFIG_DIR}/sunshine/apps.json"

if [ ! -f "${CONFIG_DIR}/retroarch/retroarch.cfg" ]; then
    cp /etc/retroshine/retroarch.cfg "${CONFIG_DIR}/retroarch/retroarch.cfg"
fi

for f in Dolphin.ini GFX.ini; do
    if [ ! -f "${CONFIG_DIR}/dolphin/Config/${f}" ]; then
        cp "/etc/retroshine/dolphin/${f}" "${CONFIG_DIR}/dolphin/Config/${f}"
    fi
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
if [ ! -f "${CONFIG_DIR}/es-de/ES-DE/settings/es_settings.xml" ]; then
    cp /etc/retroshine/es-de/settings/es_settings.xml \
       "${CONFIG_DIR}/es-de/ES-DE/settings/es_settings.xml"
fi
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
if [ ! -f "${CONFIG_DIR}/dusklight/config.json" ]; then
    cp /etc/retroshine/dusklight.json "${CONFIG_DIR}/dusklight/config.json"
fi

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
