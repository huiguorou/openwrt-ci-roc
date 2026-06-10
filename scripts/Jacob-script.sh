#!/bin/bash

# =========================================================
# 1. 纯净硬件配置：放弃外部内核补丁，仅保留 DTS 注入
# =========================================================
echo "===> 正在准备纯净编译环境..."
# 获取最新的 DTS 资源
git clone --depth 1 https://github.com/laipeng668/openwrt-6.x.git temp_laipeng
mkdir -p target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/
DTS_FILE=$(find temp_laipeng/target/linux/ -name "*fg2000*.dts" -o -name "*inseego*.dts" | head -n 1)
[ -n "$DTS_FILE" ] && cp "$DTS_FILE" target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq8072-fg2000.dts
rm -rf temp_laipeng

echo "===> 正在注册 FG2000 编译节点..."
cat >> target/linux/qualcommax/image/ipq807x.mk <<EOF

define Device/inseego_fg2000
  DEVICE_VENDOR := Inseego
  DEVICE_MODEL := FG2000
  DEVICE_DTS := qcom/ipq8072-fg2000
  DEVICE_PACKAGES := kmod-qca-nss-dp kmod-qca-nss-drv kmod-qca-nss-drv-pppoe kmod-qca-nss-ecm kmod-shortcut-fe
endef
TARGET_DEVICES += inseego_fg2000
EOF

# =========================================================
# 2. 系统底层信息修改
# =========================================================
echo "===> 正在优化系统配置..."
./scripts/feeds update -a
./scripts/feeds install -a

sed -i 's/192.168.1.1/192.168.20.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='JacobWrt'/g" package/base-files/files/bin/config_generate
sed -i "s#_('Firmware Version'), (L\.isObject(boardinfo\.release) ? boardinfo\.release\.description + ' / ' : '') + (luciversion || ''),#_('Firmware Version'), E('span', {}, [ (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || '') + ' / ', E('a', { href: 'https://github.com/laipeng668/openwrt-ci-roc/releases', target: '_blank', rel: 'noopener noreferrer' }, [ 'Built by Jacob $(date +'%Y-%m-%d')' ]) ]),#g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

# =========================================================
# 3. 依赖清理与递归依赖修复
# =========================================================
# 移除会导致死锁的 Mihomo-meta/alpha 冲突
sed -i '/mihomo-meta/d' feeds/packages/net/mihomo/Makefile 2>/dev/null || true
sed -i '/mihomo-alpha/d' feeds/packages/net/mihomo/Makefile 2>/dev/null || true
sed -i '/CONFIG_PACKAGE_kmod-oaf/d' .config 2>/dev/null || true
rm -rf tmp/info/ tmp/.config-package.in

# =========================================================
# 4. 插件注入
# =========================================================
# 注入 Mihomo
git clone --depth=1 https://github.com/morytyann/OpenWrt-mihomo.git /tmp/nikki_repo
cp -r /tmp/nikki_repo/mihomo package/mihomo 2>/dev/null || cp -r /tmp/nikki_repo package/mihomo
rm -rf /tmp/nikki_repo

# 引入必要插件库
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

git_sparse_clone aria2 https://github.com/laipeng668/packages net/aria2
git_sparse_clone nginx https://github.com/laipeng668/packages net/nginx
git_sparse_clone frp https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps

git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac
