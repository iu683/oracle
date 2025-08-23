#!/bin/bash

# ================== 颜色定义 ==================
green="\033[32m"
red="\033[31m"
yellow="\033[33m"
skyblue="\033[36m"
re="\033[0m"

# ================== 工具函数 ==================
random_port() {
    shuf -i 2000-65000 -n 1
}

check_udp_port() {
    local port=$1
    while [[ -n $(netstat -tuln | grep -w udp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]; do
        echo -e "${red}${port}端口已经被其他程序占用，请更换端口重试${re}"
        read -p "请输入端口（回车随机端口）: " port
        [[ -z $port ]] && port=$(random_port)
    done
    echo $port
}

# ================== 主菜单 ==================
while true; do
    clear
    echo "--------------"
    echo -e "${green}1. 安装 Hysteria2${re}"
    echo -e "${red}2. 卸载 Hysteria2${re}"
    echo -e "${yellow}3. 更换 Hysteria2端口${re}"
    echo "--------------"
    echo -e "${skyblue}0. 退出${re}"
    echo "--------------"

    read -p $'\033[1;91m请输入你的选择: \033[0m' sub_choice
    case $sub_choice in
        1)
            clear
            read -p $'\033[1;35m请输入Hysteria2节点端口（回车随机端口）：\033[0m' port
            [[ -z $port ]] && port=$(random_port)
            port=$(check_udp_port $port)

            if [ -f "/etc/alpine-release" ]; then
                SERVER_PORT=$port bash -c "$(curl -fsSL https://raw.githubusercontent.com/Polarisiu/tool/main/hy2.sh)"
            else
                HY2_PORT=$port bash -c "$(curl -fsSL https://raw.githubusercontent.com/Polarisiu/tool/main/azHysteria2.sh)"
            fi

            echo -e "${green}Hysteria2 安装完成！端口: $port${re}"
            sleep 1
            ;;
        2)
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
                clear
            fi
            echo -e "${green}Hysteria2 已卸载${re}"
            sleep 1
            ;;
        3)
            clear
            read -p $'\033[1;35m设置 Hysteria2 端口[1-65535]（回车随机端口）：\033[0m' new_port
            [[ -z $new_port ]] && new_port=$(random_port)
            new_port=$(check_udp_port $new_port)

            if [ -f "/etc/alpine-release" ]; then
                sed -i "s/^listen: :[0-9]*/listen: :$new_port/" /root/config.yaml
                pkill -f '[w]eb'
                nohup ./web server config.yaml >/dev/null 2>&1 &
            else
                sed -i "s/^listen: :[0-9]*/listen: :$new_port/" /etc/hysteria/config.yaml
                systemctl restart hysteria-server.service
            fi
            echo -e "${green}Hysteria2端口已更换成 $new_port，请手动更改客户端配置！${re}"
            sleep 1
            ;;
        0)
            echo -e "${skyblue}已退出脚本${re}"
            exit 0
            ;;
        *)
            echo -e "${red}无效的输入！${re}"
            sleep 1
            ;;
    esac
done
