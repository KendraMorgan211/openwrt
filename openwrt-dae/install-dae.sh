#!/bin/sh
# ============================================================
# OpenWrt 25.12 x86_64 安装 dae/daed（eBPF 透明代理）
# 前提：新固件已刷入（内核含 BTF、eBPF kmod 已内置）
# 用法：scp 到路由器后 sh install-dae.sh，或直接粘贴执行
# ============================================================
set -e

echo "==== 0. 前置硬检查：内核 BTF ===="
if [ ! -f /sys/kernel/btf/vmlinux ]; then
    echo "!! 内核没有 BTF（/sys/kernel/btf/vmlinux 不存在）"
    echo "!! dae 的 eBPF CO-RE 无法运行，请确认刷的是带 BTF 的新固件"
    exit 1
fi
echo "BTF OK"

echo "==== 1. 安装 eBPF 内核模块（新固件已内置，此处兜底） ===="
apk update
apk add kmod-sched-core kmod-sched-bpf kmod-veth kmod-nft-tproxy 2>/dev/null || true

echo "==== 2. 安装 dae / daed / luci-app-daede（kenzok8 feed 一键脚本） ===="
# 该脚本自动完成：检测 SDK 版本 -> 加第三方源 -> apk add dae daed luci-app-daede
wget -O - https://raw.githubusercontent.com/WoHal/openwrt-daede/refs/heads/main/scripts/install.sh | ash

echo "==== 3. 验证安装 ===="
dae --version 2>/dev/null || echo "(dae 版本命令退出码非 0，继续)"
ls -la /usr/bin/dae /usr/bin/daed 2>/dev/null || true

echo "==== 4. eBPF 可用性验证（dae 启动的前提） ===="
bpftool feature 2>/dev/null | head -5 || echo "(bpftool 未安装或无输出，跳过)"
echo ""
echo "==== 安装完成 ===="
echo "下一步："
echo "  1. LuCI -> 服务 -> daede 配置后端（dae 轻量 / daed 带 Web 面板）"
echo "  2. 按 openwrt-dae/README.md 的共存规则配置，避免与雷神冲突"
echo "  3. /etc/init.d/daed enable && /etc/init.d/daed start"
