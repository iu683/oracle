#!/bin/bash
set -e

# ===============================
# 防火墙管理脚本（Debian/Ubuntu 双栈 IPv4/IPv6）
# ===============================

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# ===============================
# 工具函数
# ===============================

# 获取 SSH 端口
get_ssh_port() {
    PORT=$(grep -E '^ *Port ' /etc/ssh/sshd_config | awk '{print $2}' | head -n 1)
    [[ -z "$PORT" || ! "$PORT" =~ ^[0-9]+$ ]] && PORT=22
    echo "$PORT"
}

# 保存规则
save_rules() {
    netfilter-persistent save 2>/dev/null || true
}

# 初始化默认规则
init_rules() {
    SSH_PORT=$(get_ssh_port)
    for proto in iptables ip6tables; do
        $proto -F
        $proto -X
        $proto -t nat -F 2>/dev/null || true
        $proto -t nat -X 2>/dev/null || true
        $proto -t mangle -F 2>/dev/null || true
        $proto -t mangle -X 2>/dev/null || true
        $proto -P INPUT DROP
        $proto -P FORWARD DROP
        $proto -P OUTPUT ACCEPT
        $proto -A INPUT -i lo -j ACCEPT
        $proto -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        $proto -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
        $proto -A INPUT -p tcp --dport 80 -j ACCEPT
        $proto -A INPUT -p tcp --dport 443 -j ACCEPT
    done
    save_rules
    systemctl enable netfilter-persistent 2>/dev/null || true
}

# 检查防火墙安装
check_installed() {
    dpkg -l | grep -q iptables-persistent
}

# 安装防火墙
install_firewall() {
    echo -e "${YELLOW}正在安装防火墙，请稍候...${RESET}"
    apt update -y
    apt remove -y ufw iptables-persistent || true
    apt install -y iptables-persistent xtables-addons-common libtext-csv-xs-perl curl bzip2 unzip || true
    init_rules
    echo -e "${GREEN}✅ 防火墙安装完成，默认放行 SSH/80/443${RESET}"
    read -p "按回车继续..."
}

# 清空防火墙规则
clear_firewall() {
    echo -e "${YELLOW}正在清空防火墙规则并放行所有流量...${RESET}"
    for proto in iptables ip6tables; do
        $proto -F
        $proto -X
        $proto -P INPUT ACCEPT
        $proto -P FORWARD ACCEPT
        $proto -P OUTPUT ACCEPT
    done
    save_rules
    systemctl disable netfilter-persistent 2>/dev/null || true
    echo -e "${GREEN}✅ 防火墙规则已清空，所有流量已放行${RESET}"
    read -p "按回车继续..."
}

# 恢复默认规则
restore_default_rules() {
    echo -e "${YELLOW}正在恢复默认防火墙规则 (仅放行 SSH/80/443)...${RESET}"
    SSH_PORT=$(get_ssh_port)
    echo -e "${GREEN}检测到 SSH 端口: $SSH_PORT${RESET}"
    init_rules
    echo -e "${GREEN}✅ 默认规则已恢复: 仅允许 SSH/80/443，其余拒绝${RESET}"
    read -p "按回车继续..."
}

# 一键放行 Web 端口
open_web_ports() {
    SSH_PORT=$(get_ssh_port)
    echo -e "${YELLOW}正在一键放行 SSH/80/443...${RESET}"
    for proto in iptables ip6tables; do
        $proto -I INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
        $proto -I INPUT -p tcp --dport 80 -j ACCEPT
        $proto -I INPUT -p tcp --dport 443 -j ACCEPT
    done
    save_rules
    echo -e "${GREEN}✅ 已放行 SSH/80/443${RESET}"
    read -p "按回车继续..."
}

# IP 操作
ip_action() {
    local action=$1 ip=$2
    for proto in iptables ip6tables; do
        case $action in
            accept)
                $proto -I INPUT -s "$ip" -j ACCEPT
                ;;
            drop)
                $proto -I INPUT -s "$ip" -j DROP
                ;;
            delete)
                while $proto -C INPUT -s "$ip" -j ACCEPT 2>/dev/null; do
                    $proto -D INPUT -s "$ip" -j ACCEPT
                done
                while $proto -C INPUT -s "$ip" -j DROP 2>/dev/null; do
                    $proto -D INPUT -s "$ip" -j DROP
                done
                ;;
        esac
    done
}

