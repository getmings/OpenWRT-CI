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
		set -euo pipefail

		HONK_DIR="$PACKAGE_PATH/luci-app-honk/honk"
		TOOLCHAIN="$HONK_DIR/honk_toolchain.sh"

		export PATH="$HOME/.cargo/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

		echo " "
		echo "===== Install Honk Build Dependencies ====="

		[ -f "$TOOLCHAIN" ] || {
			echo "ERROR: honk_toolchain.sh not found!"
			exit 1
		}

		# 读取 Honk 上游锁定的工具链版本
		eval "$(bash "$TOOLCHAIN")"

		echo "Honk commit: $HONK_SRC_VERSION"
		echo "Zig version: $ZIG_VERSION"
		echo "bpf-linker version: $BPF_LINKER_VERSION"

		# 安装系统编译依赖
		sudo apt-get -o Acquire::Retries=5 update

		sudo apt-get -o Acquire::Retries=5 install -y \
			clang \
			llvm \
			libbpf-dev \
			pkg-config \
			cmake \
			libclang-dev \
			zstd

		# 安装 Rustup
		if ! command -v rustup >/dev/null 2>&1; then
			curl --proto '=https' --tlsv1.2 -sSf \
				https://sh.rustup.rs | sh -s -- -y --profile minimal
		fi

		[ -f "$HOME/.cargo/env" ] || {
			echo "ERROR: Rust environment not found!"
			exit 1
		}

		source "$HOME/.cargo/env"

		export PATH="$HOME/.cargo/bin:/usr/local/bin:$PATH"

		# 从 Honk 精确提交读取 Rust stable / nightly 版本
		HONK_REPO="${HONK_SRC_URL#https://github.com/}"
		HONK_REPO="${HONK_REPO%.git}"
		HONK_RAW="https://raw.githubusercontent.com/${HONK_REPO}/${HONK_SRC_VERSION}"

		RUST_STABLE=$(curl -fsSL --retry 5 \
			"$HONK_RAW/rust-toolchain.toml" |
			sed -n 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' |
			head -n 1)

		RUST_EBPF=$(curl -fsSL --retry 5 \
			"$HONK_RAW/crates/honk-ebpf/rust-toolchain.toml" |
			sed -n 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' |
			head -n 1)

		[ -n "$RUST_STABLE" ] && [ -n "$RUST_EBPF" ] || {
			echo "ERROR: Cannot resolve Honk Rust toolchain!"
			exit 1
		}

		echo "Rust stable: $RUST_STABLE"
		echo "Rust eBPF: $RUST_EBPF"

		# 安装 Rust stable
		rustup toolchain install "$RUST_STABLE" --profile minimal

		# 安装 eBPF nightly
		rustup toolchain install "$RUST_EBPF" \
			--profile minimal \
			--component rust-src \
			--component llvm-tools

		# 安装 Zig
		if [ "$(zig version 2>/dev/null || true)" != "$ZIG_VERSION" ]; then
			echo "Installing Zig $ZIG_VERSION"

			curl -fsSL --retry 5 \
				"https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
				-o /tmp/honk-zig.tar.xz

			ZIG_DIR="/opt/honk-zig-${ZIG_VERSION}"

			sudo rm -rf "$ZIG_DIR"
			sudo mkdir -p "$ZIG_DIR"

			sudo tar -xJf /tmp/honk-zig.tar.xz \
				-C "$ZIG_DIR" --strip-components=1

			sudo ln -sfn "$ZIG_DIR/zig" /usr/local/bin/zig
		fi

		# 安装 bpf-linker
		echo "Installing bpf-linker $BPF_LINKER_VERSION"

		curl -fsSL --retry 5 \
			"https://github.com/aya-rs/bpf-linker/releases/download/v${BPF_LINKER_VERSION}/bpf-linker-x86_64-unknown-linux-musl.tar.zst" \
			-o /tmp/honk-bpf-linker.tar.zst

		echo "${BPF_LINKER_SHA256}  /tmp/honk-bpf-linker.tar.zst" |
			sha256sum -c -

		sudo tar --zstd -xf /tmp/honk-bpf-linker.tar.zst \
			-C /usr/local/bin

		sudo chmod +x /usr/local/bin/bpf-linker

		# 验证工具链
		echo " "
		echo "===== Verify Honk Toolchain ====="

		zig version
		bpf-linker --version
		rustc "+${RUST_STABLE}" --version
		rustc "+${RUST_EBPF}" --version
		cargo --version

		command -v zig
		command -v bpf-linker
		command -v cargo

		echo " "
		echo "Honk build dependencies installed successfully!"

	) || exit 1
else
	echo "Honk package not found, skipping toolchain installation."
fi
