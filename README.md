# Debian 13 i3 Workstation (ROG Strix Edition)

A fully automated, "Golden Master" shell script to transform a fresh **Debian 13 (Trixie/Testing)** minimal install into a polished, production-ready **i3 Window Manager** environment.

Designed specifically for the **ASUS ROG Strix G17** (Intel 10th Gen + NVIDIA GTX 1660 Ti), but compatible with most modern laptops and desktops.

![Debian i3 Catppuccin](https://github.com/catppuccin/i3/raw/main/assets/preview.png)
*(Theme Preview: Catppuccin Mocha)*

## ✨ Features

* **Core:** i3-wm, Polybar, Rofi, Dunst, Picom (Compositor).
* **Terminal:** Kitty (GPU accelerated, fully themed).
* **Browser:** Interactive installer for **Official Firefox Latest** (not the old ESR).
* **Visuals:** Pre-configured **Catppuccin Mocha** (Dark) & **Latte** (Light) themes.
* **Drivers:** Auto-installs **NVIDIA Proprietary Drivers** (with Kernel Headers protection).
* **Hardware:** Optimizations for 144Hz screens, Intel WiFi 6 (AX201), and Touchpad gestures.
* **Workflow:** "Omarchy" style keybindings (DHH inspired) for maximum productivity.

## ⚠️ Pre-Requisites (READ CAREFULLY)

To ensure the script runs successfully, you **must** install Debian using these exact steps:

1.  **Download:** Debian Netinst ISO (Standard / Non-free firmware version).
2.  **Root Password:** **LEAVE EMPTY**.
    * *Why?* If you set a root password, the installer does not install `sudo`, and your user cannot run admin commands. Leaving it empty grants your user sudo rights automatically.
3.  **Software Selection:**
    * [ ] Debian Desktop Environment
    * [ ] GNOME / XFCE / KDE (Uncheck all)
    * [x] **Standard System Utilities** (Check ONLY this)

## 🚀 Installation

1.  Log into your fresh Debian TTY (Black screen).
2.  Ensure you have an internet connection (`ping google.com`).
3.  Run the following commands:

```bash
# 1. Install Git
sudo apt update && sudo apt install -y git

# 2. Clone and Run
git clone [https://github.com/mohitcodes99/debian-setup.git](https://github.com/mohitcodes99/debian-setup.git)
cd debian-setup
chmod +x install.sh
./install.sh
