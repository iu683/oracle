#!/bin/bash

# ================== 颜色定义 ==================
green="\033[32m"
red="\033[31m"
yellow="\033[33m"
re="\033[0m"

# ================== 工具函数 ==================
random_port() {
    shuf -i 2000-65000 -n 1
}

check_port() {
    local port=$1
    while [[ -n $(lsof -i :$port 2>/dev/null) ]]; do
        echo -e "${red}${port}端口已经被占用，请更换端口重试${re}"
        read -p "请输入端口（直接回车使用随机端口）: " port
        [[ -z $port ]] && port=$(random_port) && echo -e "${green}使用随机端口: $port${re}"
    done
    echo $port
}

install_lsof() {
    if ! command -v lsof &>/dev/null; then
        if [ -f "/etc/debian_version" ]; then
            apt update && apt install -y lsof
        elif [ -f "/etc/alpine-release" ]; then
            apk add lsof
        fi
    fi
}

install_jq() {
    if ! command -v jq &>/dev/null; then
        if [ -f "/etc/debian_version" ]; then
            apt update && apt install -y jq
        elif [ -f "/etc/alpine-release" ]; then
            apk add jq
        fi
    fi
}

# ================== 主菜单 ==================
while true; do
    clear
    echo "--------------"
    echo -e "${green}1. 安装 Reality${re}"
    echo -e "${green}2. 查看 Reality 状态${re}"
    echo -e "${green}3. 更改 Reality 端口${re}"
    echo -e "${green}4. 卸载 Reality${re}"
    echo "--------------"
    echo -e "${green}0. 退出${re}"
    echo "--------------"

    read -p $'\033[1;32m请输入你的选择: \033[0m' sub_choice
    case $sub_choice in
        1)
            clear
            install_lsof
            read -p $'\033[1;32m请输入Reality节点端口（回车随机端口）: \033[0m' port
            [[ -z $port ]] && port=$(random_port)
            port=$(check_port $port)

            echo -e "${green}开始安装 Reality...${re}"
            PORT=$port bash <(curl -fsSL https://raw.githubusercontent.com/Polarisiu/proxy/main/azreality.sh)

            echo -e "${green}Reality 安装完成！端口: $port${re}"
            sleep 1
            ;;
        2)
            clear
            echo -e "${green}正在检查 Reality 运行状态...${re}"
            if [ -f "/etc/alpine-release" ]; then
                if pgrep -f 'web' >/dev/null; then
                    echo -e "${green}✅ Reality 正在运行${re}"
                    port=$(jq -r '.inbounds[0].port' ~/app/config.json 2>/dev/null)
                    [[ -n $port ]] && echo -e "${green}当前端口: $port${re}"
                else
                    echo -e "${red}❌ Reality 未运行${re}"
                fi
            else
                if systemctl is-active --quiet xray; then
                    echo -e "${green}✅ Reality 正在运行 (systemd 管理)${re}"
                    port=$(jq -r '.inbounds[] | select(.protocol=="vless").port' /usr/local/etc/xray/config.json 2>/dev/null)
                    [[ -n $port ]] && echo -e "${green}当前端口: $port${re}"
                else
                    echo -e "${red}❌ Reality 未运行${re}"
                fi
            fi
            read -p "按回车返回菜单..."
            ;;
        3)
            clear
            install_jq
            read -p $'\033[1;32m请输入新 Reality 端口（回车随机端口）: \033[0m' new_port
            [[ -z $new_port ]] && new_port=$(random_port)
            new_port=$(check_port $new_port)

            if [ -f "/etc/alpine-release" ]; then
                jq --argjson new_port "$new_port" \
                   '(.inbounds[] | select(.protocol=="vless")).port = $new_port' \
                   ~/app/config.json > tmp.json && mv tmp.json ~/app/config.json
                pkill -f 'web'
                cd ~/app
                nohup ./web -c config.json >/dev/null 2>&1 &
            else
                jq --argjson new_port "$new_port" \
                   '(.inbounds[] | select(.protocol=="vless")).port = $new_port' \
                   /usr/local/etc/xray/config.json > tmp.json && mv tmp.json /usr/local/etc/xray/config.json
                systemctl restart xray.service
            fi
            echo -e "${green}Reality端口已更换成 $new_port，请手动更新客户端配置！${re}"
            sleep 1
            ;;
        4)
            clear
            if [ -f "/etc/alpine-release" ]; then
                pkill -f 'web'
                rm -rf ~/app
            else
                systemctl stop xray 2>/dev/null
                systemctl disable xray 2>/dev/null
                rm -f /usr/local/bin/xray \
                      /etc/systemd/system/xray.service \
                      /usr/local/etc/xray/config.json \
                      /usr/local/share/xray/geoip.dat \
                      /usr/local/share/xray/geosite.dat \
                      /etc/systemd/system/xray@.service
                rm -rf /var/log/xray /var/lib/xray
                systemctl daemon-reload
            fi
            echo -e "${green}Reality 已卸载${re}"
            sleep 1
            ;;
        0)
            echo -e "${green}已退出脚本${re}"
            exit 0
            ;;
        *)
            echo -e "${red}无效输入！${re}"
            sleep 1
            ;;
    esac
done
