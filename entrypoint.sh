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
    "${CONFIG_DIR}/es-de/settings" \
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

# ── ES-DE config → /config volume ────────────────────────────────────────
mkdir -p /root/.config
ln -sfn "${CONFIG_DIR}/es-de" /root/.config/ES-DE
if [ ! -f "${CONFIG_DIR}/es-de/settings/es_settings.xml" ]; then
    cp /etc/retroshine/es-de/settings/es_settings.xml \
       "${CONFIG_DIR}/es-de/settings/es_settings.xml"
fi

# ── Sunshine covers → /config volume ─────────────────────────────────────
# Dusklight writes its built-in cover art here; symlink keeps it persistent.
mkdir -p /root/.config/sunshine
ln -sfn "${CONFIG_DIR}/sunshine/covers" /root/.config/sunshine/covers

# ── Dusklight saves → /config volume ─────────────────────────────────────
mkdir -p /root/.local/share/TwilitRealm
ln -sfn "${CONFIG_DIR}/dusklight" /root/.local/share/TwilitRealm/Dusklight

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
