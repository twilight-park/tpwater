#!/bin/sh
# lepotato-kiosk.sh — configure Armbian Xfce Le Potato as a tpwater kiosk
# Run as the kiosk user (john) with passwordless sudo.
#
# Usage:
#   ./lepotato-kiosk.sh [setup [URL]]   — full kiosk setup (default)
#   ./lepotato-kiosk.sh overlay up      — enable read-only rootfs overlay
#   ./lepotato-kiosk.sh overlay down    — disable overlay (writable rootfs)

CMD="${1:-setup}"
URL="${2:-https://tpwater.rkroll.com}"
USER="$(whoami)"

case "$CMD" in

  setup)
    echo "Configuring kiosk for user=$USER url=$URL"

    # --- autologin via LightDM ---
    sudo tee /etc/lightdm/lightdm.conf.d/12-autologin.conf > /dev/null << EOF
[Seat:*]
autologin-user=$USER
autologin-user-timeout=0
EOF
    echo "autologin configured"

    # --- overlayroot for read-only rootfs support ---
    sudo apt-get install -y overlayroot > /dev/null
    echo "overlayroot installed"

    # --- hide cursor at idle ---
    sudo apt-get install -y unclutter > /dev/null
    echo "unclutter installed"

    # --- Xfce autostart: disable screensaver + launch chromium kiosk ---
    mkdir -p ~/.config/autostart
    cat > ~/.config/autostart/kiosk-chromium.desktop << EOF
[Desktop Entry]
Type=Application
Name=Kiosk Chromium
Exec=bash -c 'xset s off; xset -dpms; xset s noblank; unclutter -idle 1 & sleep 10; chromium --kiosk --noerrdialogs --disable-infobars --disable-translate --check-for-update-interval=31536000 $URL'
X-GNOME-Autostart-enabled=true
EOF
    echo "autostart entry created"

    echo "Done. Reboot to start kiosk: sudo reboot"
    ;;

  overlay)
    SUBCMD="${2:-}"
    case "$SUBCMD" in
      up)
        echo "Enabling read-only rootfs overlay..."
        # Use overlayroot-chroot if already in overlay mode, else write directly
        if [ -x "$(command -v overlayroot-chroot)" ] && grep -q overlay /proc/mounts 2>/dev/null; then
            sudo overlayroot-chroot sh -c 'echo overlayroot=\"tmpfs\" >> /etc/overlayroot.conf'
        else
            sudo apt-get install -y overlayroot > /dev/null
            sudo sh -c 'echo overlayroot=\"tmpfs\" >> /etc/overlayroot.conf'
        fi
        echo "Overlay enabled. Reboot to activate: sudo reboot"
        ;;
      down)
        echo "Disabling rootfs overlay..."
        sudo overlayroot-chroot sh -c 'echo overlayroot=\"\" > /etc/overlayroot.conf'
        echo "Overlay disabled. Reboot to return to writable rootfs: sudo reboot"
        ;;
      *)
        echo "Usage: $0 overlay up|down" >&2
        exit 1
        ;;
    esac
    ;;

  *)
    echo "Usage: $0 [setup [URL] | overlay up | overlay down]" >&2
    exit 1
    ;;

esac
