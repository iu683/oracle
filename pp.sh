#!/bin/bash
# ==========================================
# 一键开放 VPS 所有端口 + 自动安装 iptables-legacy
# ⚠️ 警告：仍存在安全风险，仅用于测试环境
# ==========================================

# 颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

# --------------------------
# 检查 root 权限
# --------------------------
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ 请使用 root 权限运行此脚本${RESET}"
    exit 1
fi

echo -e "${YELLOW}检测系统类型...${RESET}"

# --------------------------
# 自动安装函数
# --------------------------
install_package() {
    local pkg="$1"
    if [[ -f /etc/alpine-release ]]; then
        echo -e "${YELLOW}检测到 Alpine，安装 $pkg ...${RESET}"
        apk update && apk add --no-cache "$pkg"
    elif [[ -f /etc/debian_version ]]; then
        echo -e "${YELLOW}检测到 Debian/Ubuntu，安装 $pkg ...${RESET}"
        apt-get update && apt-get install -y "$pkg"
    elif [[ -f /etc/redhat-release ]]; then
        echo -e "${YELLOW}检测到 CentOS/RHEL，安装 $pkg ...${RESET}"
        yum install -y "$pkg"
    else
        echo -e "${RED}❌ 未知系统，请手动安装 $pkg${RESET}"
        exit 1
    fi
}

# --------------------------
# Debian/Ubuntu 安装并切换 iptables-legacy
# --------------------------
if [[ -f /etc/debian_version ]]; then
    if ! command -v iptables >/dev/null 2>&1; then
        echo -e "${YELLOW}未检测到 iptables，自动安装 iptables + iptables-legacy...${RESET}"
        apt-get update && apt-get install -y iptables iptables-legacy
    fi
    echo -e "${YELLOW}切换到 iptables-legacy ...${RESET}"
    update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-legacy 10
    update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-legacy 10
    update-alternatives --set iptables /usr/sbin/iptables-legacy
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
    IPT_CMD="iptables"
    FW_TYPE="iptables"   # 强制 Debian/Ubuntu 使用 iptables-legacy
fi

# --------------------------
# 检测防火墙类型（非 Debian/Ubuntu）
# --------------------------
if [[ -z "$FW_TYPE" ]]; then
    if command -v ufw >/dev/null 2>&1; then
        FW_TYPE="ufw"
    elif command -v iptables >/dev/null 2>&1; then
        FW_TYPE="iptables"
        IPT_CMD="iptables"
    elif command -v nft >/dev/null 2>&1; then
        FW_TYPE="nftables"
    else
        if [[ -f /etc/alpine-release ]]; then
            install_package nftables
            FW_TYPE="nftables"
            rc-update add nftables && service nftables start
        elif [[ -f /etc/redhat-release ]]; then
            install_package iptables
            FW_TYPE="iptables"
            IPT_CMD="iptables"
        else
            echo -e "${RED}❌ 未知系统，无法安装防火墙${RESET}"
            exit 1
        fi
    fi
fi

# --------------------------
# 开放所有端口
# --------------------------
echo -e "${GREEN}检测到防火墙: $FW_TYPE，开始配置...${RESET}"

if [[ "$FW_TYPE" == "iptables" ]]; then
    $IPT_CMD -F
    $IPT_CMD -X
    $IPT_CMD -t nat -F
    $IPT_CMD -t nat -X
    $IPT_CMD -t mangle -F
    $IPT_CMD -t mangle -X
    $IPT_CMD -P INPUT ACCEPT
    $IPT_CMD -P OUTPUT ACCEPT
    $IPT_CMD -P FORWARD ACCEPT
    echo -e "${GREEN}所有端口已开放（iptables-legacy）${RESET}"

elif [[ "$FW_TYPE" == "nftables" ]]; then
    nft flush ruleset
    nft add table inet filter
    nft add chain inet filter input   "{ type filter hook input priority 0 ; policy accept ; }"
    nft add chain inet filter forward "{ type filter hook forward priority 0 ; policy accept ; }"
    nft add chain inet filter output  "{ type filter hook output priority 0 ; policy accept ; }"
    echo -e "${GREEN}所有端口已开放（nftables）${RESET}"

elif [[ "$FW_TYPE" == "ufw" ]]; then
    ufw --force reset
    ufw default allow incoming
    ufw default allow outgoing
    ufw --force enable
    echo -e "${GREEN}所有端口已开放（ufw）${RESET}"
fi

echo -e "${YELLOW}⚠️ VPS 所有端口已开放，仍存在安全风险${RESET}"
