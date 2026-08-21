#!/bin/bash

set -Eeuo pipefail

trap 'echo "ERROR line $LINENO"; exit 1' ERR


DTS_DIR="target/linux/qualcommax/files/arch/arm64/boot/dts/qcom"
IMAGE_MK="target/linux/qualcommax/image/ipq807x.mk"

mkdir -p $DTS_DIR


echo "Checking 25.12 NSS source"


# 不修改上游 NSS patch

if [ -d target/linux/qualcommax/patches-6.12 ]; then
    echo "Using upstream NSS patches"
fi



# ==================================================
# AP8220
# ==================================================

echo "Checking AP8220"


grep -q \
"define Device/aliyun_ap8220" \
$IMAGE_MK || {

echo "Missing AP8220 profile"
exit 1

}



# ==================================================
# FG2000 DTS
# ==================================================

FG_DTS=$DTS_DIR/ipq8072-fg2000.dts


if [ -f "$FG_DTS" ]; then

echo "FG2000 DTS exists"

else


FOUND=$(find target/linux/qualcommax \
-name "*fg2000*.dts" \
-o -name "*inseego*.dts" \
| head -n1 || true)


if [ -n "$FOUND" ]; then

cp "$FOUND" "$FG_DTS"

else


if [ -f "$GITHUB_WORKSPACE/devices/ipq8072-fg2000.dts" ]; then

cp \
$GITHUB_WORKSPACE/devices/ipq8072-fg2000.dts \
$FG_DTS

else

echo "Missing FG2000 DTS"
exit 1

fi

fi

fi



# ==================================================
# NSS DTSI
# ==================================================

NSS_DTSI=$DTS_DIR/ipq8074-nss.dtsi


if [ ! -f "$NSS_DTSI" ]; then


FOUND=$(find target/linux/qualcommax \
-name ipq8074-nss.dtsi \
| head -n1 || true)


if [ -n "$FOUND" ]; then

cp "$FOUND" "$NSS_DTSI"

else

echo "Missing NSS DTSI"
exit 1

fi


fi



# ==================================================
# FG2000 Image Profile
# ==================================================

if ! grep -q \
"define Device/inseego_fg2000" \
$IMAGE_MK
then


cat >> $IMAGE_MK <<'EOF'


define Device/inseego_fg2000
  DEVICE_VENDOR := Inseego
  DEVICE_MODEL := FG2000
  DEVICE_DTS := ipq8072-fg2000
  DEVICE_PACKAGES := \
    kmod-qca-nss-dp \
    kmod-qca-nss-drv \
    kmod-qca-nss-drv-pppoe \
    kmod-qca-nss-ecm \
    kmod-dummy \
    kmod-tun
endef

TARGET_DEVICES += inseego_fg2000

EOF


fi



# ==================================================
# LAN
# ==================================================

CFG="package/base-files/files/bin/config_generate"


if [ -f "$CFG" ]; then

sed -i \
"s/192.168.[12].1/${CUSTOM_LAN_IP}/g" \
$CFG || true


sed -i \
"s/hostname='.*'/hostname='${CUSTOM_HOSTNAME}'/g" \
$CFG || true

fi



# ==================================================
# Optional packages
# ==================================================

clone_pkg(){

NAME=$1
URL=$2
DIR=$3


if find package feeds \
-name "$NAME" \
-type d | grep -q .
then

echo "$NAME exists"

else

git clone \
--depth 1 \
$URL \
$DIR

fi

}



clone_pkg \
luci-theme-aurora \
https://github.com/eamonxg/luci-theme-aurora \
package/luci-theme-aurora



clone_pkg \
luci-theme-argon \
https://github.com/jerrykuku/luci-theme-argon \
package/luci-theme-argon



clone_pkg \
luci-app-lucky \
https://github.com/gdy666/luci-app-lucky \
package/luci-app-lucky



echo
echo "Jacob customization completed"
