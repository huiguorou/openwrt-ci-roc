#!/bin/bash

set -Eeuo pipefail

trap 'echo "ERROR: Jacob-script failed at line $LINENO"' ERR


# =========================================================
# Variables
# =========================================================

DTS_DIR="target/linux/qualcommax/files/arch/arm64/boot/dts/qcom"

IMAGE_FILE="target/linux/qualcommax/image/ipq807x.mk"

FG2000_DEVICE="inseego_fg2000"
FG2000_DTS="ipq8072-fg2000"

AP8220_DEVICE="aliyun_ap8220"

CUSTOM_LAN_IP="${CUSTOM_LAN_IP:-192.168.20.1}"

CUSTOM_HOSTNAME="${CUSTOM_HOSTNAME:-JacobWrt}"


echo
echo "========================================================="
echo " JacobWrt"
echo " FG2000 + Aliyun AP8220"
echo " IPQ807x / LibWrt 25.12 NSS"
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

    exit 1

fi


if [ ! -f "$IMAGE_FILE" ]; then

    echo
    echo "ERROR:"
    echo "$IMAGE_FILE does not exist."

    exit 1

fi


mkdir -p "$DTS_DIR"


# =========================================================
# 2. NSS patch policy
#
# NEVER modify upstream patch queue.
# =========================================================

echo
echo "===> NSS kernel patches:"
echo "     100% upstream-managed"


PATCH_DIR="target/linux/qualcommax/patches-6.12"


if [ -d "$PATCH_DIR" ]; then

    PATCH_COUNT="$(
        find "$PATCH_DIR" \
          -maxdepth 1 \
          -type f \
          -name '*.patch' \
          | wc -l
    )"

    echo "  -> Patch count: $PATCH_COUNT"

fi


# =========================================================
# 3. Validate AP8220 upstream profile
#
# AP8220 is upstream-supported.
# We DO NOT create or override its DTS/profile.
# =========================================================

echo
echo "===> Checking Aliyun AP8220 upstream support..."


if grep -q \
    '^define Device/aliyun_ap8220$' \
    "$IMAGE_FILE"; then

    echo "  -> Aliyun AP8220 device profile found."

else

    echo
    echo "========================================================="
    echo "ERROR:"
    echo "25.12-nss does not provide Device/aliyun_ap8220"
    echo
    echo "Do not silently generate a replacement."
    echo "Upstream device structure should be inspected first."
    echo "========================================================="

    exit 1

fi


# =========================================================
# 4. Validate AP8220 WiFi board package
# =========================================================

echo
echo "===> Checking AP8220 WiFi BDF package..."


if grep -Rqs \
    'aliyun_ap8220' \
    package/firmware/ipq-wifi \
    2>/dev/null; then

    echo "  -> ipq-wifi-aliyun_ap8220 available."

else

    echo
    echo "ERROR:"
    echo "AP8220 WiFi board package is missing."

    exit 1

fi


# =========================================================
# 5. FG2000 DTS
#
# Priority:
#
# 1. upstream target DTS
# 2. another matching FG2000/Inseego DTS
# 3. CI repo fallback
# =========================================================

echo
echo "===> Checking FG2000 DTS..."


TARGET_DTS="$DTS_DIR/${FG2000_DTS}.dts"


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

        echo "  -> Found upstream FG2000 DTS:"
        echo "     $FOUND_DTS"

        cp \
          "$FOUND_DTS" \
          "$TARGET_DTS"


    elif [ -n "${GITHUB_WORKSPACE:-}" ] && \
         [ -f "$GITHUB_WORKSPACE/devices/ipq8072-fg2000.dts" ]; then


        echo "  -> Using CI fallback FG2000 DTS."

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
        echo "========================================================="

        exit 1

    fi

fi


# =========================================================
# 6. FG2000 NSS DTSI
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

        cp \
          "$FOUND_NSS_DTSI" \
          "$TARGET_NSS_DTSI"

        echo "  -> NSS DTSI installed."

    else

        echo
        echo "ERROR:"
        echo "ipq8074-nss.dtsi not found."

        exit 1

    fi

fi