# PING 操作
ping_action() {
    local action=$1
    for proto in iptables ip6tables; do
        case $action in
            allow)
                $proto -I INPUT -p icmp --icmp-type echo-request -j ACCEPT 2>/dev/null || true
                $proto -I OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT 2>/dev/null || true
                ;;
            deny)
                while $proto -C INPUT -p icmp --icmp-type echo-request -j ACCEPT 2>/dev/null; do
                    $proto -D INPUT -p icmp --icmp-type echo-request -j ACCEPT
                done
                while $proto -C OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT 2>/dev/null; do
                    $proto -D OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT
                done
                ;;
        esac
    done
}

# 安装并生成 GeoIP 数据
install_geoip() {
    mkdir -p /usr/share/xt_geoip
    cd /usr/share/xt_geoip || return
    echo -e "${YELLOW}正在下载 GeoIP 数据，请稍候...${RESET}"
    curl -O https://geolite.maxmind.com/download/geoip/database/GeoLite2-Country-CSV.zip
    unzip -o GeoLite2-Country-CSV.zip
    mkdir -p /usr/share/xt_geoip/build
    for csv in $(find . -name "*-Blocks-IPv4.csv" -o -name "*-Blocks-IPv6.csv"); do
        csv2bin "$csv" /usr/share/xt_geoip/build
    done
    echo -e "${GREEN}✅ GeoIP 数据下载并生成完成${RESET}"
}

# 国家规则
manage_country_rules() {
    local action=$1
    local country=$2
    for proto in iptables ip6tables; do
        case $action in
            block)
                $proto -I INPUT -m geoip --src-cc "$country" -j DROP 2>/dev/null || true
                ;;
            allow)
                $proto -I INPUT -m geoip --src-cc "$country" -j ACCEPT 2>/dev/null || true
                ;;
            unblock)
                while $proto -C INPUT -m geoip --src-cc "$country" -j DROP 2>/dev/null; do
                    $proto -D INPUT -m geoip --src-cc "$country" -j DROP
                done
                while $proto -C INPUT -m geoip --src-cc "$country" -j ACCEPT 2>/dev/null; do
                    $proto -D INPUT -m geoip --src-cc "$country" -j ACCEPT
                done
                ;;
        esac
    done
}

# ===============================
# 菜单
# ===============================
menu() {
    while true; do
        clear
        echo -e "${GREEN}============================${RESET}"
        echo -e "${GREEN} 🔥 防火墙管理脚本 (IPv4/IPv6)${RESET}"
        echo -e "${GREEN}============================${RESET}"
        echo -e "${GREEN}1. 开放指定端口${RESET}"
        echo -e "${GREEN}2. 关闭指定端口${RESET}"
        echo -e "${GREEN}3. 开放所有端口${RESET}"
        echo -e "${GREEN}4. 关闭所有端口（默认安全）${RESET}"
        echo -e "${GREEN}5. 添加 IP 白名单（放行）${RESET}"
        echo -e "${GREEN}6. 添加 IP 黑名单（封禁）${RESET}"
        echo -e "${GREEN}7. 删除 IP 规则${RESET}"
        echo -e "${GREEN}8. 显示当前防火墙规则${RESET}"
        echo -e "${GREEN}9. 清空所有规则（全放行）${RESET}"
        echo -e "${GREEN}10. 恢复默认安全规则（仅放行 SSH/80/443）${RESET}"
        echo -e "${GREEN}11. 允许 PING（ICMP）${RESET}"
        echo -e "${GREEN}12. 禁用 PING（ICMP）${RESET}"
        echo -e "${GREEN}13. 阻止国家 IP${RESET}"
        echo -e "${GREEN}14. 允许国家 IP${RESET}"
        echo -e "${GREEN}15. 清除国家 IP${RESET}"
        echo -e "${GREEN}16. 一键放行常用 Web 端口 (SSH/80/443)${RESET}"
        echo -e "${GREEN}0. 退出${RESET}"
        echo -e "${GREEN}============================${RESET}"
        read -p "请输入选择: " choice

        case $choice in
            1)
                read -p "请输入要开放的端口号: " PORT
                for proto in iptables ip6tables; do
                    $proto -I INPUT -p tcp --dport "$PORT" -j ACCEPT
                    $proto -I INPUT -p udp --dport "$PORT" -j ACCEPT
                done
                save_rules
                echo -e "${GREEN}✅ 已开放端口 $PORT${RESET}"
                read -p "按回车继续..."
                ;;
            2)
                read -p "请输入要关闭的端口号: " PORT
                for proto in iptables ip6tables; do
                    while $proto -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; do
                        $proto -D INPUT -p tcp --dport "$PORT" -j ACCEPT
                    done
                    while $proto -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null; do
                        $proto -D INPUT -p udp --dport "$PORT" -j ACCEPT
                    done
                done
                save_rules
                echo -e "${GREEN}✅ 已关闭端口 $PORT${RESET}"
                read -p "按回车继续..."
                ;;
            3) open_web_ports ;;
            4) restore_default_rules ;;
            5)
                read -p "请输入要放行的IP: " IP
                ip_action accept "$IP"
                save_rules
                echo -e "${GREEN}✅ IP $IP 已放行${RESET}"
                read -p "按回车继续..."
                ;;
            6)
                read -p "请输入要封禁的IP: " IP
                ip_action drop "$IP"
                save_rules
                echo -e "${GREEN}✅ IP $IP 已封禁${RESET}"
                read -p "按回车继续..."
                ;;
            7)
                read -p "请输入要删除的IP: " IP
                ip_action delete "$IP"
                save_rules
                echo -e "${GREEN}✅ IP $IP 已删除${RESET}"
                read -p "按回车继续..."
                ;;
            8)
                echo -e "${YELLOW}IPv4规则:${RESET}"; iptables -L -n --line-numbers
                echo -e "${YELLOW}IPv6规则:${RESET}"; ip6tables -L -n --line-numbers
                read -p "按回车继续..."
                ;;
            9) clear_firewall ;;
            10) restore_default_rules ;;
            11) ping_action allow; save_rules; echo -e "${GREEN}✅ 已允许 PING${RESET}"; read -p "按回车继续..." ;;
            12) ping_action deny; save_rules; echo -e "${GREEN}✅ 已禁用 PING${RESET}"; read -p "按回车继续..." ;;
            13)
                read -e -p "请输入阻止的国家代码: " country_code
                manage_country_rules block "$country_code"; save_rules
                echo -e "${GREEN}✅ 已阻止国家 $country_code 的 IP${RESET}"
                read -p "按回车继续..."
                ;;
            14)
                read -e -p "请输入允许的国家代码: " country_code
                manage_country_rules allow "$country_code"; save_rules
                echo -e "${GREEN}✅ 已允许国家 $country_code 的 IP${RESET}"
                read -p "按回车继续..."
                ;;
            15)
                read -e -p "请输入清除的国家代码: " country_code
                manage_country_rules unblock "$country_code"; save_rules
                echo -e "${GREEN}✅ 已清除国家 $country_code 的 IP${RESET}"
                read -p "按回车继续..."
                ;;
            16) open_web_ports ;;
            0) exit 0 ;;
            *) echo -e "${RED}❌ 无效输入，请重新选择${RESET}"; read -p "按回车继续..." ;;
        esac
    done
}

# ===============================
# 主逻辑
# ===============================
if ! check_installed; then
    echo -e "${YELLOW}⚠️ 防火墙未安装，是否现在安装？(Y/N)${RESET}"
    read -p "选择: " choice
    case "$choice" in
        [Yy]) install_firewall; install_geoip; menu ;;
        [Nn]) echo "已取消"; exit 0 ;;
        *) echo -e "${RED}❌ 无效选择${RESET}"; exit 1 ;;
    esac
else
    menu
fi
