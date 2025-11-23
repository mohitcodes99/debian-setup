#!/usr/bin/env bash
#
# install.sh - The Definitive Debian 13 i3 Workstation (Final Verified)
# Target: ASUS ROG Strix G17
# Fixes: broken repos, polkit paths, permissions, nvidia headers
#
# INSTRUCTIONS:
# 1. Install Debian (Root Password: EMPTY)
# 2. Login to TTY
# 3. sudo apt install git
# 4. Clone & Run.
#

set -euo pipefail
IFS=$'\n\t'

# --- Colors ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { printf "${BLUE}[%s]${NC} ${GREEN}%s${NC}\n" "$(date +'%H:%M:%S')" "$*"; }
err() { printf "${BLUE}[%s]${NC} ${RED}%s${NC}\n" "$(date +'%H:%M:%S')" "$*"; }

log "Starting Final Setup..."

# 1. SAFETY CHECKS
# -----------------
# Ensure we are running as root via sudo
if [ "$EUID" -ne 0 ]; then
    err "Please run with sudo: sudo ./install.sh"
    exit 1
fi

# Ensure we know who the real user is (to avoid root-owned config files)
if [ -z "${SUDO_USER:-}" ]; then
    err "Could not detect sudo user. Are you logged in as root? Log in as a normal user and use sudo."
    exit 1
fi

# Internet Check
if ! ping -c 1 google.com &> /dev/null; then
    err "Error: No Internet. Connect via Ethernet or run 'nmtui'."
    exit 1
fi

# 2. FIX REPOSITORIES (The "Nuclear" Fix)
# -----------------
# We overwrite sources.list to guarantee the system can find packages.
log "Fixing Repositories..."
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
EOF

log "Updating Package Lists..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# 3. INSTALL PACKAGES
# -----------------
PKGS=(
  # Core
  xorg xinit i3-wm i3status i3lock dmenu
  lightdm lightdm-gtk-greeter
  picom polybar rofi dunst
  kitty
  xserver-xorg-input-libinput # Touchpad
  numlockx                    # Numpad
  
  # Apps
  thunar thunar-archive-plugin file-roller
  mousepad evince feh flameshot arandr
  lxappearance btop galculator
  
  # Utils
  network-manager network-manager-gnome blueman
  udiskie gvfs gvfs-backends
  copyq xclip brightnessctl
  curl wget git unzip build-essential jq
  xdg-user-dirs libdbus-glib-1-2
  
  # Hardware (ASUS/Intel)
  firmware-linux firmware-iwlwifi firmware-misc-nonfree
  
  # Audio/Power/Auth
  pipewire pipewire-pulse wireplumber pavucontrol
  tlp acpi upower mate-polkit policykit-1-gnome
)

log "Installing System Packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y "${PKGS[@]}"

# 4. MICROCODE & SERVICES
# -----------------
if [ -f /proc/cpuinfo ]; then
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        apt-get install -y intel-microcode
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        apt-get install -y amd64-microcode
    fi
fi

systemctl enable --now NetworkManager
systemctl enable --now tlp
systemctl enable --now bluetooth
systemctl unmask lightdm
systemctl enable lightdm

# Fix "Device not managed"
if [ -f /etc/NetworkManager/NetworkManager.conf ]; then
    sed -i 's/managed=false/managed=true/g' /etc/NetworkManager/NetworkManager.conf
fi

# 5. FIREFOX INSTALLER
# -----------------
if ! command -v firefox >/dev/null 2>&1; then
    log "Installing Official Firefox..."
    cd /tmp
    wget -O firefox.tar.bz2 "https://download.mozilla.org/?product=firefox-latest&os=linux64&lang=en-US"
    tar xjf firefox.tar.bz2 -C /opt/
    ln -sf /opt/firefox/firefox /usr/bin/firefox
    
    # Copy icon
    cp /opt/firefox/browser/chrome/icons/default/default128.png /usr/share/pixmaps/firefox.png
    
    cat > /usr/share/applications/firefox.desktop <<EOF
