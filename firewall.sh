#!/bin/bash
set -e

# 颜色定义
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# 获取当前 SSH 端口
get_ssh_port() {
    grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}' | head -n 1
}

# 初始化规则
init_rules() {
    ssh_port=$(get_ssh_port)
    cat > /etc/iptables/rules.v4 << EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A FORWARD -i lo -j ACCEPT
-A INPUT -p tcp --dport $ssh_port -j ACCEPT
-A INPUT -p tcp --dport 80 -j ACCEPT
-A INPUT -p tcp --dport 443 -j ACCEPT
COMMIT
EOF
    iptables-restore < /etc/iptables/rules.v4
}

# 检查是否安装防火墙
check_installed() {
    dpkg -l | grep -q iptables-persistent
}

# 安装防火墙
install_firewall() {
    apt update -y
    apt remove -y ufw iptables-persistent || true
    apt install -y iptables-persistent
    init_rules
    systemctl enable netfilter-persistent
    echo -e "${GREEN}✅ 防火墙安装完成，已默认放行 SSH/80/443${RESET}"
}

# 卸载防火墙
uninstall_firewall() {
    iptables -F
    iptables -X
    rm -f /etc/iptables/rules.v4
    apt remove -y ufw iptables-persistent
    systemctl disable netfilter-persistent 2>/dev/null || true
    echo -e "${RED}❌ 防火墙已卸载并关闭${RESET}"
}

# 主菜单
menu() {
    while true; do
        clear
        echo -e "${GREEN}============================${RESET}"
        echo -e "${GREEN} 🔥 防火墙管理脚本${RESET}"
        echo -e "${GREEN}============================${RESET}"
        echo -e "${GREEN}1. 开放指定端口${RESET}"
        echo -e "${GREEN}2. 关闭指定端口${RESET}"
        echo -e "${GREEN}3. 开放所有端口${RESET}"
        echo -e "${GREEN}4. 关闭所有端口${RESET}"
        echo -e "${GREEN}5. 添加 IP 白名单${RESET}"
        echo -e "${GREEN}6. 添加 IP 黑名单${RESET}"
        echo -e "${GREEN}7. 删除 IP 规则${RESET}"
        echo -e "${GREEN}8. 显示当前规则${RESET}"
        echo -e "${GREEN}9. 卸载防火墙${RESET}"
        echo -e "${GREEN}0. 退出${RESET}"
        echo -e "${GREEN}============================${RESET}"
        read -p "请输入选择: " choice

        case $choice in
            1)
                read -p "请输入要开放的端口号: " o_port
                grep -q -- "--dport $o_port" /etc/iptables/rules.v4 || {
                    sed -i "/COMMIT/i -A INPUT -p tcp --dport $o_port -j ACCEPT" /etc/iptables/rules.v4
                    sed -i "/COMMIT/i -A INPUT -p udp --dport $o_port -j ACCEPT" /etc/iptables/rules.v4
                    iptables-restore < /etc/iptables/rules.v4
                }
                echo -e "${GREEN}✅ 已开放端口 $o_port${RESET}"
                ;;
            2)
                read -p "请输入要关闭的端口号: " c_port
                sed -i "/--dport $c_port/d" /etc/iptables/rules.v4
                iptables-restore < /etc/iptables/rules.v4
                echo -e "${GREEN}✅ 已关闭端口 $c_port${RESET}"
                ;;
            3)
                ssh_port=$(get_ssh_port)
                cat > /etc/iptables/rules.v4 << EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A FORWARD -i lo -j ACCEPT
-A INPUT -p tcp --dport $ssh_port -j ACCEPT
COMMIT
EOF
                iptables-restore < /etc/iptables/rules.v4
                echo -e "${GREEN}✅ 已开放所有端口${RESET}"
                ;;
            4)
                init_rules
                echo -e "${GREEN}✅ 已关闭所有端口，仅放行 SSH/80/443${RESET}"
                ;;
            5)
                read -p "请输入要放行的IP: " o_ip
                grep -q -- "-A INPUT -s $o_ip -j ACCEPT" /etc/iptables/rules.v4 || {
                    sed -i "/COMMIT/i -A INPUT -s $o_ip -j ACCEPT" /etc/iptables/rules.v4
                    iptables-restore < /etc/iptables/rules.v4
                }
                echo -e "${GREEN}✅ 已放行IP $o_ip${RESET}"
                ;;
            6)
                read -p "请输入要封锁的IP: " c_ip
                grep -q -- "-A INPUT -s $c_ip -j DROP" /etc/iptables/rules.v4 || {
                    sed -i "/COMMIT/i -A INPUT -s $c_ip -j DROP" /etc/iptables/rules.v4
                    iptables-restore < /etc/iptables/rules.v4
                }
                echo -e "${GREEN}✅ 已封锁IP $c_ip${RESET}"
                ;;
            7)
                read -p "请输入要删除的IP: " d_ip
                sed -i "/-A INPUT -s $d_ip/d" /etc/iptables/rules.v4
                iptables-restore < /etc/iptables/rules.v4
                echo -e "${GREEN}✅ 已删除IP规则 $d_ip${RESET}"
                ;;
            8)
                echo -e "${YELLOW}当前防火墙规则:${RESET}"
                iptables -L -n --line-numbers
                read -p "按回车继续..."
                ;;
            9)
                uninstall_firewall
                exit 0
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

# 主执行逻辑
if check_installed; then
    menu
else
    echo -e "${YELLOW}⚠️  防火墙未安装，是否现在安装？(Y/N)${RESET}"
    read -p "选择: " choice
    case "$choice" in
        [Yy]) install_firewall && menu ;;
        [Nn]) echo "已取消" && exit 0 ;;
        *) echo -e "${RED}❌ 无效选择${RESET}" && exit 1 ;;
    esac
fi
