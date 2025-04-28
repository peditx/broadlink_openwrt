include $(TOPDIR)/rules.mk

PKG_NAME:=broadlink
PKG_VERSION:=1.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/broadlink
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Broadlink Integration
  DEPENDS:=+lua +luci-base +luci-lib-json +libopenssl +libpthread +libubus +libubox
endef

define Package/broadlink/install
    $(INSTALL_DIR) $(1)/etc/config
    $(INSTALL_DIR) $(1)/etc/init.d
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci
    $(INSTALL_DIR) $(1)/usr/sbin
    $(INSTALL_DIR) $(1)/usr/lib/lua/broadlink
    
    $(INSTALL_CONF) ./files/etc/config/broadlink $(1)/etc/config/
    $(INSTALL_BIN) ./files/etc/init.d/broadlink $(1)/etc/init.d/
    $(CP) ./files/usr/lib/lua/luci/* $(1)/usr/lib/lua/luci/
    $(CP) ./files/usr/lib/lua/broadlink/* $(1)/usr/lib/lua/broadlink/
    $(INSTALL_BIN) ./files/usr/sbin/broadlink-cli $(1)/usr/sbin/
endef

$(eval $(call BuildPackage,broadlink))