[Desktop Entry]
Name=Firefox
Comment=Web Browser
Exec=/opt/firefox/firefox %u
Terminal=false
Type=Application
Icon=firefox
Categories=Network;WebBrowser;
StartupWMClass=firefox
EOF
fi

# 6. NVIDIA DRIVERS
# -----------------
log "Installing Nvidia Drivers..."
# Metapackage ensures we always have headers for the latest kernel
apt-get install -y linux-headers-amd64
apt-get install -y nvidia-driver firmware-misc-nonfree

# 7. THEMES & FONTS
# -----------------
log "Configuring Visuals..."
USER_HOME="/home/$SUDO_USER"

mkdir -p "$USER_HOME/.local/share/fonts"
mkdir -p "$USER_HOME/.themes"
mkdir -p "$USER_HOME/.config"
mkdir -p "$USER_HOME/Pictures/wallpapers"

# Fonts
cd /tmp
wget -O JBM.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
unzip -o JBM.zip -d "$USER_HOME/.local/share/fonts"
fc-cache -fv

# Themes
apt-get install -y papirus-icon-theme
git clone --depth=1 https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme.git /tmp/ct
cp -a /tmp/ct/themes/* "$USER_HOME/.themes/"
rm -rf /tmp/ct

# Wallpapers
wget -O "$USER_HOME/Pictures/wallpapers/forest.jpg" https://raw.githubusercontent.com/zhichaoh/Catppuccin-Wallpapers/main/Landscapes/Forrest.jpg

# 8. DYNAMIC CONFIGURATION
# -----------------

# Find the correct Polkit Agent (Crucial for GUI Root apps)
if [ -f /usr/lib/mate-polkit/polkit-mate-authentication-agent-1 ]; then
    POLKIT_BIN="/usr/lib/mate-polkit/polkit-mate-authentication-agent-1"
elif [ -f /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 ]; then
    POLKIT_BIN="/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1"
elif [ -f /usr/libexec/polkit-gnome-authentication-agent-1 ]; then
    POLKIT_BIN="/usr/libexec/polkit-gnome-authentication-agent-1"
else
    POLKIT_BIN=$(find /usr -name "polkit-gnome-authentication-agent-1" 2>/dev/null | head -n 1)
fi
log "Polkit Agent found: $POLKIT_BIN"

# GTK
mkdir -p "$USER_HOME/.config/gtk-3.0"
cat > "$USER_HOME/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name = Catppuccin-Mocha-Standard-Blue-Dark
gtk-icon-theme-name = Papirus-Dark
gtk-font-name = JetBrainsMono Nerd Font 10
EOF

# Picom
mkdir -p "$USER_HOME/.config/picom"
cat > "$USER_HOME/.config/picom/picom.conf" <<EOF
backend = "glx";
vsync = true;
fading = true;
fade-in-step = 0.03;
fade-out-step = 0.03;
shadow = true;
shadow-radius = 12;
corner-radius = 10;
EOF

# Kitty
mkdir -p "$USER_HOME/.config/kitty"
cat > "$USER_HOME/.config/kitty/kitty.conf" <<EOF
font_family      JetBrainsMono Nerd Font
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size 11.0
background_opacity 0.95
foreground              #CDD6F4
background              #1E1E2E
selection_foreground    #1E1E2E
selection_background    #F5E0DC
cursor                  #F5E0DC
EOF

# Rofi
mkdir -p "$USER_HOME/.config/rofi"
cat > "$USER_HOME/.config/rofi/config.rasi" <<EOF
configuration {
  modi: "drun";
  font: "JetBrainsMono Nerd Font 12";
  show-icons: true;
  icon-theme: "Papirus";
}
@theme "sidebar"
window {
    width: 30%;
    border: 2px;
    border-color: #89b4fa;
}
EOF

# Polybar
mkdir -p "$USER_HOME/.config/polybar"
cat > "$USER_HOME/.config/polybar/config.ini" <<EOF
[bar/main]
width = 100%
height = 32
background = #1e1e2e
foreground = #cdd6f4
font-0 = "JetBrainsMono Nerd Font:size=10;2"
modules-left = i3
modules-right = pulseaudio date tray
padding-right = 1
[module/i3]
type = internal/i3
label-focused = %index%
label-focused-background = #313244
label-focused-underline = #89b4fa
label-focused-padding = 1
[module/pulseaudio]
type = internal/pulseaudio
format-volume = <ramp-volume> <label-volume>
ramp-volume-0 = 
ramp-volume-1 = 
ramp-volume-2 = 
[module/date]
type = internal/date
interval = 1
format =  %H:%M   %a %d
[module/tray]
type = internal/tray
EOF

# i3 Config
mkdir -p "$USER_HOME/.config/i3"
cat > "$USER_HOME/.config/i3/config" <<EOF
set \$mod Mod4
font pango:JetBrainsMono Nerd Font 10

bindsym Control+space exec "rofi -show drun -show-icons"
bindsym \$mod+Return exec kitty
bindsym \$mod+b exec firefox
bindsym \$mod+Shift+f exec thunar
bindsym \$mod+Shift+t exec kitty -e btop
bindsym \$mod+w kill
bindsym \$mod+f fullscreen toggle
bindsym \$mod+t floating toggle
bindsym \$mod+Shift+space floating toggle

bindsym \$mod+Left focus left
bindsym \$mod+Down focus down
bindsym \$mod+Up focus up
bindsym \$mod+Right focus right

bindsym \$mod+Shift+Left move left
bindsym \$mod+Shift+Down move down
bindsym \$mod+Shift+Up move up
bindsym \$mod+Shift+Right move right

bindsym \$mod+1 workspace 1
bindsym \$mod+2 workspace 2
bindsym \$mod+3 workspace 3
bindsym \$mod+4 workspace 4

bindsym \$mod+Shift+1 move container to workspace 1
bindsym \$mod+Shift+2 move container to workspace 2
bindsym \$mod+Shift+3 move container to workspace 3
bindsym \$mod+Shift+4 move container to workspace 4

bindsym \$mod+Escape exec "i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit'"
bindsym \$mod+Shift+r restart
bindsym \$mod+Shift+c reload

bindsym Print exec flameshot gui
bindsym XF86AudioRaiseVolume exec pactl set-sink-volume @DEFAULT_SINK@ +5%
bindsym XF86AudioLowerVolume exec pactl set-sink-volume @DEFAULT_SINK@ -5%
bindsym XF86AudioMute exec pactl set-sink-mute @DEFAULT_SINK@ toggle
bindsym XF86MonBrightnessUp exec brightnessctl s +5%
bindsym XF86MonBrightnessDown exec brightnessctl s 5%-

exec_always --no-startup-id picom --config ~/.config/picom/picom.conf
exec_always --no-startup-id killall -q polybar; sleep 1; polybar main
exec_always --no-startup-id feh --bg-fill ~/Pictures/wallpapers/forest.jpg
exec --no-startup-id xrandr --auto
exec --no-startup-id numlockx on
exec --no-startup-id nm-applet
exec --no-startup-id blueman-applet
exec --no-startup-id udiskie -t
exec --no-startup-id copyq
exec --no-startup-id $POLKIT_BIN

default_border pixel 2
client.focused #89b4fa #89b4fa #1e1e2e #89b4fa #89b4fa
EOF

# 9. PERMISSIONS & FINISH
# -----------------
log "Applying Permissions..."
chown -R $SUDO_USER:$SUDO_USER "$USER_HOME/.config"
chown -R $SUDO_USER:$SUDO_USER "$USER_HOME/.local"
chown -R $SUDO_USER:$SUDO_USER "$USER_HOME/.themes"
chown -R $SUDO_USER:$SUDO_USER "$USER_HOME/Pictures"

# Force icon cache update
if [ -d /usr/share/icons/Papirus ]; then
    gtk-update-icon-cache /usr/share/icons/Papirus || true
fi

log "Setup Complete! Rebooting in 5 seconds..."
sleep 5
reboot
