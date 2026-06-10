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
    echo "✅ 成功从 LiBwrt 提取 DTS: $DTS_FILE"
    cp "$DTS_FILE" target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/
    DTS_FILENAME=$(basename "$DTS_FILE" .dts)
else
    echo "⚠️ 未在 LiBwrt 中找到独立 DTS 文件，尝试从本地仓库根目录寻找..."
    DTS_FILE_LOCAL=$(find $GITHUB_WORKSPACE/ -maxdepth 1 -name "*fg2000*.dts" -o -name "*inseego*.dts" | head -n 1)
    if [ -n "$DTS_FILE_LOCAL" ]; then
        cp "$DTS_FILE_LOCAL" target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/
        DTS_FILENAME=$(basename "$DTS_FILE_LOCAL" .dts)
    else
        DTS_FILENAME="ipq8072a-inseego-fg2000"
    fi
fi

echo "===> 3. 注册 FG2000 编译节点..."
if grep -q "define Device/inseego_fg2000" target/linux/qualcommax/image/*.mk 2>/dev/null; then
    echo "✅ 节点已被内核 Patch 自动注册，跳过手动追加。"
else
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
# 依赖清理与环境优化 (暴力破解递归依赖)
# =========================================================
echo "===> 正在暴力破解 Mihomo 递归依赖..."
find feeds/ -name "Makefile" | xargs grep -l "mihomo-alpha" | xargs rm -f
find feeds/ -name "Makefile" | xargs grep -l "mihomo-meta" | xargs rm -f
rm -rf tmp/info/ tmp/.config-package.in

# 1. 移除旧版 Golang，替换为 sbwml 优化的 Golang 1.22+
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 23.x feeds/packages/lang/golang

# 2. 重新注入稳定版 mihomo 核心
echo "===> 正在注入 Mihomo 核心依赖..."
git clone --depth=1 https://github.com/morytyann/OpenWrt-mihomo.git /tmp/nikki_repo
if [ -d "/tmp/nikki_repo/mihomo" ]; then
    cp -r /tmp/nikki_repo/mihomo package/mihomo
else
    cp -r /tmp/nikki_repo package/mihomo
fi
rm -rf /tmp/nikki_repo

# 3. 彻底清理残余插件及链接
find ./ -name "luci-app-*" -o -name "mihomo*" -o -name "passwall*" -o -name "luci-app-lxc" | xargs rm -rf
rm -rf feeds/luci/applications/luci-app-argon-config feeds/luci/applications/luci-app-appfilter feeds/luci/applications/luci-app-frp* feeds/luci/themes/luci-theme-argon

# 4. 拯救 Nikki：提取 yq 源码
rm -rf feeds/packages/utils/yq
git clone --depth=1 -b openwrt-23.05 https://github.com/openwrt/packages.git /tmp/stable_packages
cp -r /tmp/stable_packages/utils/yq feeds/packages/utils/yq
rm -rf /tmp/stable_packages

# =========================================================
# 引入第三方插件与工具
# =========================================================
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

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

git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon feeds/luci/themes/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config feeds/luci/applications/luci-app-argon-config
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora feeds/luci/themes/luci-theme-aurora
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config feeds/luci/applications/luci-app-aurora-config
git clone --depth=1 https://github.com/sbwml/luci-app-openlist2 package/openlist2
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter
git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac
