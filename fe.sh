#!/bin/bash
# =========================================================
# 防火墙一键管理脚本（国家封锁版，全绿菜单）
# =========================================================

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | sed -E 's/.*:([0-9]+)/\1/' | sort -u | head -n1)
[ -z "$SSH_PORT" ] && SSH_PORT=22

PROTOCOLS=("iptables" "ip6tables")

save_rules() {
    netfilter-persistent save 2>/dev/null || true
    echo -e "${GREEN}规则已保存${RESET}"
}

clear_firewall() {
    for proto in "${PROTOCOLS[@]}"; do
        $proto -F
        $proto -X
        $proto -P INPUT ACCEPT
        $proto -P FORWARD ACCEPT
        $proto -P OUTPUT ACCEPT
    done
    save_rules
    echo -e "${YELLOW}已清空所有防火墙规则，全放行${RESET}"
}

allow_basic_ports() {
    clear_firewall
    for proto in "${PROTOCOLS[@]}"; do
        $proto -P INPUT DROP
        $proto -P FORWARD DROP
        $proto -P OUTPUT ACCEPT
        $proto -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        $proto -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
        $proto -A INPUT -p tcp --dport 80 -j ACCEPT
        $proto -A INPUT -p tcp --dport 443 -j ACCEPT
        $proto -A INPUT -i lo -j ACCEPT
    done
    save_rules
    echo -e "${GREEN}已配置：只允许 SSH($SSH_PORT)/80/443${RESET}"
}

open_port() {
    read -p "请输入要开放的端口: " port
    for proto in "${PROTOCOLS[@]}"; do
        $proto -A INPUT -p tcp --dport $port -j ACCEPT
        $proto -A INPUT -p udp --dport $port -j ACCEPT
    done
    save_rules
    echo -e "${GREEN}端口 $port 已开放${RESET}"
}

close_port() {
    read -p "请输入要关闭的端口: " port
    for proto in "${PROTOCOLS[@]}"; do
        $proto -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        $proto -D INPUT -p udp --dport $port -j ACCEPT 2>/dev/null
    done
    save_rules
    echo -e "${RED}端口 $port 已关闭${RESET}"
}

whitelist_ip() {
    read -p "请输入要加入白名单的IP: " ip
    for proto in "${PROTOCOLS[@]}"; do
        $proto -I INPUT -s $ip -j ACCEPT
    done
    save_rules
    echo -e "${GREEN}IP $ip 已加入白名单${RESET}"
}

blacklist_ip() {
    read -p "请输入要加入黑名单的IP: " ip
    for proto in "${PROTOCOLS[@]}"; do
        $proto -A INPUT -s $ip -j DROP
    done
    save_rules
    echo -e "${RED}IP $ip 已加入黑名单${RESET}"
}

allow_ping() {
    for proto in "${PROTOCOLS[@]}"; do
        $proto -A INPUT -p icmp --icmp-type echo-request -j ACCEPT 2>/dev/null
        $proto -A INPUT -p icmpv6 --icmpv6-type echo-request -j ACCEPT 2>/dev/null
    done
    save_rules
    echo -e "${GREEN}已允许 ping${RESET}"
}

block_ping() {
    for proto in "${PROTOCOLS[@]}"; do
        $proto -A INPUT -p icmp --icmp-type echo-request -j DROP 2>/dev/null
        $proto -A INPUT -p icmpv6 --icmpv6-type echo-request -j DROP 2>/dev/null
    done
    save_rules
    echo -e "${RED}已禁止 ping${RESET}"
}

# 安装 xtables-addons + GeoIP 数据库
install_geoip() {
    if ! lsmod | grep -q xt_geoip; then
        echo -e "${YELLOW}正在安装 xtables-addons（geoip 模块）...${RESET}"
        apt-get update -y
        apt-get install -y xtables-addons-common xtables-addons-source geoip-database libtext-csv-xs-perl
        mkdir -p /usr/share/xt_geoip
        /usr/lib/xtables-addons/xt_geoip_dl
        /usr/lib/xtables-addons/xt_geoip_build -D /usr/share/xt_geoip /usr/share/xt_geoip/*.csv
        modprobe xt_geoip
    fi
}

block_country() {
    install_geoip
    read -p "请输入要禁止的国家代码 (如 CN RU IN): " country
    for proto in "${PROTOCOLS[@]}"; do
        $proto -A INPUT -m geoip --src-cc $country -j DROP
    done
    save_rules
    echo -e "${RED}已封锁国家: $country${RESET}"
}

unblock_country() {
    read -p "请输入要解除封锁的国家代码 (如 CN RU IN): " country
    for proto in "${PROTOCOLS[@]}"; do
        while $proto -C INPUT -m geoip --src-cc $country -j DROP 2>/dev/null; do
            $proto -D INPUT -m geoip --src-cc $country -j DROP
        done
    done
    save_rules
    echo -e "${GREEN}已解除封锁国家: $country${RESET}"
}

status_firewall() {
    for proto in "${PROTOCOLS[@]}"; do
        echo -e "${GREEN}===== $proto 规则 =====${RESET}"
        $proto -L -n -v --line-numbers | grep -E "dpt:|Chain|policy|geoip"
    done
}

menu() {
    clear
    echo -e "${GREEN}▶ 防火墙管理脚本（国家封锁版）${RESET}"
    echo -e "${GREEN}--------------------------------${RESET}"
    echo -e "${GREEN}1) 初始化防火墙 (只允许 SSH/80/443)${RESET}"
    echo -e "${GREEN}2) 清空所有规则 (全放行)${RESET}"
    echo -e "${GREEN}3) 开放指定端口${RESET}"
    echo -e "${GREEN}4) 关闭指定端口${RESET}"
    echo -e "${GREEN}5) 加入白名单 IP${RESET}"
    echo -e "${GREEN}6) 加入黑名单 IP${RESET}"
    echo -e "${GREEN}7) 允许 ping${RESET}"
    echo -e "${GREEN}8) 禁止 ping${RESET}"
    echo -e "${GREEN}9) 封锁指定国家${RESET}"
    echo -e "${GREEN}10) 解除封锁国家${RESET}"
    echo -e "${GREEN}11) 查看防火墙状态${RESET}"
    echo -e "${GREEN}0) 退出${RESET}"
    echo -e "${GREEN}--------------------------------${RESET}"
    read -p "请选择操作: " choice

    case $choice in
        1) allow_basic_ports ;;
        2) clear_firewall ;;
        3) open_port ;;
        4) close_port ;;
        5) whitelist_ip ;;
        6) blacklist_ip ;;
        7) allow_ping ;;
        8) block_ping ;;
        9) block_country ;;
        10) unblock_country ;;
        11) status_firewall ;;
        0) exit ;;
        *) echo -e "${RED}无效选择${RESET}";;
    esac
}

while true; do
    menu
    read -p "按回车键继续..." enter
done
