#!/bin/sh
# lepotato-kiosk.sh — configure Armbian Xfce Le Potato as a tpwater kiosk
# Run as the kiosk user (john) with sudo access.
# Usage: ./lepotato-kiosk.sh [URL]
# Default URL: https://tpwater.rkroll.com

URL="${1:-https://tpwater.rkroll.com}"
USER="$(whoami)"

echo "Configuring kiosk for user=$USER url=$URL"

# --- autologin via LightDM ---
sudo tee /etc/lightdm/lightdm.conf.d/12-autologin.conf > /dev/null << EOF
[Seat:*]
autologin-user=$USER
autologin-user-timeout=0
EOF
echo "autologin configured"

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
