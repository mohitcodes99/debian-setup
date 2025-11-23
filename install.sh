#!/usr/bin/env bash
#
# install.sh - The Definitive Debian 13 i3 Workstation (Version 8.0 Final)
# Target: ASUS ROG Strix G17 | Features: Multimedia Keys | Firefox | Nvidia Safe
#
# INSTRUCTIONS:
# 1. Install Debian (Select "Standard System Utilities" ONLY. Root Password: EMPTY).
# 2. Login to TTY.
# 3. sudo apt install git
# 4. Clone your repo & Run.
#

set -euo pipefail
IFS=$'\n\t'

# --- Colors & Logging ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { printf "${BLUE}[%s]${NC} ${GREEN}%s${NC}\n" "$(date +'%H:%M:%S')" "$*"; }
warn() { printf "${BLUE}[%s]${NC} ${YELLOW}%s${NC}\n" "$(date +'%H:%M:%S')" "$*"; }
err() { printf "${BLUE}[%s]${NC} ${RED}%s${NC}\n" "$(date +'%H:%M:%S')" "$*"; }

log "Starting Final Desktop Setup..."

# --- 0. PRE-FLIGHT CHECKS ---

# Internet Check
if ! ping -c 1 google.com &> /dev/null; then
    err "Error: No Internet. Please connect via 'nmtui' or Ethernet cable."
    exit 1
fi

# Sudo Check
if ! command -v sudo &> /dev/null; then
    err "Error: 'sudo' is missing. You likely set a Root password during install."
    err "Fix: Su to root, 'apt install sudo', 'usermod -aG sudo youruser', reboot."
    exit 1
fi
sudo -v

# Apt Lock Wait (Prevents crash on fresh boot)
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    warn "Waiting for apt locks to clear..."
    sleep 2
done

# Backup Function
backup_file() {
    if [ -f "$1" ]; then
        mv "$1" "$1.bak.$(date +%s)"
        log "Backed up $1"
    fi
}

# ****************************************************************
# 1. REPOSITORIES & SYSTEM PREP
# ****************************************************************
log "Configuring Repositories & Upgrading..."

if ! command -v add-apt-repository >/dev/null 2>&1; then
    sudo apt update
    sudo apt install -y software-properties-common
fi

sudo add-apt-repository -y contrib
sudo add-apt-repository -y non-free
sudo add-apt-repository -y non-free-firmware

# CRITICAL: Update system headers/kernel before installing drivers
sudo apt update -y
sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y

# ****************************************************************
# 2. INSTALL PACKAGES
# ****************************************************************
PKGS=(
  # Desktop Core
  xorg xinit i3-wm i3status i3lock dmenu
  lightdm lightdm-gtk-greeter
  picom polybar rofi dunst
  kitty
  xserver-xorg-input-libinput # Touchpad gestures
  numlockx                    # Auto-enable Numpad
  
  # Apps
  thunar              # File Manager
  thunar-archive-plugin file-roller
  mousepad            # Text Editor
  evince              # PDF Viewer
  feh                 # Image/Wallpaper
  flameshot           # Screenshot Tool
  arandr              # Monitor GUI
  lxappearance        # Theme Switcher
  btop                # Activity Monitor
  galculator          # Calculator
  
  # Utilities
  network-manager network-manager-gnome blueman
  udiskie gvfs gvfs-backends
  copyq xclip brightnessctl
  curl wget git unzip build-essential jq
  xdg-user-dirs libdbus-glib-1-2
  
  # Hardware (ASUS/Intel Specifics)
  firmware-linux
  firmware-iwlwifi    # Intel AX201
  firmware-misc-nonfree
  
  # Audio/Power/Auth
  pipewire pipewire-pulse wireplumber pavucontrol
  tlp acpi upower mate-polkit policykit-1-gnome
)

log "Installing System Packages..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y "${PKGS[@]}"

