#!/bin/bash

# =========================================================
# 1. 硬件核心：Inseego FG2000 适配与 NSS 补丁注入
# =========================================================
echo "===> 1. 拉取高通 NSS 核心补丁 (跳过冲突补丁)..."
git clone --depth 1 https://github.com/laipeng668/openwrt-6.x.git temp_laipeng
mkdir -p target/linux/qualcommax/patches-6.12/

# 精准注入：仅拷贝 NSS 相关补丁，避开内核自带的 Clock/DTS 补丁
find temp_laipeng/target/linux/ -name "*nss*.patch" -exec cp {} target/linux/qualcommax/patches-6.12/ \; 2>/dev/null || true

echo "===> 2. 提取并注入 Inseego FG2000 设备树 (DTS)..."
mkdir -p target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/
DTS_FILE=$(find temp_laipeng/target/linux/ -name "*fg2000*.dts" -o -name "*inseego*.dts" | head -n 1)
[ -n "$DTS_FILE" ] && cp "$DTS_FILE" target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/
DTS_FILENAME="ipq8072-fg2000" # 统一命名

echo "===> 3. 注册 FG2000 编译节点..."
cat >> target/linux/qualcommax/image/ipq807x.mk <<EOF

define Device/inseego_fg2000
  DEVICE_VENDOR := Inseego
  DEVICE_MODEL := FG2000
  DEVICE_DTS := qcom/ipq8072-fg2000
  DEVICE_PACKAGES := kmod-qca-nss-dp kmod-qca-nss-drv kmod-qca-nss-drv-pppoe kmod-qca-nss-ecm kmod-shortcut-fe
endef
TARGET_DEVICES += inseego_fg2000
EOF
rm -rf temp_laipeng

# =========================================================
# 2. 系统底层信息与环境补充
# =========================================================
echo "===> 正在更新环境依赖..."
./scripts/feeds update -a
./scripts/feeds install -a

sed -i 's/192.168.1.1/192.168.20.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='JacobWrt'/g" package/base-files/files/bin/config_generate
# 修改编译署名
sed -i "s#_('Firmware Version'), (L\.isObject(boardinfo\.release) ? boardinfo\.release\.description + ' / ' : '') + (luciversion || ''),#_('Firmware Version'), E('span', {}, [ (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || '') + ' / ', E('a', { href: 'https://github.com/laipeng668/openwrt-ci-roc/releases', target: '_blank', rel: 'noopener noreferrer' }, [ 'Built by Jacob $(date +'%Y-%m-%d')' ]) ]),#g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

# =========================================================
# 3. 依赖清理 (仅针对导致死锁的包)
# =========================================================
echo "===> 正在进行精细化清理..."
# 禁用会导致递归死锁的冲突源
sed -i '/mihomo-meta/d' feeds/packages/net/mihomo/Makefile 2>/dev/null || true
sed -i '/mihomo-alpha/d' feeds/packages/net/mihomo/Makefile 2>/dev/null || true
sed -i '/CONFIG_PACKAGE_kmod-oaf/d' .config 2>/dev/null || true

# =========================================================
# 4. 注入第三方插件
# =========================================================
# 注入稳定版 Mihomo 核心
git clone --depth=1 https://github.com/morytyann/OpenWrt-mihomo.git /tmp/nikki_repo
cp -r /tmp/nikki_repo/mihomo package/mihomo 2>/dev/null || cp -r /tmp/nikki_repo package/mihomo
rm -rf /tmp/nikki_repo

# 引入插件库
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
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac
