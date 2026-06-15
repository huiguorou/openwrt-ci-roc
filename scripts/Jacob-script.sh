#!/bin/bash

# =========================================================
# 1. 纯净硬件配置：精确定位唯一的 ipq8074-nss.dtsi 依赖与补丁清洗
# =========================================================
echo "===> 正在准备纯净编译环境..."
mkdir -p target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/

# 克隆临时素材库
git clone --depth 1 https://github.com/laipeng668/openwrt-6.x.git temp_laipeng

# 定位并拷贝 FG2000 的核心 DTS 文件
DTS_FILE=$(find temp_laipeng/target/linux/ -name "*fg2000*.dts" -o -name "*inseego*.dts" | head -n 1)
if [ -n "$DTS_FILE" ]; then
    echo "✅ 成功捕获 FG2000 主设备树: $DTS_FILE"
    cp "$DTS_FILE" target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq8072-fg2000.dts
fi

# 精准隔离注入核心组件
DTSI_NSS=$(find temp_laipeng/target/linux/ -name "ipq8074-nss.dtsi" | head -n 1)
if [ -n "$DTSI_NSS" ]; then
    cp "$DTSI_NSS" target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/
    echo "  -> 成功隔离注入: ipq8074-nss.dtsi"
fi

# 精准注入 NSS 驱动补丁到官方 6.12 补丁池
echo "===> 正在挑选兼容的 NSS 核心内核补丁..."
mkdir -p target/linux/qualcommax/patches-6.12/
find temp_laipeng/target/linux/ -name "*nss*.patch" -exec cp {} target/linux/qualcommax/patches-6.12/ \; 2>/dev/null || true

# 🔪 【核心修复】强行粉碎冲突的 VXLAN 补丁，防止内核构建崩溃！
rm -f target/linux/qualcommax/patches-6.12/*vxlan*.patch
echo "  -> 🛠️ 已成功强行剔除破坏性的 VXLAN 冲突补丁！"

rm -rf temp_laipeng

echo "===> 正在注册 FG2000 编译节点..."
cat >> target/linux/qualcommax/image/ipq807x.mk <<EOF

define Device/inseego_fg2000
  DEVICE_VENDOR := Inseego
  DEVICE_MODEL := FG2000
  DEVICE_DTS := ipq8072-fg2000
  DEVICE_PACKAGES := kmod-qca-nss-dp kmod-qca-nss-drv kmod-qca-nss-drv-pppoe kmod-qca-nss-ecm kmod-shortcut-fe
endef
TARGET_DEVICES += inseego_fg2000
EOF

# =========================================================
# 2. 系统底层信息修改与 Feed 同步
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
sed -i '/mihomo-meta/d' feeds/packages/net/mihomo/Makefile 2>/dev/null || true
sed -i '/mihomo-alpha/d' feeds/packages/net/mihomo/Makefile 2>/dev/null || true
sed -i '/CONFIG_PACKAGE_kmod-oaf/d' .config 2>/dev/null || true
rm -rf tmp/info/ tmp/.config-package.in

# =========================================================
# 4. 核心功能插件注入
# =========================================================
git clone --depth=1 https://github.com/morytyann/OpenWrt-mihomo.git /tmp/nikki_repo
cp -r /tmp/nikki_repo/mihomo package/mihomo 2>/dev/null || cp -r /tmp/nikki_repo package/mihomo
rm -rf /tmp/nikki_repo

git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
