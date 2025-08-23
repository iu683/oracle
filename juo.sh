#!/bin/bash
# ==========================================
# 一键开放 VPS 所有端口
# ⚠️ 警告：非常不安全，仅用于测试环境
# ==========================================

# 颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${YELLOW}检测防火墙类型...${RESET}"

# 检测 ufw 是否存在
if command -v ufw >/dev/null 2>&1; then
    echo -e "${GREEN}检测到 ufw，开始配置...${RESET}"
    ufw --force reset
    ufw default allow incoming
    ufw default allow outgoing
    ufw enable
    echo -e "${GREEN}所有端口已开放（ufw）${RESET}"

# 检测 iptables 是否存在
elif command -v iptables >/dev/null 2>&1; then
    echo -e "${GREEN}检测到 iptables，开始配置...${RESET}"
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    echo -e "${GREEN}所有端口已开放（iptables）${RESET}"

# 检测 nftables 是否存在
elif command -v nft >/dev/null 2>&1; then
    echo -e "${GREEN}检测到 nftables，开始配置...${RESET}"
    # 清空现有规则
    nft flush ruleset
    # 建立新规则集，全部放行
    nft add table inet filter
    nft add chain inet filter input { type filter hook input priority 0 \; policy accept \; }
    nft add chain inet filter forward { type filter hook forward priority 0 \; policy accept \; }
    nft add chain inet filter output { type filter hook output priority 0 \; policy accept \; }
    echo -e "${GREEN}所有端口已开放（nftables）${RESET}"

else
    echo -e "${RED}❌ 未检测到 ufw / iptables / nftables，请先安装防火墙工具${RESET}"
    exit 1
fi

echo -e "${YELLOW}⚠️ 请注意：VPS 所有端口已开放，存在安全风险${RESET}"
