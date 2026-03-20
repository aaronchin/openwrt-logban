include $(TOPDIR)/rules.mk

PKG_NAME:=logban
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=aaronchin
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/logban
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Firewall
  TITLE:=Lightweight auth log ban service for OpenWrt
  PKGARCH:=all
  DEPENDS:=+firewall4 +nftables
endef

define Package/logban/description
 A lightweight OpenWrt service that watches auth logs in real time and
 blocks abusive source IPs after repeated failed logins.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/logban/conffiles
/etc/config/logban
endef

define Package/logban/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_CONF) ./files/etc/config/logban $(1)/etc/config/logban
	$(INSTALL_BIN) ./files/etc/init.d/logban $(1)/etc/init.d/logban
	$(INSTALL_BIN) ./files/usr/sbin/logban.sh $(1)/usr/sbin/logban.sh
endef

$(eval $(call BuildPackage,logban))
