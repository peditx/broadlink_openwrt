#!/bin/sh

# Auto-install Broadlink for OpenWrt (Compatible with legacy wget)1
# Execute with: sh install_broadlink.sh

# Check root
[ "$(id -u)" -ne 0 ] && {
    echo "Error: Root access required!"
    exit 1
}

# Temporary directory
TMP_DIR="/tmp/broadlink_install"
REPO_URL="https://github.com/peditx/broadlink_openwrt"

# Cleanup previous attempts
rm -rf "$TMP_DIR" 2>/dev/null

# Install essential tools
echo "Installing dependencies..."
opkg update
opkg install wget unzip ca-bundle || {
    echo "Error: Failed to install prerequisites!"
    exit 1
}

# Download repository (simplified for legacy wget)
echo "Downloading repository..."
wget -q -O "$TMP_DIR.zip" "$REPO_URL/archive/main.zip" || {
    echo "Download failed! Check:"
    echo "1. Internet connection"
    echo "2. Certificate validity: opkg install ca-bundle"
    echo "3. GitHub availability"
    exit 1
}

# Extract files
echo "Extracting files..."
unzip -q "$TMP_DIR.zip" -d "$TMP_DIR" || {
    echo "Extraction failed! Possible causes:"
    echo "1. Corrupted download"
    echo "2. Insufficient space in /tmp"
    echo "3. Missing unzip: opkg install unzip"
    exit 1
}

# Verify directory structure
REPO_DIR="$TMP_DIR/broadlink_openwrt-main"
[ ! -d "$REPO_DIR/files" ] && {
    echo "Invalid repository structure!"
    exit 1
}

# Install package dependencies
echo "Checking runtime dependencies..."
for pkg in lua luci-base luci-lib-json libopenssl libpthread libubus libubox; do
    opkg list-installed | grep -q "^$pkg " || {
        echo "Installing $pkg..."
        opkg install $pkg || {
            echo "Dependency error! Install manually: opkg install $pkg"
            exit 1
        }
    }
done

# File deployment
echo "Installing components..."
cp -vr "$REPO_DIR/files/etc/config/broadlink" "/etc/config/"
cp -vr "$REPO_DIR/files/etc/init.d/broadlink" "/etc/init.d/"
cp -vr "$REPO_DIR/files/usr/lib/lua/luci/"* "/usr/lib/lua/luci/"
mkdir -p "/usr/lib/lua/broadlink"
cp -vr "$REPO_DIR/files/usr/lib/lua/broadlink/"* "/usr/lib/lua/broadlink/"
cp -vr "$REPO_DIR/files/usr/sbin/broadlink-cli" "/usr/sbin/"

# Set permissions
echo "Setting permissions..."
chmod 755 "/etc/init.d/broadlink"
chmod 755 "/usr/sbin/broadlink-cli"

# Service management
echo "Initializing services..."
/etc/init.d/broadlink enable
/etc/init.d/broadlink start
/etc/init.d/uhttpd restart

# Cleanup
rm -rf "$TMP_DIR" "$TMP_DIR.zip"

echo ""
echo "✅ Broadlink Successfully Installed!"
echo "Access via: LuCI → Utilities → Broadlink"
