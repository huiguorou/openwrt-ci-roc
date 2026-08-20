#!/bin/bash

set -Eeuo pipefail

trap 'echo "ERROR: Jacob-script failed at line $LINENO"' ERR


# =========================================================
# 基础变量
# =========================================================

DTS_DIR="target/linux/qualcommax/files/arch/arm64/boot/dts/qcom"
IMAGE_FILE="target/linux/qualcommax/image/ipq807x.mk"

DEVICE_NAME="inseego_fg2000"
DEVICE_DTS="ipq8072-fg2000"


echo
echo "========================================================="
echo " JacobWrt - FG2000 / IPQ807x / NSS"
echo "========================================================="
echo


# =========================================================
# 1. 检查 upstream source tree
# =========================================================

echo "===> Checking upstream source structure..."

if [ ! -d target/linux/qualcommax ]; then

    echo "ERROR:"
    echo "target/linux/qualcommax does not exist."
    echo
    echo "Upstream target layout has changed."

    exit 1

fi


if [ ! -f "$IMAGE_FILE" ]; then

    echo "ERROR:"
    echo "$IMAGE_FILE does not exist."
    echo
    echo "Upstream IPQ807x image layout has changed."

    exit 1

fi


mkdir -p "$DTS_DIR"


# =========================================================
# 2. NSS Kernel Patch Queue
#
# 非常重要：
#
# main-nss 自带正确的 qualcommax/IPQ807x NSS patches。
#
# Jacob-script 不允许：
#
#   find "*nss*.patch"
#   cp *.patch
#   rm *vxlan*.patch
#   修改 kernel patch numbering
#
# =========================================================

echo
echo "===> Keeping upstream NSS kernel patch queue untouched."

PATCH_DIR="target/linux/qualcommax/patches-6.12"

if [ -d "$PATCH_DIR" ]; then

    PATCH_COUNT="$(
        find "$PATCH_DIR" \
          -maxdepth 1 \
          -type f \
          -name '*.patch' \
          | wc -l
    )"

    echo "  -> Upstream patch count: $PATCH_COUNT"

fi


# =========================================================
# 3. 防御检查
#
# 不允许明显属于 IPQ9574 / qualcommbe 的 patch
# 被我们自己的脚本加入 qualcommax。
#
# 注意：
# 如果未来 upstream 本身合理引用 IPQ9574，
# 这里可能需要重新评估。
#
# 目前只打印，不主动删除任何 patch。
# =========================================================

echo
echo "===> Auditing qualcommax patch queue..."

IPQ9574_PATCHES="$(
    grep -RIl \
      -e 'nsscc-ipq9574' \
      "$PATCH_DIR" \
      2>/dev/null \
      || true
)"

if [ -n "$IPQ9574_PATCHES" ]; then

    echo
    echo "WARNING:"
    echo "IPQ9574-specific patch references detected:"
    echo
    echo "$IPQ9574_PATCHES"
    echo
    echo "No patches will be deleted automatically."
    echo "Kernel Patch Preflight will verify whether upstream"
    echo "considers this patch queue valid."
    echo

fi


# =========================================================
# 4. FG2000 DTS
#
# 优先级：
#
# A. 当前 upstream 已经包含标准目标文件
# B. 当前 qualcommax 中找到 fg2000/inseego DTS
# C. CI repo 中 devices/ipq8072-fg2000.dts
# D. 否则 fail
#
# 不再 clone 第二份 OpenWrt。
# =========================================================

echo
echo "===> Checking FG2000 DTS..."

TARGET_DTS="$DTS_DIR/${DEVICE_DTS}.dts"


if [ -f "$TARGET_DTS" ]; then

    echo "  -> FG2000 DTS already exists:"
    echo "     $TARGET_DTS"


