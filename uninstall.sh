#!/bin/sh

echo ">>> Starting Broadlink NG Uninstallation..."

# 1. Stop and disable the service if it exists
if [ -f /etc/init.d/broadlink ]; then
    echo "--> Stopping and disabling the service..."
    /etc/init.d/broadlink stop >/dev/null 2>&1
    /etc/init.d/broadlink disable >/dev/null 2>&1
fi

# 2. Remove all application files
echo "--> Removing application files..."
rm -f /etc/init.d/broadlink
rm -f /etc/config/broadlink
rm -f /usr/sbin/broadlinkd
rm -f /usr/lib/lua/luci/controller/broadlink.lua
rm -f /usr/lib/lua/luci/view/broadlink_ui.htm
rm -rf /usr/lib/lua/broadlink

# 3. Remove the firewall rule
echo "--> Removing firewall rule..."
uci -q delete firewall.broadlink_discovery
uci commit firewall
/etc/init.d/firewall reload >/dev/null 2>&1

# 4. Clear LuCI cache to remove the menu entry
echo "--> Clearing LuCI cache..."
rm -rf /tmp/luci-*

echo ""
echo ">>> Broadlink NG has been successfully uninstalled. <<<"
echo ""
echo "NOTE: Dependencies are not removed automatically."
echo "If you are sure they are not used by other packages, you can remove them with:"
echo "opkg remove lua-cjson lua-openssl"
echo ""
