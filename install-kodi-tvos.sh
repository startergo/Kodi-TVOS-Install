#!/bin/bash

# Kodi tvOS Installation Script
# Prepares Kodi .deb file for installation on non-jailbroken Apple TV
# Requires: dpkg, iOS App Signer, Xcode, Apple Developer Account

set -e

echo "================================================"
echo "  Kodi tvOS Installation Helper"
echo "================================================"
echo ""

# Configuration
DEB_FILE=""
EXTRACT_DIR="$HOME/kodi-extracted"
OUTPUT_DIR="$HOME/Desktop"

# Auto-detect .deb file in Downloads
echo "Searching for Kodi .deb file in Downloads..."
DEB_FILES=($(ls "$HOME/Downloads/"*kodi*.deb 2>/dev/null))

if [ ${#DEB_FILES[@]} -eq 0 ]; then
    echo "ERROR: No Kodi .deb file found in Downloads folder"
    echo ""
    echo "Download Kodi tvOS .deb from:"
    echo "  https://kodi.tv/download/tvos/"
    echo ""
    echo "Direct link:"
    echo "  https://mirrors.kodi.tv/releases/darwin/tvos/org.xbmc.kodi-tvos_21.2-tvos.deb?https=1"
    echo ""
    echo "After downloading, run this script again."
    exit 1
elif [ ${#DEB_FILES[@]} -eq 1 ]; then
    DEB_FILE="${DEB_FILES[0]}"
    echo "✓ Found: $(basename "$DEB_FILE")"
else
    echo "Multiple Kodi .deb files found:"
    for i in "${!DEB_FILES[@]}"; do
        echo "  $((i+1)). $(basename "${DEB_FILES[$i]}")"
    done
    echo ""
    read -p "Select file number (1-${#DEB_FILES[@]}): " selection
    DEB_FILE="${DEB_FILES[$((selection-1))]}"
fi

# Check if dpkg is available
if ! command -v dpkg-deb &> /dev/null; then
    echo "ERROR: dpkg-deb not found. Install it with: brew install dpkg"
    exit 1
fi

# Check if .deb file exists
if [ ! -f "$DEB_FILE" ]; then
    echo "ERROR: Kodi .deb file not found at: $DEB_FILE"
    echo "Please download it first or update the DEB_FILE path in this script."
    exit 1
fi

echo "✓ Found Kodi .deb file: $DEB_FILE"
echo ""

# Step 1: Extract .deb
echo "Step 1: Extracting .deb file..."
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
dpkg-deb -R "$DEB_FILE" "$EXTRACT_DIR"
echo "✓ Extracted to: $EXTRACT_DIR"
echo ""

# Step 2: Remove PlugIns folder
echo "Step 2: Removing PlugIns folder (avoids bundle ID conflicts)..."
if [ -d "$EXTRACT_DIR/Applications/Kodi.app/PlugIns" ]; then
    rm -rf "$EXTRACT_DIR/Applications/Kodi.app/PlugIns"
    echo "✓ PlugIns folder removed"
else
    echo "✓ No PlugIns folder found"
fi
echo ""

# Step 3: Create IPA
echo "Step 3: Creating unsigned IPA package..."
mkdir -p "$OUTPUT_DIR/Payload"
cp -r "$EXTRACT_DIR/Applications/Kodi.app" "$OUTPUT_DIR/Payload/"

cd "$OUTPUT_DIR"
rm -f Kodi-unsigned.ipa
zip -qr Kodi-unsigned.ipa Payload
rm -rf Payload

echo "✓ Created: $OUTPUT_DIR/Kodi-unsigned.ipa"
echo ""

echo "================================================"
echo "  PREPARATION COMPLETE!"
echo "================================================"
echo ""
echo "Unsigned IPA: $OUTPUT_DIR/Kodi-unsigned.ipa"
echo ""
echo "NEXT STEPS:"
echo ""
echo "═══════════════════════════════════════════════"
echo "1. SIGN THE IPA"
echo "═══════════════════════════════════════════════"
echo ""
echo "   a) Download iOS App Signer:"
echo "      https://dantheman827.github.io/ios-app-signer/"
echo ""
echo "   b) In iOS App Signer:"
echo "      • Input File: $OUTPUT_DIR/Kodi-unsigned.ipa"
echo "      • Signing Certificate: Apple Distribution: Your Name"
echo "      • Provisioning Profile: Your Kodi provisioning profile"
echo "      • Click 'Start'"
echo "      • Save as: $OUTPUT_DIR/Kodi-signed.ipa"
echo ""
echo "═══════════════════════════════════════════════"
echo "2. INSTALL TO APPLE TV"
echo "═══════════════════════════════════════════════"
echo ""
echo "   a) Make sure Apple TV is awake and unlocked"
echo ""
echo "   b) In Xcode:"
echo "      • Window → Devices and Simulators (⌘⇧2)"
echo "      • Select your Apple TV from the list"
echo "      • Click '+' button under 'INSTALLED APPS'"
echo "      • Select: $OUTPUT_DIR/Kodi-signed.ipa"
echo "      • Wait for installation to complete"
echo ""
echo "   c) Kodi will appear on your Apple TV home screen!"
echo ""
echo "================================================"
echo ""
