# Installing Kodi on Non-Jailbroken Apple TV

Complete guide for installing Kodi from a .deb file onto a non-jailbroken Apple TV using a paid Apple Developer account.

> **Kodi stopped opening?** The Apple Distribution certificate (and the profile built on it) lasts one year.
> Follow [Yearly renewal](#yearly-renewal-certificate-expired) below — it takes about 10 minutes and keeps your Kodi settings and add-ons.

## Yearly renewal (certificate expired)

Symptom: Kodi's icon is still on the Apple TV but it refuses to open. Your Developer Program membership is a
separate thing; the certificate expires every year regardless.

**Current certificate/profile expire: 2027-11-13** (renewed 2026-11-13).

### Fast path: one command (App Store Connect API)

With an App Store Connect API key set up (below), the whole renewal is:

```bash
# Apple TV awake, on the home screen
./resign-kodi-tvos.sh --renew ~/Downloads/org.xbmc.kodi-tvos_21.2-tvos.deb
```

`--renew` runs `asc.py renew`, which generates a new private key + CSR locally, creates the Apple Distribution
certificate through the API, imports key + certificate into the login keychain, creates a **tvOS Ad Hoc** profile
for the App ID and every enabled Apple TV on the account, and saves it to `~/Downloads`. The script then re-signs
and installs over the existing Kodi as usual. No browser, no 2FA.

`python3 asc.py check` is read-only: it lists Distribution certificates, tvOS Ad Hoc profiles (with expiry),
the App ID and registered Apple TVs — useful to see where things stand.

**One-time API key setup** (done 2026-11-13; key `kodi-renew`):

1. https://appstoreconnect.apple.com/access/integrations/api → **Team Keys** (click *Request Access* the first time)
2. Generate a key with the **Admin** role (only Admin can create certificates/profiles over the API)
3. Download `AuthKey_<KEYID>.p8` (only downloadable once) and lock it down:

```bash
mv ~/Downloads/AuthKey_<KEYID>.p8 ~/.kodi-signing/ && chmod 600 ~/.kodi-signing/AuthKey_<KEYID>.p8
cat > ~/.kodi-signing/asc.env <<EOF
ASC_KEY_ID=<KEYID>
ASC_ISSUER_ID=<Issuer ID from the same page>
ASC_KEY_FILE=\$HOME/.kodi-signing/AuthKey_<KEYID>.p8
KODI_BUNDLE_ID=com.startergo.UTM.kodi
EOF
chmod 600 ~/.kodi-signing/asc.env
```

An Admin key can do almost anything on the developer account — treat the `.p8` like a password. It never goes in
this repo; revoke it on the same page if it leaks (or after each renewal, and make a new one next year).

### Manual path (browser)

If the API key is gone, do it by hand:

### 1. Make a certificate signing request (Terminal, no Keychain Access needed)

```bash
mkdir -p ~/.kodi-signing && chmod 700 ~/.kodi-signing && cd ~/.kodi-signing
Y=$(date +%Y)
/usr/bin/openssl genrsa -out dist$Y.key 2048 && chmod 600 dist$Y.key
/usr/bin/openssl req -new -key dist$Y.key -out dist$Y.certSigningRequest -subj "/CN=Your Name/C=US"
```

Keep `~/.kodi-signing` — the private key never leaves your Mac and the certificate is useless without it.

### 2. Create the certificate

1. https://developer.apple.com/account/resources/certificates/add → **Apple Distribution** → Continue
2. Upload `~/.kodi-signing/distYYYY.certSigningRequest` → Continue → **Download** (`distribution.cer`)
3. Import the key and certificate into the login keychain:

```bash
cd ~/.kodi-signing
security import dist$Y.key -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
security import ~/Downloads/distribution.cer -k ~/Library/Keychains/login.keychain-db
security find-identity -v -p codesigning     # should list "Apple Distribution: ..."
```

You can revoke the old, expired Distribution certificate on the portal.

### 3. Create the provisioning profile

1. https://developer.apple.com/account/resources/profiles/add
2. Choose **tvOS Ad Hoc** — *not* the plain "Ad Hoc" just above it (that one is iOS and won't list the Apple TV)
3. App ID: the **same** one as before (`com.startergo.UTM.kodi`) — same App ID + same team is what preserves Kodi's data
4. Certificate: the new Distribution certificate · Device: the Apple TV
5. Name it (e.g. `Kodi tvOS AdHoc YYYY`) → Generate → Download

### 4. Re-sign and install

Wake the Apple TV (home screen, not screensaver), then:

```bash
./resign-kodi-tvos.sh ~/Downloads/Kodi_tvOS_AdHoc_YYYY.mobileprovision ~/Downloads/org.xbmc.kodi-tvos_21.2-tvos.deb
```

The script reads the profile, picks the matching keychain identity, unpacks the `.deb` (no `dpkg` needed),
removes `PlugIns`, sets the bundle ID, signs nested frameworks then the app, verifies, writes
`~/Desktop/Kodi-signed.ipa`, and installs it **over** the existing Kodi with `xcrun devicectl`.

**Don't delete Kodi from the Apple TV first** — installing over it keeps settings and add-ons.

Options: `--no-install` (sign only), `--device <name|identifier>` (if several Apple TVs).
If the install step can't find the Apple TV, see *Apple TV shows "unavailable" / "Browsing on the local area network"* below,
then install the signed app with Xcode (Devices → **+** → `~/Desktop/Kodi-signed.ipa`) or re-run the script.

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
3. Select "tvOS Ad Hoc" (not the plain "Ad Hoc", which is for iOS devices)
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

### Apple TV shows "unavailable" / "Browsing on the local area network"
Seen during the 2026 renewal: the Apple TV pinged fine and advertised itself on the network, but Xcode
(and `xcrun devicectl list devices`) kept it under **Disconnected**. The pairing record had gone stale.
Fix:
1. Xcode → Window → Devices and Simulators → right-click the Apple TV → **Unpair Device**
2. On the Apple TV: Settings → Remotes and Devices → **Remote App and Devices** (stay on that screen)
3. In Xcode click **Pair** and enter the code shown on the TV
4. Wait until it moves to **Connected**, then install

If that fails, restart the Apple TV (Settings → System → Restart) and pair again.

### Certificate expired
- Kodi refuses to open; see [Yearly renewal](#yearly-renewal-certificate-expired)

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

# Yearly: re-sign with the new profile and install over the existing Kodi
./resign-kodi-tvos.sh ~/Downloads/<new>.mobileprovision ~/Downloads/org.xbmc.kodi-tvos_21.2-tvos.deb

# Check signing identities / Apple TV connection
security find-identity -v -p codesigning
xcrun devicectl list devices
```

## Resources

- iOS App Signer: https://dantheman827.github.io/ios-app-signer/
- Apple Developer Portal: https://developer.apple.com/account
- Kodi Downloads: https://kodi.tv/download
- Homebrew: https://brew.sh/

---

**Created:** November 11, 2025  
**Renewed:** November 13, 2026 (tvOS 26.2, macOS 26.5)  
**Tested on:** Apple TV 4K (A2843), tvOS 18.3, macOS 15.6, Xcode 26.1
