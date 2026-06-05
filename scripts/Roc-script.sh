#!/bin/bash

# =========================================================
# 系统底层信息修改
# =========================================================
# 修改默认IP & 固件名称
sed -i 's/192.168.1.1/192.168.20.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='JacobWrt'/g" package/base-files/files/bin/config_generate

# 修改编译署名和时间
sed -i "s#_('Firmware Version'), (L\.isObject(boardinfo\.release) ? boardinfo\.release\.description + ' / ' : '') + (luciversion || ''),# \
            _('Firmware Version'),\n \
            E('span', {}, [\n \
                (L.isObject(boardinfo.release)\n \
                ? boardinfo.release.description + ' / '\n \
                : '') + (luciversion || '') + ' / ',\n \
            E('a', {\n \
                href: 'https://github.com/laipeng668/openwrt-ci-roc/releases',\n \
                target: '_blank',\n \
                rel: 'noopener noreferrer'\n \
                }, [ 'Built by Roc $(date "+%Y-%m-%d %H:%M:%S")' ])\n \
            ]),#" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

# 修改默认主题为 Argon
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# =========================================================
# 依赖清理与环境优化 (极简瘦身)
# =========================================================
# 1. 移除旧版 Golang，替换为 sbwml 优化的 Golang 1.22+ (彻底解决 Mihomo 编译失败 cp 报错)
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 23.x feeds/packages/lang/golang

# 2. 清理产生依赖警告且不需要的冗余软件包 (测速, 旧5G管理, 容器, 多余代理层等)
rm -rf feeds/luci/applications/luci-app-netspeedtest
rm -rf package/netspeedtest
rm -rf package/QModem
rm -rf package/feeds/packages/onionshare-cli
rm -rf package/feeds/packages/lxc
rm -rf feeds/packages/net/geoview
rm -rf feeds/luci/applications/luci-app-lxc
rm -rf feeds/packages/system/rpcd-mod-lxc
rm -rf package/luci-app-passwall
rm -rf package/luci-app-passwall2
rm -rf package/passwall-packages
rm -rf package/luci-app-wechatpush

# 3. 移除源自带的旧版本包，准备通过 Git 克隆替换新版
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/applications/luci-app-appfilter
rm -rf feeds/luci/applications/luci-app-frpc
rm -rf feeds/luci/applications/luci-app-frps
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/packages/net/ariang
rm -rf feeds/packages/net/aria2
rm -rf feeds/packages/net/nginx
rm -rf feeds/packages/net/frp

# =========================================================
# 拯救 Nikki：强制降级 yq 到稳定的 4.44.3 版本 (绕过 Go 1.25 报错)
# =========================================================
rm -rf feeds/packages/utils/yq
mkdir -p feeds/packages/utils/yq
cat << 'EOF' > feeds/packages/utils/yq/Makefile
include $(TOPDIR)/rules.mk

PKG_NAME:=yq
PKG_VERSION:=4.44.3
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/mikefarah/yq/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=2c700cb755ab2b4e477af94f2dd73909100eab86687c427321bbecbb05f2590d

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/mikefarah/yq/v4

include $(INCLUDE_DIR)/package.mk
include ../../lang/golang/golang-package.mk

define Package/yq
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=yq
  URL:=https://mikefarah.gitbook.io/yq/
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

$(eval $(call GoBinPackage,yq))
$(eval $(call BuildPackage,yq))
EOF

# =========================================================
# 引入第三方插件与工具
# =========================================================
# Git稀疏克隆函数
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

# 基础下载与穿透工具 (Aria2, Nginx, FRP)
git_sparse_clone aria2 https://github.com/laipeng668/packages net/aria2
mv -f package/aria2 feeds/packages/net/aria2
git_sparse_clone nginx https://github.com/laipeng668/packages net/nginx
mv -f package/nginx feeds/packages/net/nginx
git_sparse_clone ariang https://github.com/laipeng668/packages net/ariang
mv -f package/ariang feeds/packages/net/ariang
git_sparse_clone frp-binary https://github.com/laipeng668/packages net/frp
mv -f package/frp feeds/packages/net/frp
git_sparse_clone frp https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps
mv -f package/luci-app-frpc feeds/luci/applications/luci-app-frpc
mv -f package/luci-app-frps feeds/luci/applications/luci-app-frps

# UI与功能拓展 (Argon, Aurora, Lucky, OAF, AC控制器等)
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon feeds/luci/themes/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config feeds/luci/applications/luci-app-argon-config
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora feeds/luci/themes/luci-theme-aurora
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config feeds/luci/applications/luci-app-aurora-config
git clone --depth=1 https://github.com/sbwml/luci-app-openlist2 package/openlist2
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter
git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led
