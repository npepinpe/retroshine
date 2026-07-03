#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR=/config

# ── Directories ──────────────────────────────────────────────────────────────
mkdir -p \
    "${CONFIG_DIR}/sunshine" \
    "${CONFIG_DIR}/retroarch/saves" \
    "${CONFIG_DIR}/retroarch/states" \
    "${CONFIG_DIR}/retroarch/screenshots" \
    "${CONFIG_DIR}/retroarch/cores" \
    "${CONFIG_DIR}/retroarch/info" \
    "${CONFIG_DIR}/dolphin/Config" \
    "${CONFIG_DIR}/logs" \
    /tmp/runtime/pulse
chmod 700 /tmp/runtime

# ── Seed default configs (only on first boot) ─────────────────────────────
for f in sunshine.conf apps.json; do
    if [ ! -f "${CONFIG_DIR}/sunshine/${f}" ]; then
        cp "/etc/retroshine/${f}" "${CONFIG_DIR}/sunshine/${f}"
    fi
done

if [ ! -f "${CONFIG_DIR}/retroarch/retroarch.cfg" ]; then
    cp /etc/retroshine/retroarch.cfg "${CONFIG_DIR}/retroarch/retroarch.cfg"
fi

for f in Dolphin.ini GFX.ini; do
    if [ ! -f "${CONFIG_DIR}/dolphin/Config/${f}" ]; then
        cp "/etc/retroshine/dolphin/${f}" "${CONFIG_DIR}/dolphin/Config/${f}"
    fi
done

# ── Sunshine credentials ──────────────────────────────────────────────────
# Set via SUNSHINE_USER / SUNSHINE_PASS env vars.
# --creds writes a bcrypt-hashed entry to the credentials file and exits.
SUNSHINE_USER="${SUNSHINE_USER:-admin}"
SUNSHINE_PASS="${SUNSHINE_PASS:-changeme}"

/usr/bin/sunshine \
    --creds "${SUNSHINE_USER}" "${SUNSHINE_PASS}" \
    || true   # non-fatal if credentials are already set

# ── VAAPI / Intel driver ──────────────────────────────────────────────────
export LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-iHD}"

# ── PulseAudio: ensure module-native-protocol-unix socket dir exists ──────
export PULSE_RUNTIME_PATH=/tmp/runtime/pulse

# ── Exec supervisord ──────────────────────────────────────────────────────
exec /usr/bin/supervisord -c /etc/retroshine/supervisord.conf
