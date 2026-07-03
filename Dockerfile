FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Base utilities; enable restricted + universe before the main install pass
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    wget \
    software-properties-common \
    gnupg \
    && add-apt-repository restricted \
    && add-apt-repository universe \
    && rm -rf /var/lib/apt/lists/*

# RetroArch PPA (more up-to-date than Ubuntu repos)
RUN add-apt-repository ppa:libretro/stable

RUN apt-get update && apt-get install -y \
    # Xorg with modesetting driver (DRI3 hardware-accelerated GL/Vulkan)
    # xserver-xorg-input-void dropped in Ubuntu 24.04; handled via AllowEmptyInput in xorg.conf
    xserver-xorg-core \
    xserver-xorg-input-libinput \
    x11-xserver-utils \
    x11-utils \
    xauth \
    # Audio
    pulseaudio \
    pulseaudio-utils \
    # Intel VAAPI — iHD for Gen12 / Alder Lake-N (N100)
    libva2 \
    libva-drm2 \
    intel-media-va-driver \
    mesa-va-drivers \
    # Vulkan — Intel ANV driver for hardware-accelerated rendering
    mesa-vulkan-drivers \
    libvulkan1 \
    vulkan-tools \
    # OpenGL (DRI3 / GLX)
    libgl1-mesa-dri \
    libglx-mesa0 \
    # RetroArch
    retroarch \
    # Flatpak for Dolphin (user-mode install; no flatpak-system-helper/systemd needed)
    flatpak \
    dbus \
    # Process manager
    supervisor \
    procps \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Dolphin Flatpak — system-wide install baked into the image at build time.
# Build locally (not on the NAS) where download speed is adequate.
ARG DOLPHIN_FLATPAK_URL="https://dl.dolphin-emu.org/releases/2606/dolphin-2606-x86_64.flatpak"
RUN wget -q "${DOLPHIN_FLATPAK_URL}" -O /tmp/dolphin.flatpak \
    && flatpak install --system --noninteractive --bundle /tmp/dolphin.flatpak \
    && rm /tmp/dolphin.flatpak

RUN printf '#!/bin/sh\nexec flatpak run --nosandbox org.DolphinEmu.dolphin-emu "$@"\n' \
        > /usr/local/bin/dolphin-emu \
    && chmod +x /usr/local/bin/dolphin-emu

# Dusklight — native AppImage extracted at build time (avoids FUSE requirement in Docker).
# AppRun sets APPDIR and LD_LIBRARY_PATH relative to the extraction directory.
# Saves land in ~/.local/share/TwilitRealm/Dusklight; entrypoint symlinks that to /config/dusklight.
ARG DUSKLIGHT_VERSION=1.4.1
RUN wget -q \
        "https://github.com/TwilitRealm/dusklight/releases/download/v${DUSKLIGHT_VERSION}/Dusklight-v${DUSKLIGHT_VERSION}-linux-x86_64.AppImage" \
        -O /tmp/dusklight.AppImage \
    && chmod +x /tmp/dusklight.AppImage \
    && cd /opt && /tmp/dusklight.AppImage --appimage-extract \
    && mv /opt/squashfs-root /opt/dusklight \
    && rm /tmp/dusklight.AppImage

RUN printf '#!/bin/sh\ncd /opt/dusklight && exec ./AppRun "$@"\n' \
        > /usr/local/bin/dusklight \
    && chmod +x /usr/local/bin/dusklight

# Install Sunshine from LizardByte GitHub releases.
# If the wget fails, check https://github.com/LizardByte/Sunshine/releases
# for the exact filename and override: --build-arg SUNSHINE_VERSION=<version>
ARG SUNSHINE_VERSION=2026.516.143833
RUN apt-get update \
    && wget -q \
        "https://github.com/LizardByte/Sunshine/releases/download/v${SUNSHINE_VERSION}/sunshine-ubuntu-24.04-amd64.deb" \
        -O /tmp/sunshine.deb \
    && apt-get install -y /tmp/sunshine.deb \
    && rm /tmp/sunshine.deb \
    && rm -rf /var/lib/apt/lists/*

# Baked-in default configs — entrypoint copies these to /config on first boot
COPY config/supervisord.conf        /etc/retroshine/supervisord.conf
COPY config/xorg.conf               /etc/retroshine/xorg.conf
COPY config/sunshine.conf           /etc/retroshine/sunshine.conf
COPY config/apps.json               /etc/retroshine/apps.json
COPY config/retroarch.cfg           /etc/retroshine/retroarch.cfg
COPY config/pulse.pa                /etc/retroshine/pulse.pa
COPY config/dolphin/Dolphin.ini     /etc/retroshine/dolphin/Dolphin.ini
COPY config/dolphin/GFX.ini         /etc/retroshine/dolphin/GFX.ini
COPY scripts/wait-for-x.sh         /usr/local/bin/wait-for-x.sh
COPY entrypoint.sh                  /entrypoint.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/wait-for-x.sh

# Sunshine network ports
EXPOSE 47984/tcp 47989/tcp 47990/tcp 47998/udp 47999/udp 48000/udp 48010/tcp

VOLUME ["/config"]

ENTRYPOINT ["/entrypoint.sh"]