# =========================================================
# 7. FG2000 device profile
# =========================================================

echo
echo "===> Checking FG2000 profile..."


if grep -q \
    '^define Device/inseego_fg2000$' \
    "$IMAGE_FILE"; then

    echo "  -> FG2000 profile already exists."

else

    echo "  -> Adding FG2000 profile."


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
# 8. Network defaults
# =========================================================

CONFIG_GENERATE="package/base-files/files/bin/config_generate"


echo
echo "===> Configuring LAN IP..."


if [ -f "$CONFIG_GENERATE" ]; then

    if grep -Eq \
      '192\.168\.(1|2)\.1' \
      "$CONFIG_GENERATE"; then

        sed -E -i \
          "s/192\.168\.(1|2)\.1/${CUSTOM_LAN_IP}/g" \
          "$CONFIG_GENERATE"

        echo "  -> LAN IP: $CUSTOM_LAN_IP"

    else

        echo "  -> Upstream default LAN pattern changed."
        echo "     No unsafe replacement performed."

    fi

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
          "s/hostname='[^']*'/hostname='${CUSTOM_HOSTNAME}'/g" \
          "$CONFIG_GENERATE"

        echo "  -> Hostname: $CUSTOM_HOSTNAME"

    fi

fi


# =========================================================
# 10. Clean generated package metadata
# =========================================================

rm -rf \
  tmp/info \
  tmp/.config-package.in \
  2>/dev/null || true


sed -i \
  '/CONFIG_PACKAGE_kmod-oaf/d' \
  .config \
  2>/dev/null || true


# =========================================================
# 11. Package helpers
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
        echo "===> $name already provided upstream."
        echo "     Keep upstream version."

        return 0

    fi


    echo
    echo "===> Installing $name"


    rm -rf "$dest"


    git clone \
      --depth 1 \
      "$repo" \
      "$dest"

}


# =========================================================
# 12. Mihomo
# =========================================================

echo
echo "===> Checking Mihomo..."


if package_dir_exists "mihomo"; then

    echo "  -> Keep upstream Mihomo."

else

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
# 13. Themes / applications
# =========================================================

clone_if_missing \
  luci-theme-aurora \
  https://github.com/eamonxg/luci-theme-aurora.git \
  package/luci-theme-aurora


clone_if_missing \
  luci-theme-argon \
  https://github.com/jerrykuku/luci-theme-argon.git \
  package/luci-theme-argon


clone_if_missing \
  luci-app-argon-config \
  https://github.com/jerrykuku/luci-app-argon-config.git \
  package/luci-app-argon-config


clone_if_missing \
  luci-app-lucky \
  https://github.com/gdy666/luci-app-lucky.git \
  package/luci-app-lucky


# =========================================================
# 14. Final validation
# =========================================================

echo
echo "========================================================="
echo " Dual Device Validation"
echo "========================================================="


# FG2000

if [ ! -f "$TARGET_DTS" ]; then

    echo "ERROR:"
    echo "FG2000 DTS missing."

    exit 1

fi


if ! grep -q \
    '^define Device/inseego_fg2000$' \
    "$IMAGE_FILE"; then

    echo "ERROR:"
    echo "FG2000 profile missing."

    exit 1

fi


# AP8220

if ! grep -q \
    '^define Device/aliyun_ap8220$' \
    "$IMAGE_FILE"; then

    echo "ERROR:"
    echo "AP8220 profile missing."

    exit 1

fi


echo
echo "Devices:"
echo "  ✓ Inseego FG2000"
echo "  ✓ Aliyun AP8220"

echo
echo "FG2000 DTS:"
echo "  $TARGET_DTS"

echo
echo "NSS DTSI:"
echo "  $TARGET_NSS_DTSI"

echo
echo "Nikki runtime:"
echo "  ✓ kmod-dummy"
echo "  ✓ kmod-tun"

echo
echo "NSS patches:"
echo "  ✓ upstream-managed"

echo
echo "AP8220 WiFi:"
echo "  ✓ ipq-wifi-aliyun_ap8220"

echo
echo "========================================================="
echo " Jacob dual-device customization completed."
echo "========================================================="
