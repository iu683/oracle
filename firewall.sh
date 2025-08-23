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

get_ssh_port() {
    PORT=$(grep -E '^ *Port ' /etc/ssh/sshd_config | awk '{print $2}' | head -n 1)
    [[ -z "$PORT" || ! "$PORT" =~ ^[0-9]+$ ]] && PORT=22
    echo "$PORT"
}

save_rules() {
    netfilter-persistent save 2>/dev/null || true
}

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

check_installed() {
    dpkg -l | grep -q iptables-persistent
}

install_firewall() {
    echo -e "${YELLOW}正在安装防火墙，请稍候...${RESET}"
    apt update -y
    apt remove -y ufw iptables-persistent || true
    apt install -y iptables-persistent xtables-addons-common libtext-csv-xs-perl curl bzip2 unzip || true
    init_rules
    echo -e "${GREEN}✅ 防火墙安装完成，默认放行 SSH/80/443${RESET}"
    read -p "按回车继续..."
}

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

restore_default_rules() {
    echo -e "${YELLOW}正在恢复默认防火墙规则 (仅放行 SSH/80/443)...${RESET}"
    SSH_PORT=$(get_ssh_port)
    echo -e "${GREEN}检测到 SSH 端口: $SSH_PORT${RESET}"
    init_rules
    echo -e "${GREEN}✅ 默认规则已恢复${RESET}"
    read -p "按回车继续..."
}

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

# -----------------------------
# 国内镜像下载 GeoIP
# -----------------------------
install_geoip() {
    mkdir -p /usr/share/xt_geoip
    cd /usr/share/xt_geoip || return
    echo -e "${YELLOW}GeoIP 功能可用，但不进行自动更新${RESET}"
}

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
        echo -e "${GREEN}17. 显示防火墙状态及已放行端口${RESET}"
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
                echo "iptables IPv4:"
                iptables -L -n --line-numbers
                echo "iptables IPv6:"
                ip6tables -L -n --line-numbers
                read -p "按回车继续..."
                ;;
            9) clear_firewall ;;
            10) restore_default_rules ;;
            11)
                ping_action allow
                save_rules
                echo -e "${GREEN}✅ 已允许 PING（ICMP）${RESET}"
                read -p "按回车继续..."
                ;;
            12)
                ping_action deny
                save_rules
                echo -e "${GREEN}✅ 已禁用 PING（ICMP）${RESET}"
                read -p "按回车继续..."
                ;;
            13)
                read -e -p "请输入阻止的国家代码（如 CN, US, JP）: " CC
                manage_country_rules block "$CC"
                save_rules
                echo -e "${GREEN}✅ 已阻止国家 $CC 的 IP${RESET}"
                read -p "按回车继续..."
                ;;
            14)
                read -e -p "请输入允许的国家代码（如 CN, US, JP）: " CC
                manage_country_rules allow "$CC"
                save_rules
                echo -e "${GREEN}✅ 已允许国家 $CC 的 IP${RESET}"
                read -p "按回车继续..."
                ;;
            15)
                read -e -p "请输入清除的国家代码（如 CN, US, JP）: " CC
                manage_country_rules unblock "$CC"
                save_rules
                echo -e "${GREEN}✅ 已清除国家 $CC 的 IP 规则${RESET}"
                read -p "按回车继续..."
                ;;
            16) open_web_ports ;;
            17)
                echo -e "${YELLOW}当前防火墙状态:${RESET}"
                echo "iptables IPv4:"
                iptables -L -n -v --line-numbers
                echo "iptables IPv6:"
                ip6tables -L -n -v --line-numbers
                echo -e "${YELLOW}已放行端口列表:${RESET}"
                echo "TCP:"
                iptables -L INPUT -n | grep ACCEPT | grep tcp || echo "无"
                echo "UDP:"
                iptables -L INPUT -n | grep ACCEPT | grep udp || echo "无"
                echo -e "${GREEN}✅ 状态显示完成${RESET}"
                # 使用更稳妥的 read
                read -r -p "按回车返回菜单..." || true
                ;;

            0) break ;;
            *) echo -e "${RED}无效选择${RESET}"; read -p "按回车继续..." ;;
        esac
    done
}

# ===============================
# 脚本入口
# ===============================
if ! check_installed; then
    install_firewall
    install_geoip
fi

menu
