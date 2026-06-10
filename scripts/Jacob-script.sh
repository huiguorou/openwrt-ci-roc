#!/bin/bash
set -e

# =========================================================
# Jacob FG2000 / IPQ807x ImmortalWrt Build Custom Script
# Target: Inseego FG2000
# Kernel: 6.12.x
# Goal: FG2000 DTS + NSS patches + NSS packages + LuCI plugins
# =========================================================

ROOT_DIR="$(pwd)"
PATCH_DIR="target/linux/qualcommax/patches-6.12"
DTS_DIR="target/linux/qualcommax/files/arch/arm64/boot/dts/qcom"
IMAGE_MK="target/linux/qualcommax/image/ipq807x.mk"

LAIPENG_REPO="https://github.com/laipeng668/openwrt-6.x.git"
QOSMIO_NSS_PACKAGES="https://github.com/qosmio/nss-packages.git"

echo "========================================================="
echo " Jacob FG2000 / IPQ807x Build Customization Started"
echo "========================================================="


# =========================================================
# Helper functions
# =========================================================

safe_rm_dir() {
  local d="$1"
  [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
}

clone_or_update_clean() {
  local repo="$1"
  local dir="$2"
  local branch="${3:-}"

  safe_rm_dir "$dir"

  if [ -n "$branch" ]; then
    git clone --depth=1 -b "$branch" --single-branch "$repo" "$dir"
  else
    git clone --depth=1 "$repo" "$dir"
  fi
}

is_bad_soc_patch() {
  local p="$1"

  # 这些是这次云编译失败的根因类型：其他 SoC 或高版本 CMN PLL/DTS backport
  if echo "$p" | grep -Eiq 'ipq9574|ipq5018|ipq5424|ipq5332|cmn.?pll|qcom,ipq.*cmn.*pll'; then
    return 0
  fi

  if grep -Eiq 'ipq9574|ipq5018|ipq5424|ipq5332|cmn.?pll|qcom,ipq.*cmn.*pll' "$p"; then
    return 0
  fi

  # 非 IPQ807x 的 DTS 直接排除
  if grep -Eiq 'arch/arm64/boot/dts/qcom/ipq(50|53|54|60|95)' "$p"; then
    return 0
  fi

  return 1
}

is_nss_related_patch() {
  local p="$1"
  local base
  base="$(basename "$p")"

  # 允许的 NSS 相关关键字
  if echo "$base" | grep -Eiq 'nss|qca-nss|nss-dp|nss-drv|ecm|shortcut|sfe|pppoe|ppe|edma|ipq807'; then
    return 0
  fi

  if grep -Eiq 'qca.?nss|nss-dp|nss-drv|qca-nss-ecm|shortcut-fe|ecm|pppoe|edma|ppe|ipq8074|ipq8072|ipq807x' "$p"; then
    return 0
  fi

  return 1
}

import_nss_patches_from_repo() {
  local src_repo_dir="$1"
  local copied=0

  echo "===> Importing filtered NSS patches from: $src_repo_dir"

  mkdir -p "$PATCH_DIR"

  # 清理之前可能错误注入的补丁
  echo "===> Cleaning bad non-IPQ807x / CMN PLL patches..."
  rm -f "$PATCH_DIR"/*ipq9574*.patch 2>/dev/null || true
  rm -f "$PATCH_DIR"/*ipq5018*.patch 2>/dev/null || true
  rm -f "$PATCH_DIR"/*ipq5424*.patch 2>/dev/null || true
  rm -f "$PATCH_DIR"/*ipq5332*.patch 2>/dev/null || true
  rm -f "$PATCH_DIR"/*cmn*.patch 2>/dev/null || true
  rm -f "$PATCH_DIR"/*CMN*.patch 2>/dev/null || true
  rm -f "$PATCH_DIR"/*pll*.patch 2>/dev/null || true
  rm -f "$PATCH_DIR"/*PLL*.patch 2>/dev/null || true

  # 优先只取 qualcommax/patches-6.12
  if [ -d "$src_repo_dir/target/linux/qualcommax/patches-6.12" ]; then
    SEARCH_ROOTS="$src_repo_dir/target/linux/qualcommax/patches-6.12"
  else
    SEARCH_ROOTS="$src_repo_dir/target/linux"
  fi

  find $SEARCH_ROOTS -type f -name "*.patch" | sort | while read -r p; do
    base="$(basename "$p")"

    if is_bad_soc_patch "$p"; then
      echo "Skip bad SoC/CMN patch: $base"
      continue
    fi

    if is_nss_related_patch "$p"; then
      echo "Copy NSS patch: $base"
      cp -f "$p" "$PATCH_DIR/$base"
      copied=$((copied + 1))
    else
      echo "Skip unrelated patch: $base"
    fi
  done

  echo "===> NSS patch import finished."
}

copy_fg2000_dts() {
  local src_repo_dir="$1"

  echo "===> Extracting Inseego FG2000 DTS..."

  mkdir -p "$DTS_DIR"

  DTS_FILE="$(find "$src_repo_dir/target/linux" -type f \( -iname "*fg2000*.dts" -o -iname "*inseego*.dts" \) | head -n 1 || true)"

  if [ -z "$DTS_FILE" ]; then
    echo "ERROR: FG2000 DTS not found in $src_repo_dir"
    exit 1
  fi

  echo "Found FG2000 DTS: $DTS_FILE"

  # 强制统一文件名，确保 DEVICE_DTS 可稳定匹配
  cp -f "$DTS_FILE" "$DTS_DIR/ipq8072-fg2000.dts"

  # 如果 DTS 内部 model/compatible 不规范，这里不硬改，避免破坏引用。
  echo "DTS installed as: $DTS_DIR/ipq8072-fg2000.dts"
}

register_fg2000_device() {
  echo "===> Registering Inseego FG2000 image target..."

  if [ ! -f "$IMAGE_MK" ]; then
    echo "ERROR: $IMAGE_MK not found"
    exit 1
  fi

  if grep -q "Device/inseego_fg2000" "$IMAGE_MK"; then
    echo "FG2000 device target already exists, skip append."
    return 0
  fi

  cat >> "$IMAGE_MK" <<'EOF'

define Device/inseego_fg2000
  DEVICE_VENDOR := Inseego
  DEVICE_MODEL := FG2000
  DEVICE_DTS := ipq8072-fg2000
  DEVICE_PACKAGES := \
	kmod-qca-nss-dp \
	kmod-qca-nss-drv \
	kmod-qca-nss-drv-pppoe \
	kmod-qca-nss-ecm \
	kmod-shortcut-fe
endef
TARGET_DEVICES += inseego_fg2000

EOF

  echo "FG2000 target appended to $IMAGE_MK"
}

install_nss_packages() {
  echo "===> Installing NSS package feed..."

  # qosmio/nss-packages 是 OpenWrt NSS package feed，常用于 IPQ807x NSS 构建
  # 放在 package/nss-packages 下，OpenWrt 会自动扫描子目录 Makefile
  if [ ! -d "package/nss-packages" ]; then
    git clone --depth=1 "$QOSMIO_NSS_PACKAGES" package/nss-packages
  else
    echo "package/nss-packages already exists, skip clone."
  fi

  # 如果 laipeng 源里也带 qca-nss 包，尽量补充，不覆盖已有目录
  if [ -d "temp_laipeng/package" ]; then
    echo "===> Searching laipeng NSS packages..."

    for d in \
      qca-nss-drv \
      qca-nss-ecm \
      qca-nss-clients \
      qca-ssdk \
      qca-ssdk-shell \
      shortcut-fe
    do
      FOUND_DIR="$(find temp_laipeng/package -maxdepth 4 -type d -name "$d" | head -n 1 || true)"
      if [ -n "$FOUND_DIR" ] && [ ! -d "package/$d" ]; then
        echo "Copy package from laipeng: $d"
        cp -rf "$FOUND_DIR" "package/$d"
      fi
    done
  fi
}

git_sparse_clone() {
  local branch="$1"
  local repourl="$2"
  shift 2

  local repodir
  repodir="$(basename "$repourl" .git)"

  safe_rm_dir "$repodir"

  echo "===> Sparse cloning $repourl branch=$branch paths=$*"

  git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl" "$repodir"
  cd "$repodir"

  git sparse-checkout set "$@"

  for path in "$@"; do
    if [ -e "$path" ]; then
      echo "Move sparse package: $path"
      mv -f "$path" ../package/
    else
      echo "WARNING: Sparse path not found: $path"
    fi
  done

  cd "$ROOT_DIR"
  rm -rf "$repodir"
}


# =========================================================
# 1. Hardware core: FG2000 DTS + filtered NSS patches
# =========================================================

echo "===> 1. Cloning NSS/DTS source repo..."
clone_or_update_clean "$LAIPENG_REPO" temp_laipeng

mkdir -p "$PATCH_DIR"
mkdir -p "$DTS_DIR"

copy_fg2000_dts temp_laipeng
import_nss_patches_from_repo temp_laipeng
install_nss_packages
register_fg2000_device


# =========================================================
# 2. Feeds and base system customization
# =========================================================

echo "===> 2. Updating and installing feeds..."

./scripts/feeds update -a
./scripts/feeds install -a

echo "===> Setting default LAN IP and hostname..."

if [ -f package/base-files/files/bin/config_generate ]; then
  sed -i 's/192.168.1.1/192.168.20.1/g' package/base-files/files/bin/config_generate
  sed -i "s/hostname='.*'/hostname='JacobWrt'/g" package/base-files/files/bin/config_generate
else
  echo "WARNING: config_generate not found, skip LAN IP/hostname customization."
fi

echo "===> Modifying LuCI firmware signature..."

LUCI_STATUS_JS="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"

if [ -f "$LUCI_STATUS_JS" ]; then
  BUILD_DATE="$(date +'%Y-%m-%d')"

  sed -i "s#_('Firmware Version'), (L\.isObject(boardinfo\.release) ? boardinfo\.release\.description + ' / ' : '') + (luciversion || ''),#_('Firmware Version'), E('span', {}, [ (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || '') + ' / ', E('a', { href: 'https://github.com/laipeng668/openwrt-ci-roc/releases', target: '_blank', rel: 'noopener noreferrer' }, [ 'Built by Jacob ${BUILD_DATE}' ]) ]),#g" "$LUCI_STATUS_JS" || true
else
  echo "WARNING: LuCI status JS not found, skip firmware signature modification."
fi


# =========================================================
# 3. Dependency cleanup
# =========================================================

echo "===> 3. Fine-grained cleanup for known deadlock/conflict packages..."

# 禁用会导致递归死锁的冲突源
sed -i '/mihomo-meta/d' feeds/packages/net/mihomo/Makefile 2>/dev/null || true
sed -i '/mihomo-alpha/d' feeds/packages/net/mihomo/Makefile 2>/dev/null || true

# 防止不存在或冲突的 kmod-oaf 卡住配置
sed -i '/CONFIG_PACKAGE_kmod-oaf/d' .config 2>/dev/null || true


# =========================================================
# 4. Third-party packages and LuCI apps
# =========================================================

echo "===> 4. Injecting third-party packages..."

# 稳定版 Mihomo 核心
safe_rm_dir /tmp/nikki_repo
safe_rm_dir package/mihomo

git clone --depth=1 https://github.com/morytyann/OpenWrt-mihomo.git /tmp/nikki_repo

if [ -d /tmp/nikki_repo/mihomo ]; then
  cp -rf /tmp/nikki_repo/mihomo package/mihomo
else
  cp -rf /tmp/nikki_repo package/mihomo
fi

rm -rf /tmp/nikki_repo

# 第三方插件库
git_sparse_clone aria2 https://github.com/laipeng668/packages net/aria2
git_sparse_clone nginx https://github.com/laipeng668/packages net/nginx
git_sparse_clone frp https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps

# Themes and apps
safe_rm_dir package/luci-theme-argon
safe_rm_dir package/luci-theme-aurora
safe_rm_dir package/luci-app-lucky
safe_rm_dir package/luci-app-gecoosac

git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac


# =========================================================
# 5. Optional config reinforcement
# =========================================================

echo "===> 5. Reinforcing target config if .config exists..."

if [ -f ".config" ]; then
  # 选中 FG2000 target
  ./scripts/config -d TARGET_MULTI_PROFILE 2>/dev/null || true
  ./scripts/config -e TARGET_qualcommax 2>/dev/null || true
  ./scripts/config -e TARGET_qualcommax_ipq807x 2>/dev/null || true
  ./scripts/config -e TARGET_qualcommax_ipq807x_DEVICE_inseego_fg2000 2>/dev/null || true

  # NSS packages
  ./scripts/config -m PACKAGE_kmod-qca-nss-dp 2>/dev/null || true
  ./scripts/config -m PACKAGE_kmod-qca-nss-drv 2>/dev/null || true
  ./scripts/config -m PACKAGE_kmod-qca-nss-drv-pppoe 2>/dev/null || true
  ./scripts/config -m PACKAGE_kmod-qca-nss-ecm 2>/dev/null || true
  ./scripts/config -m PACKAGE_kmod-shortcut-fe 2>/dev/null || true

  make defconfig
else
  echo "WARNING: .config not found. Skip scripts/config reinforcement."
fi


# =========================================================
# 6. Final sanity check
# =========================================================

echo "===> 6. Final NSS patch sanity check..."

echo "Current NSS-related patches in $PATCH_DIR:"
find "$PATCH_DIR" -maxdepth 1 -type f -name "*.patch" | sort | grep -Ei 'nss|ecm|shortcut|sfe|pppoe|edma|ppe|ipq807' || true

echo "Checking forbidden patches..."
if find "$PATCH_DIR" -maxdepth 1 -type f -name "*.patch" | grep -Eiq 'ipq9574|ipq5018|ipq5424|ipq5332|cmn|pll'; then
  echo "ERROR: Forbidden non-IPQ807x / CMN PLL patch still exists:"
  find "$PATCH_DIR" -maxdepth 1 -type f -name "*.patch" | grep -Ei 'ipq9574|ipq5018|ipq5424|ipq5332|cmn|pll' || true
  exit 1
fi

echo "Checking FG2000 DTS..."
if [ ! -f "$DTS_DIR/ipq8072-fg2000.dts" ]; then
  echo "ERROR: FG2000 DTS missing: $DTS_DIR/ipq8072-fg2000.dts"
  exit 1
fi

echo "Checking FG2000 device registration..."
if ! grep -q "Device/inseego_fg2000" "$IMAGE_MK"; then
  echo "ERROR: FG2000 device registration missing in $IMAGE_MK"
  exit 1
fi

rm -rf temp_laipeng

echo "========================================================="
echo " Jacob FG2000 customization finished successfully"
echo "========================================================="
