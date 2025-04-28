#!/bin/sh

# Auto-install Broadlink for OpenWrt with GitHub download
# Execute with: sh install_broadlink.sh

# Check root
[ "$(id -u)" -ne 0 ] && {
    echo "Error: Root access required!"
    exit 1
}

# Temporary directory
TMP_DIR="/tmp/broadlink_install"
REPO_URL="https://github.com/peditx/broadlink_openwrt"

# Clean previous attempts
rm -rf "$TMP_DIR"

# Install required tools
echo "Installing dependencies..."
opkg update
opkg install wget unzip ca-bundle || {
    echo "Error: Failed to install required tools!"
    exit 1
}

# Download from GitHub
echo "Downloading repository..."
wget -q --show-progress -O "$TMP_DIR.zip" "$REPO_URL/archive/main.zip" || {
    echo "Download failed! Check internet connection."
    exit 1
}

# Extract files
echo "Extracting files..."
unzip -q "$TMP_DIR.zip" -d "$TMP_DIR" || {
    echo "Extraction failed! Corrupted download."
    exit 1
}

# Navigate to files
REPO_DIR="$TMP_DIR/broadlink_openwrt-main"
[ ! -d "$REPO_DIR/files" ] && {
    echo "File structure mismatch! Missing 'files' directory."
    exit 1
}

# Install package dependencies
echo "Checking package dependencies..."
for pkg in lua luci-base luci-lib-json libopenssl libpthread libubus libubox; do
    opkg list-installed | grep -q "^$pkg " || {
        echo "Installing $pkg..."
        opkg install $pkg || {
            echo "Failed to install $pkg!"
            exit 1
        }
    }
done

# Copy files
echo "Installing components..."
cp -vr "$REPO_DIR/files/etc/config/broadlink" "/etc/config/"
cp -vr "$REPO_DIR/files/etc/init.d/broadlink" "/etc/init.d/"
cp -vr "$REPO_DIR/files/usr/lib/lua/luci/"* "/usr/lib/lua/luci/"
mkdir -p "/usr/lib/lua/broadlink"
cp -vr "$REPO_DIR/files/usr/lib/lua/broadlink/"* "/usr/lib/lua/broadlink/"
cp -vr "$REPO_DIR/files/usr/sbin/broadlink-cli" "/usr/sbin/"

# Set permissions
echo "Setting permissions..."
chmod +x "/etc/init.d/broadlink"
chmod +x "/usr/sbin/broadlink-cli"

# Enable service
echo "Starting services..."
/etc/init.d/broadlink enable
/etc/init.d/broadlink restart
/etc/init.d/uhttpd reload

# Cleanup
rm -rf "$TMP_DIR" "$TMP_DIR.zip"

echo ""
echo "✅ Installation Completed!"
echo "Access Broadlink in LuCI interface → Utilities"
