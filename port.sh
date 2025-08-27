#!/bin/bash
# ==========================================
# 🟢 VPS 安全开放所有端口（兼容多系统 & 保留 Docker 规则）
# ⚠️ 提示：仅放开 VPS 系统防火墙端口，不影响 Docker 容器端口映射
# ==========================================

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

# 检查 root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}请使用 root 用户运行脚本${RESET}"
    exit 1
fi

echo -e "${YELLOW}检测 Docker 是否安装并运行...${RESET}"
if ! command -v docker &>/dev/null; then
    echo -e "${RED}Docker 未安装或不可用，请先安装 Docker${RESET}"
    exit 1
fi

if ! docker info &>/dev/null; then
    echo -e "${RED}Docker 未运行，请先启动 Docker${RESET}"
    exit 1
fi
echo -e "${GREEN}Docker 运行中 ✔${RESET}"

# 自动安装函数
install_package() {
    local pkg="$1"
    if [[ -f /etc/alpine-release ]]; then
        apk update && apk add "$pkg"
    elif [[ -f /etc/debian_version ]]; then
        apt-get update && apt-get install -y "$pkg"
    elif [[ -f /etc/redhat-release ]]; then
        yum install -y "$pkg"
    else
        echo -e "${RED}未知系统，请手动安装 $pkg${RESET}"
        exit 1
    fi
}

# 检测防火墙
FW_TYPE=""
if command -v ufw >/dev/null 2>&1; then
    FW_TYPE="ufw"
elif command -v iptables >/dev/null 2>&1; then
    FW_TYPE="iptables"
elif command -v nft >/dev/null 2>&1; then
    FW_TYPE="nftables"
else
    # 尝试安装
    if [[ -f /etc/alpine-release ]]; then
        install_package nftables
        FW_TYPE="nftables"
        rc-update add nftables
        service nftables start
    elif [[ -f /etc/debian_version ]]; then
        install_package ufw
        FW_TYPE="ufw"
    elif [[ -f /etc/redhat-release ]]; then
        install_package iptables
        FW_TYPE="iptables"
    else
        echo -e "${RED}未知系统，无法安装防火墙${RESET}"
        exit 1
    fi
fi

echo -e "${GREEN}检测到防火墙: $FW_TYPE${RESET}"

# 放开所有系统端口（保留 Docker 规则）
if [[ "$FW_TYPE" == "ufw" ]]; then
    echo -e "${YELLOW}配置 ufw 放行所有端口...${RESET}"
    ufw --force reset
    ufw default allow incoming
    ufw default allow outgoing
    ufw enable
    echo -e "${GREEN}所有端口已开放（ufw）${RESET}"

elif [[ "$FW_TYPE" == "iptables" ]]; then
    echo -e "${YELLOW}配置 iptables 放行所有端口（保留 DOCKER 链）...${RESET}"
    # 仅清空 INPUT/OUTPUT/FORWARD 自身规则，不删除 DOCKER 链
    iptables -F INPUT
    iptables -F OUTPUT
    iptables -F FORWARD
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    echo -e "${GREEN}所有端口已开放（iptables）${RESET}"

elif [[ "$FW_TYPE" == "nftables" ]]; then
    echo -e "${YELLOW}配置 nftables 放行所有端口...${RESET}"
    nft flush chain inet filter input || true
    nft flush chain inet filter output || true
    nft flush chain inet filter forward || true
    nft add chain inet filter input { type filter hook input priority 0 \; policy accept \; } 2>/dev/null || true
    nft add chain inet filter output { type filter hook output priority 0 \; policy accept \; } 2>/dev/null || true
    nft add chain inet filter forward { type filter hook forward priority 0 \; policy accept \; } 2>/dev/null || true
    echo -e "${GREEN}所有端口已开放（nftables）${RESET}"
fi

echo -e "${YELLOW}⚠️ VPS 系统端口已放行${RESET}"
