#!/bin/bash
set -e

# 颜色定义
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# 获取当前 SSH 端口
get_ssh_port() {
    SSH_PORT=$(ss -tnlp 2>/dev/null | grep -w sshd | awk -F '[: ]+' '{print $5}' | sort -n | head -n 1)
    echo "${SSH_PORT:-22}"
}

# 初始化默认规则
init_rules() {
    SSH_PORT=$(get_ssh_port)
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    netfilter-persistent save 2>/dev/null || true
    systemctl enable netfilter-persistent 2>/dev/null || true
}

# 检查防火墙是否安装
check_installed() {
    dpkg -l | grep -q iptables-persistent
}

# 安装防火墙
install_firewall() {
    apt update -y
    apt remove -y ufw iptables-persistent || true
    apt install -y iptables-persistent
    init_rules
    echo -e "${GREEN}✅ 防火墙安装完成，默认放行 SSH/80/443${RESET}"
}

# 清空防火墙规则（全放行）
clear_firewall() {
    echo -e "${YELLOW}正在清空防火墙规则并放行所有流量...${RESET}"
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    netfilter-persistent save 2>/dev/null || true
    systemctl disable netfilter-persistent 2>/dev/null || true
    echo -e "${GREEN}✅ 防火墙规则已清空，所有流量已放行 (SSH 不会断开)${RESET}"
}

# 恢复默认安全规则（仅放行 SSH）
restore_default_rules() {
    echo -e "${YELLOW}正在恢复默认防火墙规则 (仅放行 SSH)...${RESET}"
    SSH_PORT=$(get_ssh_port)
    echo -e "${GREEN}检测到 SSH 端口: $SSH_PORT${RESET}"
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
    netfilter-persistent save 2>/dev/null || true
    systemctl enable netfilter-persistent 2>/dev/null || true
    echo -e "${GREEN}✅ 默认规则已恢复: 仅允许 SSH($SSH_PORT)，其余全部拒绝${RESET}"
}

# 显示菜单
menu() {
    while true; do
        clear
        echo -e "${GREEN}============================${RESET}"
        echo -e "${GREEN} 🔥 防火墙管理脚本${RESET}"
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
        echo -e "${GREEN}10. 恢复默认安全规则（仅放行 SSH）${RESET}"
        echo -e "${GREEN}0. 退出${RESET}"
        echo -e "${GREEN}============================${RESET}"
        read -p "请输入选择: " choice

        case $choice in
            1)
                read -p "请输入要开放的端口号: " PORT
                if ! iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
                    iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
                    iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
                fi
                netfilter-persistent save 2>/dev/null || true
                echo -e "${GREEN}✅ 已开放端口 $PORT${RESET}"
                ;;
            2)
                read -p "请输入要关闭的端口号: " PORT
                while iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; do
                    iptables -D INPUT -p tcp --dport "$PORT" -j ACCEPT
                done
                while iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null; do
                    iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT
                done
                netfilter-persistent save 2>/dev/null || true
                echo -e "${GREEN}✅ 已关闭端口 $PORT${RESET}"
                ;;
            3)
                iptables -P INPUT ACCEPT
                iptables -P FORWARD ACCEPT
                iptables -P OUTPUT ACCEPT
                netfilter-persistent save 2>/dev/null || true
                echo -e "${GREEN}✅ 已开放所有端口${RESET}"
                ;;
            4)
                init_rules
                echo -e "${GREEN}✅ 已关闭所有端口，仅放行 SSH/80/443${RESET}"
                ;;
            5)
                read -p "请输入要放行的IP: " IP
                if ! iptables -C INPUT -s "$IP" -j ACCEPT 2>/dev/null; then
                    iptables -I INPUT -s "$IP" -j ACCEPT
                fi
                netfilter-persistent save 2>/dev/null || true
                echo -e "${GREEN}✅ IP $IP 已被放行${RESET}"
                ;;
            6)
                read -p "请输入要封锁的IP: " IP
                if ! iptables -C INPUT -s "$IP" -j DROP 2>/dev/null; then
                    iptables -I INPUT -s "$IP" -j DROP
                fi
                netfilter-persistent save 2>/dev/null || true
                echo -e "${GREEN}✅ IP $IP 已被封禁${RESET}"
                ;;
            7)
                read -p "请输入要删除的IP: " IP
                # 删除 ACCEPT 规则
                while iptables -C INPUT -s "$IP" -j ACCEPT 2>/dev/null; do
                    iptables -D INPUT -s "$IP" -j ACCEPT
                done
                # 删除 DROP 规则
                while iptables -C INPUT -s "$IP" -j DROP 2>/dev/null; do
                    iptables -D INPUT -s "$IP" -j DROP
                done
                netfilter-persistent save 2>/dev/null || true
                echo -e "${GREEN}✅ IP $IP 已从防火墙规则中移除${RESET}"
                ;;
            8)
                echo -e "${YELLOW}当前防火墙规则:${RESET}"
                iptables -L -n --line-numbers
                read -p "按回车继续..."
                ;;
            9)
                clear_firewall
                ;;
            10)
                restore_default_rules
                ;;
            0)
                exit 0
                ;;
            *)
                echo -e "${RED}❌ 无效输入${RESET}"
                ;;
        esac
    done
}

# 主逻辑
if check_installed; then
    menu
else
    echo -e "${YELLOW}⚠️ 防火墙未安装，是否现在安装？(Y/N)${RESET}"
    read -p "选择: " choice
    case "$choice" in
        [Yy]) install_firewall && menu ;;
        [Nn]) echo "已取消" && exit 0 ;;
        *) echo -e "${RED}❌ 无效选择${RESET}" && exit 1 ;;
    esac
fi
