# Makefile for the rebuilt Broadlink Integration Package

include $(TOPDIR)/rules.mk

PKG_NAME:=broadlink-ng
PKG_VERSION:=2.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/broadlink-ng
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Broadlink NG - Control your devices via Web & MQTT
  # DEPENDENCIES:
  # +lua-mosquitto: For MQTT communication
  # +lua-uloop: For running the Lua script as a persistent daemon
  # +lua-cjson: Faster JSON handling for the API
  # +lua-openssl: Required by the protocol library for encryption
  DEPENDS:=+lua +luci-base +lua-cjson +lua-mosquitto +lua-uloop +lua-openssl
  MAINTAINER:=Your Name <your.email@example.com>
endef

define Package/broadlink-ng/description
  A complete solution to control Broadlink devices (RM Pro, RM Mini, etc.)
  through the LuCI web interface and MQTT.
  Features device discovery, code learning, and a modern UI.
endef

# Files to be installed
define Package/broadlink-ng/install
	# Create necessary directories
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_DIR) $(1)/usr/lib/lua/broadlink

	# Install configuration file
	$(INSTALL_CONF) ./files/etc/config/broadlink $(1)/etc/config/

	# Install init script
	$(INSTALL_BIN) ./files/etc/init.d/broadlink $(1)/etc/init.d/

	# Install LuCI controller and view
	$(INSTALL_BIN) ./files/usr/lib/lua/luci/controller/broadlink.lua $(1)/usr/lib/lua/luci/controller/
	$(INSTALL_BIN) ./files/usr/lib/lua/luci/view/broadlink_ui.htm $(1)/usr/lib/lua/luci/view/

	# Install the main daemon script
	$(INSTALL_BIN) ./files/usr/sbin/broadlinkd $(1)/usr/sbin/

	# Install Broadlink Lua libraries
	$(CP) ./files/usr/lib/lua/broadlink/*.lua $(1)/usr/lib/lua/broadlink/
endef

$(eval $(call BuildPackage,broadlink-ng))
