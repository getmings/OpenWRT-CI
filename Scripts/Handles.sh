#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

FEEDS_PATH="./feeds"
PACKAGE_PATH="./package"

#修补命令统一入口：FIX <名称> <守卫目录> <命令...>
#守卫目录不存在时直接跳过，保证在 bash -e 下不中断
FIX() {
	local NAME=$1
	local GUARD=$2
	shift 2

	[ -d "$GUARD" ] || return 0

	echo " "
	if "$@"; then
		echo "$NAME has been fixed!"
	else
		echo "$NAME fix failed; continuing!"
	fi
}

#修改argon主题字体和颜色
FIX "theme-argon" "$PACKAGE_PATH/luci-theme-argon" sed -i \
	"s/primary '.*'/primary '#31a1a1'/g; s/'0.2'/'0.5'/g; s/'none'/'bing'/g; s/'600'/'normal'/g" \
	"$PACKAGE_PATH/luci-theme-argon/luci-app-argon-config/root/etc/config/argon"

#修改aurora菜单式样
FIX "theme-aurora" "$PACKAGE_PATH/luci-app-aurora-config" find \
	"$PACKAGE_PATH/luci-app-aurora-config/root/usr/share/aurora/" -type f -name '*.template' -exec sed -i \
	"s/nav_type '.*'/nav_type 'dropdown'/g; s/struct_radius_base '.*'/struct_radius_base '0.125rem'/g" {} +

#修改vantage进度条标签字体（anothaDev/luci-theme-vantage#52）
FIX "theme-vantage" "$PACKAGE_PATH/luci-theme-vantage" sed -i \
	-e '/^\/\* progress bars: thin track/,$ { /^\.cbi-progressbar::before {/,/^}/ { s/^[[:space:]]*font: 500 var(--fs-micro)\/1\.2 var(--mono);/\tfont: inherit; line-height: normal;/; } }' \
	"$PACKAGE_PATH/luci-theme-vantage/luci-theme-vantage/htdocs/luci-static/vantage/vantage.css"

#修改mini-diskmanager菜单位置
FIX "mini-diskmanager" "$PACKAGE_PATH/luci-app-mini-diskmanager" sed -i "s/services/system/g" \
	"$PACKAGE_PATH/luci-app-mini-diskmanager/luci-app-mini-diskmanager/root/usr/share/luci/menu.d/luci-app-mini-diskmanager.json"

#修改natmapt菜单位置
FIX "natmapt" "$PACKAGE_PATH/luci-app-natmapt" sed -i "s/network/services/g" \
	"$PACKAGE_PATH/luci-app-natmapt/root/usr/share/luci/menu.d/luci-app-natmap.json"




# 安装 luci-app-honk 完整编译工具链
if [ -d "$PACKAGE_PATH/luci-app-honk/honk" ]; then
	(
		set -e

		HONK_DIR="$PACKAGE_PATH/luci-app-honk/honk"

		export PATH="$HOME/.cargo/bin:/usr/local/bin:$PATH"

		echo "===== Install Honk dependencies ====="

		sudo apt-get update

		sudo apt-get install -y \
			clang llvm libbpf-dev cmake libclang-dev zstd \
			make perl file binutils git curl xz-utils pkg-config ca-certificates

		if [ ! -f "$HOME/.cargo/env" ]; then
			curl --proto '=https' --tlsv1.2 -sSf \
				https://sh.rustup.rs | sh -s -- -y --profile minimal --no-modify-path
		fi

		source "$HOME/.cargo/env"

		eval "$(bash "$HONK_DIR/honk_toolchain.sh" "$HONK_DIR/Makefile")"

		curl -fsSL --retry 3 \
			-o /tmp/bpf-linker.tar.zst \
			"https://github.com/aya-rs/bpf-linker/releases/download/v${BPF_LINKER_VERSION}/bpf-linker-x86_64-unknown-linux-musl.tar.zst"

		echo "${BPF_LINKER_SHA256}  /tmp/bpf-linker.tar.zst" | sha256sum -c -

		sudo tar --zstd -xf /tmp/bpf-linker.tar.zst -C /usr/local/bin

		curl -fsSL --retry 3 \
			-o /tmp/zig.tar.xz \
			"https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz"

		sudo tar -xJf /tmp/zig.tar.xz -C /usr/local

		sudo ln -sf \
			"/usr/local/zig-x86_64-linux-${ZIG_VERSION}/zig" \
			/usr/local/bin/zig

		echo "===== Verify Honk dependencies ====="

		zig version
		bpf-linker --version
		cargo --version

	) || exit 1
fi
