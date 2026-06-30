#!/usr/bin/env bash
# Block until the X server on DISPLAY=:1 is ready to accept connections.
export DISPLAY=:1
until xset q &>/dev/null; do
    sleep 0.5
done
exec "$@"
