#!/bin/bash
# install_no_root.sh - Install non-root Android forensic toolkit in Termux

echo "[*] Updating packages..."
pkg update -y && pkg upgrade -y

echo "[*] Installing dependencies..."
pkg install -y git python python3 python-pip wget curl \
    sqlite openssh termux-api libusb binutils

echo "[*] Installing Python tools..."
pip install protobuf pyusb

echo "[*] Installing termux-adb (patched for non-root USB)..."
curl -s https://raw.githubusercontent.com/nohajc/termux-adb/master/install.sh | bash

echo "[*] Cloning tools..."
cd $HOME
git clone https://github.com/nelenkov/android-backup-extractor.git
cd android-backup-extractor && pip install . && cd $HOME

echo "[*] Storage permissions..."
termux-setup-storage

echo "[+] Ready! Connect target via USB-C OTG and run: bash extract_no_root.sh"
