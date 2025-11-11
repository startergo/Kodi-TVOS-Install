# Installing Kodi on Non-Jailbroken Apple TV

Complete guide for installing Kodi from a .deb file onto a non-jailbroken Apple TV using a paid Apple Developer account.

## Prerequisites

### Required Software
- **macOS** with Xcode installed
- **Homebrew** (for installing dpkg)
- **dpkg** - Install with: `brew install dpkg`
- **iOS App Signer** - Download from: https://dantheman827.github.io/ios-app-signer/
- **Xcode** with command line tools

### Required Accounts/Hardware
- **Paid Apple Developer Account** ($99/year)
- **Apple TV** (non-jailbroken, connected to same network as Mac)
- **Kodi .deb file** for tvOS - Download from Kodi's website

## Setup: Apple Developer Portal

### 1. Register Your Apple TV Device

1. Get your Apple TV's UDID:
   - Open Xcode
   - Window → Devices and Simulators (⌘⇧2)
   - Connect Apple TV (via WiFi or Ethernet on same network)
   - Copy the "Identifier" (UDID)

2. Register device on Apple Developer:
   - Go to: https://developer.apple.com/account/resources/devices
   - Click "+" to add device
   - Select "Apple TV"
   - Enter name and UDID
   - Click "Continue"

### 2. Create Distribution Certificate

1. Go to: https://developer.apple.com/account/resources/certificates
2. Click "+" to create certificate
3. Select "Apple Distribution"
4. Follow prompts to create Certificate Signing Request (CSR) in Keychain Access
5. Upload CSR and download certificate
6. Double-click downloaded certificate to install in Keychain

### 3. Create Provisioning Profile

1. Go to: https://developer.apple.com/account/resources/profiles
2. Click "+" to create profile
3. Select "tvOS Ad Hoc"
4. Select or create App ID (e.g., `com.yourusername.kodi`)
5. Select your certificate
6. Select your Apple TV device
7. Download the `.mobileprovision` file

## Installation Steps

### Method 1: Using the Script (Recommended)

1. **Download the script:**
   ```bash
   # Script is at: ~/install-kodi-tvos.sh
   ```

2. **Edit the script** if needed to update paths:
   ```bash
   nano ~/install-kodi-tvos.sh
   # Update DEB_FILE path if different
   ```

3. **Run the script:**
   ```bash
   ~/install-kodi-tvos.sh
   ```

4. **Follow the on-screen instructions** to sign and install

### Method 2: Manual Installation

#### Step 1: Extract the .deb File

```bash
# Create extraction directory
mkdir -p ~/kodi-extracted

# Extract .deb file
dpkg-deb -R ~/Downloads/org.xbmc.kodi-tvos_*.deb ~/kodi-extracted
```

#### Step 2: Remove PlugIns Folder

```bash
# Remove to avoid bundle ID conflicts
rm -rf ~/kodi-extracted/Applications/Kodi.app/PlugIns
```

#### Step 3: Create Unsigned IPA

```bash
# Create Payload directory
mkdir -p ~/Desktop/Payload

# Copy Kodi.app
cp -r ~/kodi-extracted/Applications/Kodi.app ~/Desktop/Payload/

# Create IPA
cd ~/Desktop
zip -qr Kodi-unsigned.ipa Payload
rm -rf Payload
```

#### Step 4: Sign with iOS App Signer

1. Open **iOS App Signer**
2. **Input File**: Select `~/Desktop/Kodi-unsigned.ipa`
3. **Signing Certificate**: Select "Apple Distribution: Your Name"
4. **Provisioning Profile**: Select your downloaded `.mobileprovision` file
5. Click **"Start"**
6. Save as `Kodi-signed.ipa`

#### Step 5: Create Xcode Project for Pairing

1. Open Xcode
2. File → New → Project
3. Select **tvOS** → **App**
4. Product Name: `kodi`
5. Team: Select your Apple Developer account
6. Organization Identifier: Match your App ID (e.g., `com.yourusername`)
7. Click through to create project

This enables your Apple TV to be discovered by Xcode.

#### Step 6: Install to Apple TV

1. **Make sure Apple TV is awake and on home screen**

2. In Xcode:
   - Window → Devices and Simulators (⌘⇧2)
   - Select your Apple TV from the list
   - If not visible, ensure it's on same network and try pairing:
     - On Apple TV: Settings → Remotes and Devices → Remote App and Devices
     - In Xcode: Click "+" and follow pairing instructions

3. Click **"+"** button under "INSTALLED APPS"

4. Select `Kodi-signed.ipa`

5. Wait for installation to complete

6. Kodi will appear on Apple TV home screen!

## Troubleshooting

### "Entertainment Room needs to be unlocked"
- Wake up Apple TV with remote
- Make sure it's on home screen, not screensaver

### "Appex bundle ID not prefixed" error
- Make sure you removed the PlugIns folder before creating IPA
- Re-run the extraction and removal steps

### Apple TV not appearing in Xcode
- Ensure both devices on same network
- Create dummy tvOS Xcode project first (Step 5 above)
- Try WiFi if Ethernet doesn't work, or vice versa
- Check: Settings → Remotes and Devices → Remote App and Devices on Apple TV

### Certificate expired
- Certificates expire after 1 year
- Create new certificate on Apple Developer portal
- Create new provisioning profile
- Re-sign and reinstall IPA

## Important Notes

- **App expires in 1 year** when certificate expires - you'll need to re-sign and reinstall
- **No jailbreak required** - this method works on stock Apple TV
- **Paid developer account required** ($99/year from Apple)
- **PlugIns folder must be removed** to avoid bundle ID conflicts
- **Apple TV must be registered** in your developer account

## Quick Reference Commands

```bash
# Install dpkg
brew install dpkg

# Extract .deb
dpkg-deb -R kodi.deb ~/kodi-extracted

# Remove PlugIns
rm -rf ~/kodi-extracted/Applications/Kodi.app/PlugIns

# Create IPA
mkdir Payload && cp -r ~/kodi-extracted/Applications/Kodi.app Payload/
zip -qr Kodi-unsigned.ipa Payload && rm -rf Payload

# Make script executable
chmod +x ~/install-kodi-tvos.sh

# Run installation script
~/install-kodi-tvos.sh
```

## Resources

- iOS App Signer: https://dantheman827.github.io/ios-app-signer/
- Apple Developer Portal: https://developer.apple.com/account
- Kodi Downloads: https://kodi.tv/download
- Homebrew: https://brew.sh/

---

**Created:** November 11, 2025  
**Tested on:** Apple TV 4K (A2843), tvOS 18.3, macOS 15.6, Xcode 26.1
