#!/bin/bash

# =========================================================
# 硬件核心：Inseego FG2000 适配与 NSS 补丁注入
# =========================================================
echo "===> 1. 拉取并应用高通 NSS 核心优化补丁..."
git clone --depth 1 https://github.com/laipeng668/openwrt-6.x.git temp_laipeng
mkdir -p target/linux/qualcommax/
cp -r temp_laipeng/target/linux/*/patches-6.* target/linux/qualcommax/ 2>/dev/null || true

echo "===> 2. 提取并注入 Inseego FG2000 设备树 (DTS)..."
mkdir -p target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/
DTS_FILE=$(find temp_laipeng/target/linux/ -name "*fg2000*.dts" -o -name "*inseego*.dts" | head -n 1)

if [ -n "$DTS_FILE" ]; then
    cp "$DTS_FILE" target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/
    DTS_FILENAME=$(basename "$DTS_FILE" .dts)
else
    DTS_FILENAME="ipq8072a-inseego-fg2000"
fi

echo "===> 3. 注册 FG2000 编译节点..."
if ! grep -q "define Device/inseego_fg2000" target/linux/qualcommax/image/*.mk 2>/dev/null; then
    cat >> target/linux/qualcommax/image/ipq807x.mk <<EOF

define Device/inseego_fg2000
  DEVICE_VENDOR := Inseego
  DEVICE_MODEL := FG2000
  DEVICE_DTS := qcom/\${DTS_FILENAME}
  DEVICE_PACKAGES := kmod-qca-nss-dp kmod-qca-nss-drv kmod-qca-nss-drv-pppoe kmod-qca-nss-ecm kmod-shortcut-fe
endef
TARGET_DEVICES += inseego_fg2000
EOF
fi
rm -rf temp_laipeng

# =========================================================
# 系统底层信息修改
# =========================================================
sed -i 's/192.168.1.1/192.168.20.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='JacobWrt'/g" package/base-files/files/bin/config_generate
BUILD_DATE=$(date +'%Y-%m-%d %H:%M:%S')
sed -i "s#_('Firmware Version'), (L\.isObject(boardinfo\.release) ? boardinfo\.release\.description + ' / ' : '') + (luciversion || ''),#_('Firmware Version'), E('span', {}, [ (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || '') + ' / ', E('a', { href: 'https://github.com/laipeng668/openwrt-ci-roc/releases', target: '_blank', rel: 'noopener noreferrer' }, [ 'Built by Jacob ${BUILD_DATE}' ]) ]),#g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js
sed -i 's/luci-theme-bootstrap/luci-theme-aurora/g' feeds/luci/collections/luci/Makefile

# =========================================================
# 依赖环境补充 (解决递归依赖与缺失包)
# =========================================================
echo "===> 正在优化 Golang 环境及 Mihomo 核心..."
# 1. 强制更新 Feed 索引，确保依赖关系被正确扫描
./scripts/feeds update -a
./scripts/feeds install -a

# 2. 使用 sbwml 的 Golang 1.22+
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 23.x feeds/packages/lang/golang

# 3. 注入稳定版 Mihomo 核心
git clone --depth=1 https://github.com/morytyann/OpenWrt-mihomo.git /tmp/nikki_repo
cp -r /tmp/nikki_repo/mihomo package/mihomo 2>/dev/null || cp -r /tmp/nikki_repo package/mihomo
rm -rf /tmp/nikki_repo

# 4. 强制修复 OAF 递归依赖 (直接禁用)
sed -i '/CONFIG_PACKAGE_kmod-oaf/d' .config 2>/dev/null || true

# =========================================================
# 引入第三方插件 (保留必要的克隆逻辑)
# =========================================================
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

# 引入必要插件
git_sparse_clone aria2 https://github.com/laipeng668/packages net/aria2
git_sparse_clone nginx https://github.com/laipeng668/packages net/nginx
git_sparse_clone frp-binary https://github.com/laipeng668/packages net/frp
git_sparse_clone frp https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps

git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config package/luci-app-aurora-config
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac
