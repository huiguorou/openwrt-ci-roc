#!/bin/bash
set -e

# =========================================================
# 0. 基础准备
# =========================================================
echo "========================================================="
echo " Jacob FG2000 / IPQ807x Build Customization Started"
echo "========================================================="

echo "===> Updating feeds first..."
./scripts/feeds update -a
./scripts/feeds install -a

QCOM_DTS_DIR="target/linux/qualcommax/files/arch/arm64/boot/dts/qcom"
mkdir -p "$QCOM_DTS_DIR"

# =========================================================
# 1. 纯净硬件配置：注入 FG2000 DTS，并精确补齐 DTSI 依赖
# =========================================================
echo "===> Preparing clean FG2000 DTS environment..."

rm -rf temp_laipeng
git clone --depth 1 https://github.com/laipeng668/openwrt-6.x.git temp_laipeng

echo "===> Searching FG2000 / Inseego DTS..."

DTS_FILE=$(find temp_laipeng/target/linux/ \( -name "*fg2000*.dts" -o -name "*inseego*.dts" \) | head -n 1)

if [ -z "$DTS_FILE" ]; then
    echo "ERROR: FG2000 / Inseego DTS not found in laipeng repo."
    exit 1
fi

echo "✅ Found FG2000 DTS: $DTS_FILE"
cp "$DTS_FILE" "$QCOM_DTS_DIR/ipq8072-fg2000.dts"

# ---------------------------------------------------------
# 精确递归补齐 DTS/DTSI include 依赖
# 不再无脑覆盖所有 ipq8074*.dtsi，避免污染当前内核 DTS 树
# ---------------------------------------------------------
echo "===> Resolving DTSI dependencies recursively..."

copy_dtsi_recursive() {
    local src_file="$1"
    local depth="${2:-0}"

    if [ "$depth" -gt 12 ]; then
        echo "Warning: include recursion too deep at $src_file"
        return 0
    fi

    grep -E '^[[:space:]]*#include[[:space:]]+"[^"]+"' "$src_file" 2>/dev/null \
    | sed -E 's/^[[:space:]]*#include[[:space:]]+"([^"]+)".*/\1/' \
    | while read -r inc; do
        case "$inc" in
            *.dtsi|*.dts)
                ;;
            *)
                continue
                ;;
        esac

        # 只处理 qcom 同目录下的相对 include
        local inc_base
        inc_base=$(basename "$inc")

        local found
        found=$(find temp_laipeng/target/linux/ -name "$inc_base" | head -n 1 || true)

        if [ -n "$found" ]; then
            local dst="$QCOM_DTS_DIR/$inc_base"

            if [ ! -f "$dst" ]; then
                echo "  -> Inject dependency: $inc_base"
                cp "$found" "$dst"
            else
                echo "  -> Dependency already exists, keep current: $inc_base"
            fi

            copy_dtsi_recursive "$found" $((depth + 1))
        else
            echo "  -> Include not found in temp repo, assuming kernel tree provides it: $inc_base"
        fi
    done
}

copy_dtsi_recursive "$DTS_FILE"

# ---------------------------------------------------------
# 必要时额外补 NSS 相关 DTSI
# 因为 FG2000/IPQ807x NSS 树经常 include ipq8074-nss.dtsi
# ---------------------------------------------------------
echo "===> Checking NSS DTSI dependency..."

for extra in ipq8074-nss.dtsi ipq8072-nss.dtsi; do
    if [ ! -f "$QCOM_DTS_DIR/$extra" ]; then
        extra_src=$(find temp_laipeng/target/linux/ -name "$extra" | head -n 1 || true)
        if [ -n "$extra_src" ]; then
            echo "  -> Inject NSS dependency: $extra"
            cp "$extra_src" "$QCOM_DTS_DIR/$extra"
        fi
    fi
done

# ---------------------------------------------------------
# 修复 ramoops_region 缺失问题
# 你的日志里的硬失败点就是这里
# ---------------------------------------------------------
echo "===> Fixing invalid ramoops_region references..."

find "$QCOM_DTS_DIR" -name "*.dtsi" -o -name "*.dts" | while read -r f; do
    if grep -q '&ramoops_region' "$f"; then
        echo "  -> Remove invalid &ramoops_region block from: $f"
        sed -i '/&ramoops_region[[:space:]]*{/,/};/d' "$f"
    fi
done

