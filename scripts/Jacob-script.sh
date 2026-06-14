#!/bin/bash

# =========================================================
# 1. 纯净硬件配置：放弃外部内核补丁，精确补充 DTS 与相关 DTSI 依赖
# =========================================================
echo "===> 正在准备纯净编译环境..."
# 建立标准内核 DTS 存储目录
mkdir -p target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/

# 克隆临时素材库
git clone --depth 1 https://github.com/laipeng668/openwrt-6.x.git temp_laipeng

# 定位并拷贝 FG2000 的核心 DTS 文件
DTS_FILE=$(find temp_laipeng/target/linux/ -name "*fg2000*.dts" -o -name "*inseego*.dts" | head -n 1)
if [ -n "$DTS_FILE" ]; then
    echo "✅ 成功捕获 FG2000 主设备树: $DTS_FILE"
    cp "$DTS_FILE" target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq8072-fg2000.dts
fi

# 核心修复：地毯式搜寻所有缺失的 ipq8074/ipq8072 相关头文件 (.dtsi) 并一并注入
# 这将彻底解决 #include "ipq8074-nss.dtsi" 找不到文件的致命错误
echo "===> 正在同步提取并补齐所有相关的 .dtsi 依赖组件..."
find temp_laipeng/target/linux/ -name "ipq8074*.dtsi" -o -name "ipq8072*.dtsi" | while read -r dtsi_path; do
    echo "  -> 注入依赖: $(basename "$dtsi_path")"
    cp "$dtsi_path" target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/
done

# 销毁临时素材库
rm -rf temp_laipeng

echo "===> 正在注册 FG2000 编译节点..."
# 注意：这里 DEVICE_DTS 填写 ipq8072-fg2000，系统会自动处理前缀，避免生成 qcom/qcom/ 冗余路径
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
# 移除会导致死锁的 Mihomo-meta/alpha 冲突，禁止自选依赖
sed -i '/mihomo-meta/d' feeds/packages/net/mihomo/Makefile 2>/dev/null || true
sed -i '/mihomo-alpha/d' feeds/packages/net/mihomo/Makefile 2>/dev/null || true
sed -i '/CONFIG_PACKAGE_kmod-oaf/d' .config 2>/dev/null || true
rm -rf tmp/info/ tmp/.config-package.in

# =========================================================
# 4. 插件注入
# =========================================================
# 注入稳定版 Mihomo 核心
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