else

    FOUND_DTS="$(
        find target/linux/qualcommax \
          -type f \
          \( \
            -iname '*fg2000*.dts' \
            -o \
            -iname '*inseego*.dts' \
          \) \
          | head -n1 \
          || true
    )"


    if [ -n "$FOUND_DTS" ]; then

        echo "  -> Found upstream FG2000/Inseego DTS:"
        echo "     $FOUND_DTS"

        cp \
          "$FOUND_DTS" \
          "$TARGET_DTS"


    elif [ -n "${GITHUB_WORKSPACE:-}" ] && \
         [ -f "$GITHUB_WORKSPACE/devices/ipq8072-fg2000.dts" ]; then

        echo "  -> Using CI repository fallback DTS:"

        echo "     $GITHUB_WORKSPACE/devices/ipq8072-fg2000.dts"

        cp \
          "$GITHUB_WORKSPACE/devices/ipq8072-fg2000.dts" \
          "$TARGET_DTS"


    else

        echo
        echo "========================================================="
        echo "ERROR: FG2000 DTS not found."
        echo
        echo "Expected upstream file:"
        echo
        echo "  $TARGET_DTS"
        echo
        echo "or another *fg2000*.dts / *inseego*.dts under:"
        echo
        echo "  target/linux/qualcommax"
        echo
        echo "Recommended fallback:"
        echo
        echo "  devices/ipq8072-fg2000.dts"
        echo "========================================================="

        exit 1

    fi

fi


# =========================================================
# 5. ipq8074-nss.dtsi
# =========================================================

echo
echo "===> Checking ipq8074-nss.dtsi..."

TARGET_NSS_DTSI="$DTS_DIR/ipq8074-nss.dtsi"


if [ -f "$TARGET_NSS_DTSI" ]; then

    echo "  -> Found:"
    echo "     $TARGET_NSS_DTSI"


else

    FOUND_NSS_DTSI="$(
        find target/linux/qualcommax \
          -type f \
          -name 'ipq8074-nss.dtsi' \
          | head -n1 \
          || true
    )"


    if [ -n "$FOUND_NSS_DTSI" ]; then

        echo "  -> Found NSS DTSI:"
        echo "     $FOUND_NSS_DTSI"

        cp \
          "$FOUND_NSS_DTSI" \
          "$TARGET_NSS_DTSI"


    else

        echo
        echo "========================================================="
        echo "ERROR: ipq8074-nss.dtsi not found."
        echo
        echo "The selected main-nss source no longer appears"
        echo "to contain IPQ807x NSS DTS integration."
        echo "========================================================="

        exit 1

    fi

fi


# =========================================================
# 6. 注册 FG2000 Device Profile
#
# 如果 upstream 已经提供，则完全不重复添加。
# =========================================================

echo
echo "===> Checking FG2000 device profile..."


if grep -q \
    '^define Device/inseego_fg2000$' \
    "$IMAGE_FILE"; then

    echo "  -> FG2000 device profile already exists upstream."


else

    echo "  -> Adding FG2000 device profile."

    cat >> "$IMAGE_FILE" <<'EOF'


# =========================================================
# Inseego FG2000 - JacobWrt
# =========================================================

define Device/inseego_fg2000
  DEVICE_VENDOR := Inseego
  DEVICE_MODEL := FG2000
  DEVICE_DTS := ipq8072-fg2000
  DEVICE_PACKAGES := \
    kmod-qca-nss-dp \
    kmod-qca-nss-drv \
    kmod-qca-nss-drv-pppoe \
    kmod-qca-nss-ecm \
    kmod-tun \
    kmod-dummy
endef

TARGET_DEVICES += inseego_fg2000
EOF

fi


# =========================================================
# 7. 验证 FG2000 profile
# =========================================================

if ! grep -q \
    '^define Device/inseego_fg2000$' \
    "$IMAGE_FILE"; then

    echo "ERROR: Failed to register FG2000 profile."
    exit 1

fi


# =========================================================
# 8. LAN IP
# =========================================================

echo
echo "===> Configuring LAN address..."

CONFIG_GENERATE="package/base-files/files/bin/config_generate"


if [ -f "$CONFIG_GENERATE" ]; then

    if grep -q \
        '192\.168\.1\.1' \
        "$CONFIG_GENERATE"; then

        sed -i \
          's/192\.168\.1\.1/192.168.20.1/g' \
          "$CONFIG_GENERATE"

        echo "  -> LAN IP: 192.168.20.1"


    else

        echo "  -> INFO: upstream LAN template changed."
        echo "     Automatic IP replacement skipped."

    fi


else

    echo "  -> INFO: config_generate no longer exists."
    echo "     LAN customization skipped."

fi


# =========================================================
# 9. Hostname
# =========================================================

echo
echo "===> Configuring hostname..."


