#!/bin/bash

# =========================================================
# 硬件核心：Inseego FG2000 适配与 NSS 补丁注入
# =========================================================
echo "===> 1. 拉取并应用高通 NSS 核心优化补丁..."
git clone --depth 1 https://github.com/laipeng668/openwrt-6.x.git temp_laipeng
mkdir -p target/linux/qualcommax/
# 兼容处理：无论源仓库里叫 ipq807x 还是 qualcommax，都精准提取补丁到我们的 qualcommax 目录下
cp -r temp_laipeng/target/linux/*/patches-6.* target/linux/qualcommax/ 2>/dev/null || true

echo "===> 2. 提取 Inseego FG2000 设备树 (DTS)..."
mkdir -p target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/
# 兼容处理：无视源仓库目录名，精准抓取 FG2000 的 DTS 放入正确位置
cp temp_laipeng/target/linux/*/files/arch/arm64/boot/dts/qcom/*fg2000*.dts target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ 2>/dev/null

echo "===> 3. 注册 FG2000 编译节点..."
# 从我们刚复制好的正确目录中动态提取 DTS 文件名
DTS_FILENAME=$(ls target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/*fg2000*.dts | head -n 1 | awk -F'/' '{print $NF}' | sed 's/\.dts//')

# 安全地将机型配置追加到 Makefile 尾部
cat >> target/linux/qualcommax/image/ipq807x.mk <<EOF

define Device/inseego_fg2000
  DEVICE_VENDOR := Inseego
  DEVICE_MODEL := FG2000
  DEVICE_DTS := qcom/\${DTS_FILENAME}
  DEVICE_PACKAGES := kmod-qca-nss-dp kmod-qca-nss-drv kmod-qca-nss-drv-pppoe kmod-qca-nss-ecm kmod-shortcut-fe
endef
TARGET_DEVICES += inseego_fg2000
EOF

# 销毁临时素材库
rm -rf temp_laipeng

# =========================================================
# 系统底层信息修改 (这里往下接你原来的代码)
# =========================================================
# 修改默认IP & 固件名称
sed -i 's/192.168.1.1/192.168.20.1/g' package/base-files/files/bin/config_generate
...
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
                }, [ 'Built by Jacob $(date "+%Y-%m-%d %H:%M:%S")' ])\n \
            ]),#" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

# 修改默认主题为 Aurora
sed -i 's/luci-theme-bootstrap/luci-theme-aurora/g' feeds/luci/collections/luci/Makefile


# =========================================================
# 依赖清理与环境优化 (极简瘦身)
# =========================================================
# 1. 移除旧版 Golang，替换为 sbwml 优化的 Golang 1.22+
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 23.x feeds/packages/lang/golang

# 2. 彻底解决 Mihomo 死循环与 Nikki 依赖丢失问题
rm -rf package/feeds/*/mihomo
rm -rf package/feeds/*/mihomo-alpha
rm -rf package/feeds/*/mihomo-meta
find ./feeds ./package -maxdepth 6 -type d -name "mihomo" -exec rm -rf {} +
find ./feeds ./package -maxdepth 6 -type d -name "mihomo-alpha" -exec rm -rf {} +
find ./feeds ./package -maxdepth 6 -type d -name "mihomo-meta" -exec rm -rf {} +

# 注入 Nikki 官方稳定版 mihomo 核心
git clone --depth=1 https://github.com/morytyann/OpenWrt-mihomo.git /tmp/nikki_repo
cp -r /tmp/nikki_repo/mihomo package/mihomo
rm -rf /tmp/nikki_repo

# 3. 彻底清理残余的上层插件及其系统软链接
find ./ -name "luci-app-netspeedtest*" | xargs rm -rf
find ./ -name "netspeedtest" | xargs rm -rf
find ./ -name "onionshare-cli" | xargs rm -rf
find ./ -name "luci-app-passwall*" | xargs rm -rf
find ./ -name "passwall-packages" | xargs rm -rf
find ./ -name "luci-app-lxc" | xargs rm -rf
find ./ -name "rpcd-mod-lxc" | xargs rm -rf
find ./ -name "lxc" -type d | xargs rm -rf
find ./ -name "geoview" | xargs rm -rf
find ./ -name "luci-app-wechatpush" | xargs rm -rf

# 4. 移除源自带的旧版本包，准备替换
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
# 拯救 Nikki：从官方稳定分支提取健康的 yq 源码
# =========================================================
rm -rf feeds/packages/utils/yq
git clone --depth=1 -b openwrt-23.05 https://github.com/openwrt/packages.git /tmp/stable_packages
cp -r /tmp/stable_packages/utils/yq feeds/packages/utils/yq
rm -rf /tmp/stable_packages


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

# 基础下载与穿透工具
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

# UI与功能拓展
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon feeds/luci/themes/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config feeds/luci/applications/luci-app-argon-config
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora feeds/luci/themes/luci-theme-aurora
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config feeds/luci/applications/luci-app-aurora-config
git clone --depth=1 https://github.com/sbwml/luci-app-openlist2 package/openlist2
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter
git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac
