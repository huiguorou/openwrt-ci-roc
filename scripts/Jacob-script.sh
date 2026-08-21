#!/bin/bash

set -Eeuo pipefail

trap 'echo "ERROR: Jacob-script failed at line $LINENO"' ERR


# =========================================================
# Variables
# =========================================================

DTS_DIR="target/linux/qualcommax/files/arch/arm64/boot/dts/qcom"

IMAGE_FILE="target/linux/qualcommax/image/ipq807x.mk"

DEVICE_NAME="inseego_fg2000"
DEVICE_DTS="ipq8072-fg2000"

CUSTOM_LAN_IP="${CUSTOM_LAN_IP:-192.168.20.1}"
CUSTOM_HOSTNAME="${CUSTOM_HOSTNAME:-JacobWrt}"


echo
echo "========================================================="
echo " JacobWrt"
echo " FG2000 / IPQ807x / LibWrt 25.12 NSS"
echo "========================================================="
echo


# =========================================================
# 1. Validate upstream
# =========================================================

echo "===> Checking 25.12-nss source structure..."


if [ ! -d "target/linux/qualcommax" ]; then

    echo
    echo "ERROR:"
    echo "target/linux/qualcommax does not exist."
    echo
    echo "Upstream target layout has changed."
    exit 1

fi


if [ ! -f "$IMAGE_FILE" ]; then

    echo
    echo "ERROR:"
    echo "$IMAGE_FILE does not exist."
    echo
    echo "Upstream IPQ807x image layout has changed."
    exit 1

fi


mkdir -p "$DTS_DIR"


# =========================================================
# 2. NSS kernel patch policy
#
# NEVER:
#
# find *nss*.patch
# cp *.patch
# rm *vxlan*.patch
#
# 25.12-nss owns its complete kernel patch graph.
# =========================================================

echo
echo "===> NSS kernel patch policy:"
echo "     UPSTREAM MANAGED"
echo "     NO patch injection"
echo "     NO VXLAN patch deletion"


PATCH_DIR="target/linux/qualcommax/patches-6.12"


if [ -d "$PATCH_DIR" ]; then

    PATCH_COUNT="$(
        find "$PATCH_DIR" \
          -maxdepth 1 \
          -type f \
          -name '*.patch' \
          | wc -l
    )"

    echo "  -> qualcommax 6.12 patches: $PATCH_COUNT"

fi


# =========================================================
# 3. FG2000 DTS
# =========================================================

echo
echo "===> Checking FG2000 DTS..."


TARGET_DTS="$DTS_DIR/${DEVICE_DTS}.dts"


if [ -f "$TARGET_DTS" ]; then

    echo "  -> Upstream already provides:"
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

        echo "  -> Found compatible upstream DTS:"
        echo "     $FOUND_DTS"

        cp \
          "$FOUND_DTS" \
          "$TARGET_DTS"


    elif [ -n "${GITHUB_WORKSPACE:-}" ] && \
         [ -f "$GITHUB_WORKSPACE/devices/ipq8072-fg2000.dts" ]; then


        echo "  -> Using CI repository fallback:"
        echo "     devices/ipq8072-fg2000.dts"


        cp \
          "$GITHUB_WORKSPACE/devices/ipq8072-fg2000.dts" \
          "$TARGET_DTS"


    else

        echo
        echo "========================================================="
        echo "ERROR: FG2000 DTS not found."
        echo
        echo "Recommended fallback:"
        echo
        echo "devices/ipq8072-fg2000.dts"
        echo
        echo "This should contain your last-known-good FG2000 DTS."
        echo "========================================================="

        exit 1

    fi

fi


# =========================================================
# 4. NSS DTSI
# =========================================================

echo
echo "===> Checking ipq8074-nss.dtsi..."


TARGET_NSS_DTSI="$DTS_DIR/ipq8074-nss.dtsi"


if [ -f "$TARGET_NSS_DTSI" ]; then

    echo "  -> NSS DTSI ready:"
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

        echo "  -> Found upstream NSS DTSI:"
        echo "     $FOUND_NSS_DTSI"

        cp \
          "$FOUND_NSS_DTSI" \
          "$TARGET_NSS_DTSI"

    else

        echo
        echo "========================================================="
        echo "ERROR: ipq8074-nss.dtsi not found."
        echo
        echo "25.12-nss IPQ807x NSS device-tree support appears"
        echo "to have changed."
        echo "========================================================="

        exit 1

    fi

fi


# =========================================================
# 5. Device profile
# =========================================================

echo
echo "===> Checking FG2000 device profile..."


if grep -q \
    '^define Device/inseego_fg2000$' \
    "$IMAGE_FILE"; then

    echo "  -> FG2000 profile already exists upstream."

else

    echo "  -> Installing FG2000 profile."

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


if ! grep -q \
    '^define Device/inseego_fg2000$' \
    "$IMAGE_FILE"; then

    echo "ERROR: Failed to register FG2000 profile."
    exit 1

fi


# =========================================================
# 6. Network defaults
# =========================================================

CONFIG_GENERATE="package/base-files/files/bin/config_generate"


echo
echo "===> Configuring LAN IP..."


if [ -f "$CONFIG_GENERATE" ]; then

    # 兼容可能出现的：
    #
    # 192.168.1.1
    # 192.168.2.1
    #
    # 只修改 OpenWrt LAN 默认地址模式。

    if grep -Eq \
      '192\.168\.(1|2)\.1' \
      "$CONFIG_GENERATE"; then

        sed -E -i \
          "s/192\.168\.(1|2)\.1/${CUSTOM_LAN_IP}/g" \
          "$CONFIG_GENERATE"

        echo "  -> LAN IP: $CUSTOM_LAN_IP"

    else

        echo "  -> INFO:"
        echo "     Upstream LAN template changed."
        echo "     No unsafe replacement performed."

    fi

else

    echo "  -> INFO:"
    echo "     config_generate not found."
    echo "     LAN IP modification skipped."

fi


# =========================================================
# 7. Hostname
# =========================================================

echo
echo "===> Configuring hostname..."


if [ -f "$CONFIG_GENERATE" ]; then

    if grep -q \
      "hostname='" \
      "$CONFIG_GENERATE"; then

        sed -i \
          "s/hostname='[^']*'/hostname='${CUSTOM_HOSTNAME}'/g" \
          "$CONFIG_GENERATE"

        echo "  -> Hostname: $CUSTOM_HOSTNAME"

    else

        echo "  -> INFO:"
        echo "     hostname definition changed upstream."
        echo "     Hostname customization skipped."

    fi

fi


# =========================================================
# 8. Cleanup generated metadata
# =========================================================

echo
echo "===> Cleaning package metadata..."


rm -rf \
  tmp/info \
  tmp/.config-package.in \
  2>/dev/null || true


sed -i \
  '/CONFIG_PACKAGE_kmod-oaf/d' \
  .config \
  2>/dev/null || true


# =========================================================
# 9. Package helpers
# =========================================================

package_dir_exists() {

    local package_name="$1"

    find \
      package \
      feeds \
      -type d \
      -name "$package_name" \
      -print -quit \
      2>/dev/null \
      | grep -q .

}


clone_if_missing() {

    local name="$1"
    local repo="$2"
    local dest="$3"


    if package_dir_exists "$name"; then

        echo
        echo "===> $name"
        echo "     Already provided by 25.12-nss."
        echo "     Keep upstream package."

        return 0

    fi


    echo
    echo "===> Installing $name"
    echo "     $repo"


    rm -rf "$dest"


    git clone \
      --depth 1 \
      "$repo" \
      "$dest"

}


# =========================================================
# 10. Mihomo
#
# 25.12-nss may already provide mihomo.
# Don't override if present.
# =========================================================

echo
echo "===> Checking Mihomo..."


if package_dir_exists "mihomo"; then

    echo "  -> Mihomo already provided upstream."
    echo "     Keep 25.12-nss version."

else

    echo "  -> Installing external Mihomo package."

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

fi


# =========================================================
# 11. Aurora
#
# 25.12-nss reportedly uses Aurora by default.
# Do NOT override upstream if it already exists.
# =========================================================

clone_if_missing \
  luci-theme-aurora \
  https://github.com/eamonxg/luci-theme-aurora.git \
  package/luci-theme-aurora


# =========================================================
# 12. Argon
# =========================================================

clone_if_missing \
  luci-theme-argon \
  https://github.com/jerrykuku/luci-theme-argon.git \
  package/luci-theme-argon


clone_if_missing \
  luci-app-argon-config \
  https://github.com/jerrykuku/luci-app-argon-config.git \
  package/luci-app-argon-config


# =========================================================
# 13. Lucky
# =========================================================

clone_if_missing \
  luci-app-lucky \
  https://github.com/gdy666/luci-app-lucky.git \
  package/luci-app-lucky


# =========================================================
# 14. LuCI branding
#
# Keep upstream JavaScript unchanged.
# =========================================================

echo
echo "===> LuCI branding policy:"
echo "     Keep upstream LuCI implementation."


# =========================================================
# 15. Final validation
# =========================================================

echo
echo "========================================================="
echo " FG2000 / IPQ807x / 25.12 NSS validation"
echo "========================================================="


if [ ! -f "$TARGET_DTS" ]; then

    echo "ERROR: Missing:"
    echo "$TARGET_DTS"

    exit 1

fi


if [ ! -f "$TARGET_NSS_DTSI" ]; then

    echo "ERROR: Missing:"
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
echo "Device:"
echo "  Inseego FG2000"

echo
echo "DTS:"
echo "  $TARGET_DTS"

echo
echo "NSS DTSI:"
echo "  $TARGET_NSS_DTSI"

echo
echo "LAN:"
echo "  $CUSTOM_LAN_IP"

echo
echo "Hostname:"
echo "  $CUSTOM_HOSTNAME"

echo
echo "Mandatory runtime:"
echo "  kmod-dummy"
echo "  kmod-tun"

echo
echo "NSS:"
echo "  kmod-qca-nss-dp"
echo "  kmod-qca-nss-drv"
echo "  kmod-qca-nss-drv-pppoe"
echo "  kmod-qca-nss-ecm"

echo
echo "Kernel patches:"
echo "  100% upstream-managed"

echo
echo "========================================================="
echo " Jacob 25.12 customization completed successfully."
echo "========================================================="