if [ -f "$CONFIG_GENERATE" ]; then

    if grep -q \
        "hostname='" \
        "$CONFIG_GENERATE"; then

        sed -i \
          "s/hostname='[^']*'/hostname='JacobWrt'/g" \
          "$CONFIG_GENERATE"

        echo "  -> Hostname: JacobWrt"


    else

        echo "  -> INFO: hostname layout changed."
        echo "     Hostname customization skipped."

    fi

fi


# =========================================================
# 10. 清理旧 package metadata
# =========================================================

echo
echo "===> Cleaning generated package metadata..."

rm -rf \
  tmp/info \
  tmp/.config-package.in \
  2>/dev/null || true

sed -i \
  '/CONFIG_PACKAGE_kmod-oaf/d' \
  .config \
  2>/dev/null || true


# =========================================================
# 11. Package Clone Helper
# =========================================================

clone_package() {

    local repo="$1"
    local dest="$2"
    local branch="${3:-}"

    echo
    echo "===> Installing:"
    echo "     $repo"
    echo "  -> $dest"

    rm -rf "$dest"

    if [ -n "$branch" ]; then

        git clone \
          --depth 1 \
          --single-branch \
          --branch "$branch" \
          "$repo" \
          "$dest"

    else

        git clone \
          --depth 1 \
          "$repo" \
          "$dest"

    fi

}


# =========================================================
# 12. Mihomo
# =========================================================

echo
echo "===> Installing Mihomo..."

TMP_MIHOMO="$(mktemp -d)"


git clone \
  --depth 1 \
  https://github.com/morytyann/OpenWrt-mihomo.git \
  "$TMP_MIHOMO"


rm -rf package/mihomo


if [ -d "$TMP_MIHOMO/mihomo" ]; then

    cp -a \
      "$TMP_MIHOMO/mihomo" \
      package/mihomo


else

    mkdir -p package/mihomo

    cp -a \
      "$TMP_MIHOMO"/. \
      package/mihomo/

fi


rm -rf "$TMP_MIHOMO"


# =========================================================
# 13. Themes / Applications
# =========================================================

clone_package \
  https://github.com/jerrykuku/luci-theme-argon.git \
  package/luci-theme-argon


clone_package \
  https://github.com/jerrykuku/luci-app-argon-config.git \
  package/luci-app-argon-config


clone_package \
  https://github.com/eamonxg/luci-theme-aurora.git \
  package/luci-theme-aurora


clone_package \
  https://github.com/gdy666/luci-app-lucky.git \
  package/luci-app-lucky


# =========================================================
# 14. LuCI branding
#
# 不再用复杂 sed 重写 LuCI JS。
#
# 这是上游更新时非常容易失效的部分。
# 稳定性优先。
# =========================================================

echo
echo "===> LuCI branding..."

STATUS_JS="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"


if [ -f "$STATUS_JS" ]; then

    echo "  -> LuCI system status source detected."
    echo "  -> Keep upstream implementation unchanged."

fi


# =========================================================
# 15. 最终硬件验证
# =========================================================

echo
echo "========================================================="
echo " FG2000 / NSS pre-build validation"
echo "========================================================="


if [ ! -f "$TARGET_DTS" ]; then

    echo "ERROR: Missing FG2000 DTS:"
    echo "$TARGET_DTS"

    exit 1

fi


if [ ! -f "$TARGET_NSS_DTSI" ]; then

    echo "ERROR: Missing ipq8074-nss.dtsi:"
    echo "$TARGET_NSS_DTSI"

    exit 1

fi


if ! grep -q \
    '^define Device/inseego_fg2000$' \
    "$IMAGE_FILE"; then

    echo "ERROR: Missing FG2000 image profile."

    exit 1

fi


echo
echo "DTS:"
echo "  $TARGET_DTS"

echo
echo "NSS DTSI:"
echo "  $TARGET_NSS_DTSI"

echo
echo "Image profile:"
echo "  inseego_fg2000"

echo
echo "Required runtime modules:"
echo "  kmod-qca-nss-dp"
echo "  kmod-qca-nss-drv"
echo "  kmod-qca-nss-drv-pppoe"
echo "  kmod-qca-nss-ecm"
echo "  kmod-tun"
echo "  kmod-dummy"

echo
echo "Kernel patches:"
echo "  upstream-managed"

echo
echo "========================================================="
echo " Jacob customization completed successfully."
echo "========================================================="
