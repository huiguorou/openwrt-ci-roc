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
                }, [ 'Built by Jacob $(date "+%Y-%m-%d %H:%M:%S")' ])\n \
            ]),#" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

# 修改默认主题为 Aurora
sed -i 's/luci-theme-bootstrap/luci-theme-aurora/g' feeds/luci/collections/luci/Makefile

# =========================================================
# 依赖清理与环境优化 (极简瘦身)
# =========================================================
# 1. 移除旧版 Golang，替换为 sbwml 优化的 Golang 1.22+ (彻底解决 Mihomo 编译失败 cp 报错)
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 23.x feeds/packages/lang/golang

# 2. 终极清理：全盘搜索并物理删除冲突的冗余包与快捷方式 (消灭死循环与警告)

# 解决 mihomo 递归依赖死循环 (保留基础版 mihomo 供 nikki 依赖，只物理删除引发死循环的变种)
find ./ -name "mihomo-alpha" | xargs rm -rf
find ./ -name "mihomo-meta" | xargs rm -rf

# 彻底清理残余的上层插件及其系统软链接 (无死角清理)
find ./ -name "luci-app-netspeedtest*" | xargs rm -rf
find ./ -name "netspeedtest" | xargs rm -rf
find ./ -name "QModem" | xargs rm -rf
find ./ -name "onionshare-cli" | xargs rm -rf
find ./ -name "luci-app-passwall*" | xargs rm -rf
find ./ -name "passwall-packages" | xargs rm -rf
find ./ -name "luci-app-lxc" | xargs rm -rf
find ./ -name "rpcd-mod-lxc" | xargs rm -rf
find ./ -name "lxc" -type d | xargs rm -rf
find ./ -name "geoview" | xargs rm -rf
find ./ -name "luci-app-wechatpush" | xargs rm -rf

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
# 拯救 Nikki：从官方稳定分支提取健康的 yq 源码 (绕过高版本 Go 编译报错)
# =========================================================
rm -rf feeds/packages/utils/yq

# 拉取官方 23.05 稳定版 packages 仓库到临时目录
git clone --depth=1 -b openwrt-23.05 https://github.com/openwrt/packages.git /tmp/stable_packages

# 将稳定版的 yq 源码完整复制过来替换
cp -r /tmp/stable_packages/utils/yq feeds/packages/utils/yq

# 清理临时文件，释放空间
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
# git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
# chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led