rm -rf temp_laipeng

# =========================================================
# 2. 注册 FG2000 编译节点
# =========================================================
echo "===> Registering FG2000 build target..."

if ! grep -q "Device/inseego_fg2000" target/linux/qualcommax/image/ipq807x.mk; then
cat >> target/linux/qualcommax/image/ipq807x.mk <<'EOF'

define Device/inseego_fg2000
  DEVICE_VENDOR := Inseego
  DEVICE_MODEL := FG2000
  DEVICE_DTS := ipq8072-fg2000
  DEVICE_PACKAGES := kmod-qca-nss-dp kmod-qca-nss-drv kmod-qca-nss-drv-pppoe kmod-qca-nss-ecm kmod-shortcut-fe
endef
TARGET_DEVICES += inseego_fg2000
EOF
else
    echo "FG2000 target already registered, skip."
fi

# =========================================================
# 3. 系统底层信息修改
# =========================================================
echo "===> Optimizing system configuration..."

sed -i 's/192.168.1.1/192.168.20.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='JacobWrt'/g" package/base-files/files/bin/config_generate

if [ -f feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js ]; then
    sed -i "s#_('Firmware Version'), (L\.isObject(boardinfo\.release) ? boardinfo\.release\.description + ' / ' : '') + (luciversion || ''),#_('Firmware Version'), E('span', {}, [ (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || '') + ' / ', E('a', { href: 'https://github.com/laipeng668/openwrt-ci-roc/releases', target: '_blank', rel: 'noopener noreferrer' }, [ 'Built by Jacob $(date +'%Y-%m-%d')' ]) ]),#g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js || true
fi

# =========================================================
# 4. 依赖清理与递归依赖修复
# =========================================================
echo "===> Cleaning conflicting dependencies..."

sed -i '/mihomo-meta/d' feeds/packages/net/mihomo/Makefile 2>/dev/null || true
sed -i '/mihomo-alpha/d' feeds/packages/net/mihomo/Makefile 2>/dev/null || true
sed -i '/CONFIG_PACKAGE_kmod-oaf/d' .config 2>/dev/null || true

rm -rf tmp/info/ tmp/.config-package.in

# =========================================================
# 5. 插件注入
# =========================================================
echo "===> Injecting custom packages..."

# 注入稳定版 Mihomo 核心
rm -rf /tmp/nikki_repo package/mihomo
git clone --depth=1 https://github.com/morytyann/OpenWrt-mihomo.git /tmp/nikki_repo

if [ -d /tmp/nikki_repo/mihomo ]; then
    cp -r /tmp/nikki_repo/mihomo package/mihomo
else
    cp -r /tmp/nikki_repo package/mihomo
fi

rm -rf /tmp/nikki_repo

# 更稳的 sparse clone 函数
git_sparse_clone() {
    local branch="$1"
    local repourl="$2"
    shift 2

    local repo_name
    repo_name=$(basename "$repourl" .git)
    local tmp_dir="/tmp/sparse_${repo_name}_$$"

    rm -rf "$tmp_dir"

    echo "===> Sparse cloning $repourl branch=$branch paths=$*"

    git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl" "$tmp_dir"

    cd "$tmp_dir"
    git sparse-checkout set "$@"

    for path in "$@"; do
        if [ -e "$path" ]; then
            echo "  -> Moving $path to package/"
            rm -rf "/mnt/openwrt/package/$(basename "$path")"
            mv -f "$path" /mnt/openwrt/package/
        else
            echo "Warning: sparse path not found: $path"
        fi
    done

    cd /mnt/openwrt
    rm -rf "$tmp_dir"
}

# 注意：GitHub Actions 里源码一般在 /mnt/openwrt
cd /mnt/openwrt

git_sparse_clone aria2 https://github.com/laipeng668/packages net/aria2
git_sparse_clone nginx https://github.com/laipeng668/packages net/nginx
git_sparse_clone frp https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps

rm -rf package/luci-theme-argon package/luci-app-argon-config package/luci-theme-aurora package/luci-app-lucky package/luci-app-gecoosac

git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac

# =========================================================
# 6. 最终 defconfig 前清理
# =========================================================
echo "===> Final cleanup before defconfig..."

rm -rf tmp/info/ tmp/.config-package.in

echo "========================================================="
echo " Jacob FG2000 / IPQ807x Build Customization Finished"
echo "========================================================="
