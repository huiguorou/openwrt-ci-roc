#!/bin/bash

# =========================================================
# 硬件核心：Inseego FG2000 适配与 NSS 补丁注入
# =========================================================
echo "===> 1. 拉取并应用高通 NSS 核心优化补丁..."
git clone --depth 1 https://github.com/laipeng668/openwrt-6.x.git temp_laipeng
mkdir -p target/linux/qualcommax/
# 兼容拷贝所有 qualcommax/ipq807x 补丁
cp -r temp_laipeng/target/linux/*/patches-6.* target/linux/qualcommax/ 2>/dev/null || true

echo "===> 2. 提取并注入 Inseego FG2000 设备树 (DTS)..."
mkdir -p target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/

# 智能查找：使用 find 命令在 laipeng668 仓库中地毯式搜索
DTS_FILE=$(find temp_laipeng/target/linux/ -name "*fg2000*.dts" -o -name "*inseego*.dts" | head -n 1)

if [ -n "$DTS_FILE" ]; then
    echo "✅ 成功从 LiBwrt 提取 DTS: $DTS_FILE"
    cp "$DTS_FILE" target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/
    DTS_FILENAME=$(basename "$DTS_FILE" .dts)
else
    echo "⚠️ 未在 LiBwrt 中找到独立 DTS 文件，尝试从本地仓库根目录寻找..."
    DTS_FILE_LOCAL=$(find $GITHUB_WORKSPACE/ -maxdepth 1 -name "*fg2000*.dts" -o -name "*inseego*.dts" | head -n 1)
    if [ -n "$DTS_FILE_LOCAL" ]; then
        echo "✅ 成功从本地仓库提取 DTS: $DTS_FILE_LOCAL"
        cp "$DTS_FILE_LOCAL" target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/
        DTS_FILENAME=$(basename "$DTS_FILE_LOCAL" .dts)
    else
        echo "❌ 警告：未找到任何 DTS 文件！将使用默认占位符盲写。"
        DTS_FILENAME="ipq8072a-inseego-fg2000"
    fi
fi

echo "===> 3. 注册 FG2000 编译节点..."
# 查漏补缺：检查是否已经被 LiBwrt 的 Patch 自动注册过，避免重复注册导致 Make 报错
if grep -q "define Device/inseego_fg2000" target/linux/qualcommax/image/*.mk 2>/dev/null; then
    echo "✅ 节点已被内核 Patch 自动注册，跳过手动追加。"
else
    echo "⚠️ 未检测到预设节点，开始安全注入..."
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

# 销毁临时素材库
rm -rf temp_laipeng

# =========================================================
# 系统底层信息修改
# =========================================================
# 修改默认IP & 固件名称
sed -i 's/
