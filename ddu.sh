#!/bin/bash
# ==========================================
# 一键开放 VPS 所有端口（保留 SSH）
# ⚠️ 警告：仍有安全风险，仅用于测试环境
# ==========================================

# 颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

SSH_PORT=22

echo -e "${YELLOW}检测系统类型...${RESET}"

# --------------------------
# 自动安装函数
# --------------------------
install_package() {
    local pkg="$1"
    if [[ -f /etc/alpine-release ]]; then
        echo -e "${YELLOW}检测到 Alpine，尝试安装 $pkg ...${RESET}"
        apk update
        apk add --no-cache "$pkg"
    elif [[ -f /etc/debian_version ]]; then
        echo -e "${YELLOW}检测到 Debian/Ubuntu，尝试安装 $pkg ...${RESET}"
        apt-get update
        apt-get install -y "$pkg"
    elif [[ -f /etc/redhat-release ]]; then
        echo -e "${YELLOW}检测到 CentOS/RHEL，尝试安装 $pkg ...${RESET}"
        yum install -y "$pkg"
    else
        echo -e "${RED}❌ 未知系统，请手动安装 $pkg${RESET}"
        exit 1
    fi
}

# --------------------------
# Debian/Ubuntu 自动切换 iptables-legacy
# --------------------------
setup_iptables_legacy() {
    # 安装 legacy 包
    apt-get install -y iptables-legacy
    # 检查 iptables-legacy 是否存在
    if command -v iptables-legacy >/dev/null 2>&1; then
        update-alternatives --set iptables /usr/sbin/iptables-legacy
        update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
        update-alternatives --set arptables /usr/sbin/arptables-legacy
        update-alternatives --set ebtables /usr/sbin/ebtables-legacy
        IPT_CMD="iptables-legacy"
        echo -e "${GREEN}已切换到 iptables-legacy${RESET}"
    else
        echo -e "${RED}❌ iptables-legacy 不存在，使用默认 iptables${RESET}"
        IPT_CMD="iptables"
    fi
}

# --------------------------
# 检测防火墙
# --------------------------
if command -v ufw >/dev/null 2>&1; then
    FW_TYPE="ufw"
elif command -v iptables >/dev/null 2>&1; then
    FW_TYPE="iptables"
    if [[ -f /etc/debian_version ]]; then
        setup_iptables_legacy
    else
        IPT_CMD="iptables"
    fi
elif command -v nft >/dev/null 2>&1; then
    FW_TYPE="nftables"
else
    # 自动安装防火墙
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
        IPT_CMD="iptables"
    else
        echo -e "${RED}❌ 未知系统，无法安装防火墙${RESET}"
        exit 1
    fi
fi

# --------------------------
# 开放所有端口（保留 SSH）
# --------------------------
echo -e "${GREEN}检测到防火墙: $FW_TYPE，开始配置...${RESET}"

if [[ "$FW_TYPE" == "ufw" ]]; then
    ufw --force reset
    ufw allow "$SSH_PORT"
    ufw default allow incoming
    ufw default allow outgoing
    ufw --force enable
    echo -e "${GREEN}所有端口已开放（ufw），SSH 保留在端口 $SSH_PORT${RESET}"

elif [[ "$FW_TYPE" == "iptables" ]]; then
    $IPT_CMD -F
    $IPT_CMD -X
    $IPT_CMD -t nat -F
    $IPT_CMD -t nat -X
    $IPT_CMD -t mangle -F
    $IPT_CMD -t mangle -X
    $IPT_CMD -P INPUT ACCEPT
    $IPT_CMD -P OUTPUT ACCEPT
    $IPT_CMD -P FORWARD ACCEPT
    # 保留 SSH
    $IPT_CMD -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
    echo -e "${GREEN}所有端口已开放（$IPT_CMD），SSH 保留在端口 $SSH_PORT${RESET}"

elif [[ "$FW_TYPE" == "nftables" ]]; then
    nft flush ruleset
    # 添加表和链（存在则跳过）
    nft list table inet filter >/dev/null 2>&1 || nft add table inet filter
    nft list chain inet filter input >/dev/null 2>&1 || nft add chain inet filter input { type filter hook input priority 0 \; policy accept \; }
    nft list chain inet filter forward >/dev/null 2>&1 || nft add chain inet filter forward { type filter hook forward priority 0 \; policy accept \; }
    nft list chain inet filter output >/dev/null 2>&1 || nft add chain inet filter output { type filter hook output priority 0 \; policy accept \; }
    # 保留 SSH
    nft add rule inet filter input tcp dport "$SSH_PORT" accept
    echo -e "${GREEN}所有端口已开放（nftables），SSH 保留在端口 $SSH_PORT${RESET}"
fi

echo -e "${YELLOW}⚠️ 请注意：VPS 所有端口已开放，仍存在安全风险${RESET}"
