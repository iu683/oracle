#!/bin/bash

# ================== 颜色定义 ==================
green="\033[32m"
re="\033[0m"

# ================== 工具函数 ==================
random_port() {
    shuf -i 2000-65000 -n 1
}

check_udp_port() {
    local port=$1
    while ss -u -l -n | awk '{print $5}' | grep -w ":$port" >/dev/null 2>&1; do
        echo -e "${green}${port}端口已经被其他程序占用，请更换端口重试${re}"
        read -p "请输入端口（回车随机端口）: " port
        [[ -z $port ]] && port=$(random_port)
    done
    echo $port
}

open_firewall_port() {
    local port=$1
    # ufw
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $port/udp >/dev/null 2>&1
    fi
    # firewalld
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=${port}/udp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
    # iptables
    if command -v iptables >/dev/null 2>&1; then
        iptables -C INPUT -p udp --dport $port -j ACCEPT >/dev/null 2>&1 || \
        iptables -I INPUT -p udp --dport $port -j ACCEPT
    fi
}

show_status() {
    clear
    echo -e "${green}Hysteria2 服务状态：${re}"
    if [ -f "/etc/alpine-release" ]; then
        if pgrep -f '[w]eb' >/dev/null 2>&1; then
            echo -e "${green}运行中 (Alpine版)${re}"
            echo -e "${green}监听端口: $(grep -Po '(?<=listen: :)[0-9]+' /root/config.yaml)${re}"
        else
            echo -e "${green}未运行${re}"
        fi
    else
        if systemctl is-active --quiet hysteria-server.service; then
            echo -e "${green}运行中${re}"
            port=$(grep -Po '(?<=listen: :)[0-9]+' /etc/hysteria/config.yaml)
            echo -e "${green}监听端口: $port${re}"
        else
            echo -e "${green}未运行${re}"
        fi
    fi
    echo
    read -p "按回车返回菜单..."
}

show_client_config() {
    echo
    if [ -f "/etc/alpine-release" ]; then
        port=$(grep -Po '(?<=listen: :)[0-9]+' /root/config.yaml)
    else
        port=$(grep -Po '(?<=listen: :)[0-9]+' /etc/hysteria/config.yaml)
    fi
    ip=$(curl -s https://api.ipify.org)
    echo -e "${green}服务器 IP: $ip${re}"
    echo -e "${green}服务器端口: $port${re}"
    echo -e "${green}协议: hysteria${re}"
    echo
    read -p "按回车返回菜单..."
}

# ================== 主菜单 ==================
while true; do
    clear
    echo "--------------"
    echo -e "${green}1. 安装 Hysteria2${re}"
    echo -e "${green}2. 查看 Hysteria2状态${re}"
    echo -e "${green}3. 更换 Hysteria2端口${re}"
    echo -e "${green}4. 卸载 Hysteria2${re}"
    echo -e "${green}0. 退出${re}"
    echo "--------------"

    read -p $'\033[1;32m请输入你的选择: \033[0m' sub_choice
    case $sub_choice in
        1)
            clear
            port=$(random_port)
            port=$(check_udp_port $port)

            open_firewall_port $port

            if [ -f "/etc/alpine-release" ]; then
                SERVER_PORT=$port bash -c "$(curl -fsSL https://raw.githubusercontent.com/iu683/star/main/hy2.sh)"
            else
                HY2_PORT=$port bash -c "$(curl -fsSL https://raw.githubusercontent.com/iu683/star/main/azHysteria2.sh)"
            fi

            echo -e "${green}Hysteria2 安装完成！端口: $port${re}"
            show_client_config
            ;;
        2)
            show_status
            ;;
        3)
            clear
            new_port=$(random_port)
            new_port=$(check_udp_port $new_port)

            open_firewall_port $new_port

            if [ -f "/etc/alpine-release" ]; then
                sed -i "s/^listen: :[0-9]*/listen: :$new_port/" /root/config.yaml
                pkill -f '[w]eb'
                nohup ./web server config.yaml >/dev/null 2>&1 &
            else
                sed -i "s/^listen: :[0-9]*/listen: :$new_port/" /etc/hysteria/config.yaml
                systemctl restart hysteria-server.service
            fi
            echo -e "${green}Hysteria2端口已更换成 $new_port${re}"
            show_client_config
            ;;
        4)
            clear
            if [ -f "/etc/alpine-release" ]; then
                pkill -f '[w]eb'
                pkill -f '[n]pm'
                cd && rm -rf web npm server.crt server.key config.yaml
            else
                systemctl stop hysteria-server.service
                rm -f /usr/local/bin/hysteria
                rm -f /etc/systemd/system/hysteria-server.service
                rm -f /etc/hysteria/config.yaml
                systemctl daemon-reload
            fi
            echo -e "${green}Hysteria2 已彻底卸载${re}"
            sleep 1
            ;;
        0)
            echo -e "${green}已退出脚本${re}"
            exit 0
            ;;
        *)
            echo -e "${green}无效的输入！${re}"
            sleep 1
            ;;
    esac
done