# Detect CPU for Microcode (Intel i7-10750H)
if [ -f /proc/cpuinfo ]; then
    CPU_VENDOR=$(grep -m 1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
    if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
        log "Intel CPU detected. Installing Microcode..."
        sudo apt install -y intel-microcode
    elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
        sudo apt install -y amd64-microcode
    fi
fi

# Enable Services
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now tlp
sudo systemctl enable --now bluetooth
sudo systemctl unmask lightdm
sudo systemctl enable lightdm

# FIX: NetworkManager "Device not managed" bug
if [ -f /etc/NetworkManager/NetworkManager.conf ]; then
    sudo sed -i 's/managed=false/managed=true/g' /etc/NetworkManager/NetworkManager.conf
fi

xdg-user-dirs-update

# ****************************************************************
# 3. FIREFOX (Latest Official Binary)
# ****************************************************************
if command -v firefox >/dev/null 2>&1; then
    log "Firefox is already installed."
else
    echo ""
    warn "Firefox (Official) is not installed."
    # We use /dev/tty to ensure prompt works even if piped
    read -p "Do you want to install the latest official Mozilla Firefox? [y/N] " response < /dev/tty
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        log "Downloading latest Firefox..."
        cd /tmp
        wget -O firefox.tar.bz2 "https://download.mozilla.org/?product=firefox-latest&os=linux64&lang=en-US"
        
        log "Installing to /opt/firefox..."
        if [ -d /opt/firefox ]; then sudo rm -rf /opt/firefox; fi
        sudo tar xjf firefox.tar.bz2 -C /opt/
        
        log "Linking binary..."
        if [ -L /usr/bin/firefox ]; then sudo rm -f /usr/bin/firefox; fi
        sudo ln -s /opt/firefox/firefox /usr/bin/firefox
        
        log "Setting up Icon..."
        sudo cp /opt/firefox/browser/chrome/icons/default/default128.png /usr/share/pixmaps/firefox.png
        
        log "Creating Desktop Entry..."
        cat <<EOF | sudo tee /usr/share/applications/firefox.desktop
[Desktop Entry]
Name=Firefox
Comment=Web Browser
Exec=/opt/firefox/firefox %u
Terminal=false
Type=Application
Icon=firefox
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/vnd.mozilla.xul+xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;
StartupWMClass=firefox
EOF
        log "Firefox installed."
    else
        log "Skipping Firefox."
    fi
fi

# ****************************************************************
# 4. NVIDIA DRIVER
# ****************************************************************
log "Checking for Nvidia..."
# Install Headers Metapackage (Safest method for updates)
sudo apt install -y linux-headers-amd64

if apt-cache show nvidia-driver >/dev/null 2>&1; then
    log "Installing Nvidia Driver..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y nvidia-driver firmware-misc-nonfree
    NEED_REBOOT=true
else
    log "Nvidia driver not found. Skipping."
fi

# ****************************************************************
# 5. FONTS
# ****************************************************************
log "Installing Nerd Fonts..."
mkdir -p ~/.local/share/fonts
cd /tmp
wget -O JBM.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
unzip -o JBM.zip -d ~/.local/share/fonts
fc-cache -fv
cd -

# ****************************************************************
# 6. THEMES (Catppuccin All Variants)
# ****************************************************************
log "Installing Themes..."
sudo apt install -y papirus-icon-theme
mkdir -p ~/.themes

# Clone
git clone --depth=1 https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme.git /tmp/ct

# Copy ALL themes (Includes Yellow/Latte/Mocha)
cp -a /tmp/ct/themes/* ~/.themes/
rm -rf /tmp/ct

log "Downloading Wallpapers..."
mkdir -p ~/Pictures/wallpapers
wget -O ~/Pictures/wallpapers/forest_dark.jpg https://raw.githubusercontent.com/zhichaoh/Catppuccin-Wallpapers/main/Landscapes/Forrest.jpg
wget -O ~/Pictures/wallpapers/landscape_light.jpg https://raw.githubusercontent.com/zhichaoh/Catppuccin-Wallpapers/main/Landscapes/Beach.jpg

# Set Default to Dark (Mocha)
mkdir -p ~/.config/gtk-3.0
cat > ~/.config/gtk-3.0/settings.ini <<EOF
[Settings]
gtk-theme-name = Catppuccin-Mocha-Standard-Blue-Dark
gtk-icon-theme-name = Papirus-Dark
gtk-font-name = JetBrainsMono Nerd Font 10
EOF

# ****************************************************************
# 7. CONFIGS
# ****************************************************************

# --- Dynamic Polkit Agent Detection (Trixie Proof) ---
# We look for Mate first (stable), then Gnome (classic), then fallback.
if [ -f /usr/lib/mate-polkit/polkit-mate-authentication-agent-1 ]; then
    POLKIT_BIN="/usr/lib/mate-polkit/polkit-mate-authentication-agent-1"
elif [ -f /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 ]; then
    POLKIT_BIN="/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1"
elif [ -f /usr/libexec/polkit-gnome-authentication-agent-1 ]; then
    POLKIT_BIN="/usr/libexec/polkit-gnome-authentication-agent-1"
else
    # Last resort search
    POLKIT_BIN=$(find /usr -name "polkit-gnome-authentication-agent-1" 2>/dev/null | head -n 1)
fi
log "Polkit agent detected: $POLKIT_BIN"

# --- Picom ---
mkdir -p ~/.config/picom
cat > ~/.config/picom/picom.conf <<EOF
backend = "glx";
vsync = true;
fading = true;
fade-in-step = 0.03;
fade-out-step = 0.03;
shadow = true;
shadow-radius = 12;
corner-radius = 10;
EOF

# --- Kitty (Theming) ---
mkdir -p ~/.config/kitty
backup_file ~/.config/kitty/kitty.conf
cat > ~/.config/kitty/kitty.conf <<EOF
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
cursor_text_color       #1E1E2E
url_color               #F5E0DC
active_border_color     #B4BEFE
inactive_border_color   #6C7086
bell_border_color       #F9E2AF
tab_bar_background      #11111B
EOF

# --- Rofi (Theming) ---
mkdir -p ~/.config/rofi
backup_file ~/.config/rofi/config.rasi
cat > ~/.config/rofi/config.rasi <<EOF
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

# --- Polybar ---
mkdir -p ~/.config/polybar
backup_file ~/.config/polybar/config.ini
cat > ~/.config/polybar/config.ini <<EOF
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
label-unfocused = %index%
label-unfocused-padding = 1

[module/pulseaudio]
type = internal/pulseaudio
format-volume = <ramp-volume> <label-volume>
ramp-volume-0 = 
ramp-volume-1 = 
ramp-volume-2 = 
label-muted =  muted

[module/date]
type = internal/date
interval = 1
format =  %H:%M   %a %d

[module/tray]
type = internal/tray
EOF

# --- i3 Config ---
mkdir -p ~/.config/i3
backup_file ~/.config/i3/config
cat > ~/.config/i3/config <<EOF
set \$mod Mod4
font pango:JetBrainsMono Nerd Font 10

# --- Keybindings (Omarchy Style + Ctrl Space) ---

# 1. Launcher (Ctrl + Space)
bindsym Control+space exec "rofi -show drun -show-icons"

# 2. Applications
bindsym \$mod+Return exec kitty                        # Terminal
bindsym \$mod+b exec firefox                           # Browser
bindsym \$mod+Shift+f exec thunar                      # File Manager
bindsym \$mod+Shift+t exec kitty -e btop               # Activity Monitor

# 3. Window Management
bindsym \$mod+w kill                                   # Close Window
bindsym \$mod+f fullscreen toggle                      # Fullscreen
bindsym \$mod+t floating toggle                        # Toggle Float/Tile
bindsym \$mod+Shift+space floating toggle              # Alternate Float

# 4. Navigation
bindsym \$mod+Left focus left
bindsym \$mod+Down focus down
bindsym \$mod+Up focus up
bindsym \$mod+Right focus right

bindsym \$mod+Shift+Left move left
bindsym \$mod+Shift+Down move down
bindsym \$mod+Shift+Up move up
bindsym \$mod+Shift+Right move right

# 5. Workspaces
bindsym \$mod+1 workspace 1
bindsym \$mod+2 workspace 2
bindsym \$mod+3 workspace 3
bindsym \$mod+4 workspace 4

bindsym \$mod+Shift+1 move container to workspace 1
bindsym \$mod+Shift+2 move container to workspace 2
bindsym \$mod+Shift+3 move container to workspace 3
bindsym \$mod+Shift+4 move container to workspace 4

# 6. System
bindsym \$mod+Escape exec "i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit'"
bindsym \$mod+Shift+r restart
bindsym \$mod+Shift+c reload

# 7. Utilities
bindsym Print exec flameshot gui                       # Screenshot
bindsym \$mod+Shift+s exec flameshot gui                # Alternate Screenshot

# 8. Hardware Keys (Laptop Multimedia)
bindsym XF86AudioRaiseVolume exec pactl set-sink-volume @DEFAULT_SINK@ +5%
bindsym XF86AudioLowerVolume exec pactl set-sink-volume @DEFAULT_SINK@ -5%
bindsym XF86AudioMute exec pactl set-sink-mute @DEFAULT_SINK@ toggle
bindsym XF86MonBrightnessUp exec brightnessctl s +5%
bindsym XF86MonBrightnessDown exec brightnessctl s 5%-

# --- Autostart ---
exec_always --no-startup-id picom --config ~/.config/picom/picom.conf
exec_always --no-startup-id killall -q polybar; sleep 1; polybar main
exec_always --no-startup-id feh --bg-fill ~/Pictures/wallpapers/forest_dark.jpg
exec --no-startup-id xrandr --auto  # Force 144Hz
exec --no-startup-id numlockx on    # Enable Numpad

exec --no-startup-id nm-applet
exec --no-startup-id blueman-applet
exec --no-startup-id udiskie -t
exec --no-startup-id copyq
exec --no-startup-id $POLKIT_BIN

# Theme
default_border pixel 2
client.focused #89b4fa #89b4fa #1e1e2e #89b4fa #89b4fa
EOF

# ****************************************************************
# DONE
# ****************************************************************
# Force icon cache update one last time
sudo gtk-update-icon-cache /usr/share/icons/Papirus || true

log "Setup Complete."

if [[ "${NEED_REBOOT:-false}" == true ]]; then
    log "NVIDIA Drivers installed. Rebooting in 5 seconds..."
    sleep 5
    sudo reboot
else
    sudo systemctl enable --now lightdm
    echo "Done. LightDM enabled. Type 'sudo reboot' to start."
fi
