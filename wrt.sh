#!/bin/bash
# MTProto Proxy 管理脚本 for Docker (ellermister/mtproxy, 无需手动设置 secret)

NAME="mtproxy"
IMAGE="ellermister/mtproxy"
VOLUME="mtproxy-data"

GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

# 检测端口是否被占用
function check_port() {
    local port=$1
    if command -v lsof >/dev/null 2>&1; then
        lsof -i :"$port" >/dev/null 2>&1
    elif command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -q ":$port "
    else
        netstat -tuln 2>/dev/null | grep -q ":$port "
    fi
    # 返回 0 表示可用，1 表示被占用
    if [[ $? -eq 0 ]]; then
        return 1
    else
        return 0
    fi
}

# 获取随机可用端口
function get_random_port() {
    while true; do
        PORT=$(shuf -i 1025-65535 -n 1)
        check_port $PORT && { echo $PORT; break; }
    done
}

# 获取公网 IP
function get_ip() {
    curl -s https://api.ipify.org || \
    curl -s ifconfig.me || \
    curl -s icanhazip.com
}

# ========= 安装并启动代理 =========
function install_proxy() {
    echo -e "\n${GREEN}=== 安装并启动 MTProto Proxy ===${RESET}\n"
    read -p "请输入外部端口 (默认 8443, 留空随机): " PORT
    if [[ -z "$PORT" ]]; then
        PORT=$(get_random_port)
        echo "随机选择未占用端口: $PORT"
    else
        while ! check_port $PORT; do
            echo "端口 $PORT 已被占用，请重新输入"
            read -p "端口: " PORT
        done
    fi

    read -p "IP 白名单选项 (OFF/IP/IPSEG, 默认 OFF): " IPWL
    IPWL=${IPWL:-OFF}
    read -p "请输入 domain (伪装域名, 默认 cloudflare.com): " DOMAIN
    DOMAIN=${DOMAIN:-cloudflare.com}

    # 删除旧容器
    if docker ps -a --format '{{.Names}}' | grep -Eq "^${NAME}\$"; then
        echo "⚠️ 已存在旧容器，先删除..."
        docker rm -f ${NAME}
    fi

    docker volume create ${VOLUME} >/dev/null 2>&1

    docker run -d --name ${NAME} \
        --restart=always \
        -v ${VOLUME}:/data \
        -e domain="${DOMAIN}" \
        -e ip_white_list="${IPWL}" \
        -p 8080:80 \
        -p ${PORT}:443 \
        ${IMAGE}

    echo "⏳ 等待 5 秒让容器启动..."
    sleep 5

    if ! docker ps --format '{{.Names}}' | grep -Eq "^${NAME}\$"; then
        echo "❌ 容器未启动，请查看 Docker 日志。"
        return
    fi

    IP=$(get_ip)

    # 提取 Secret
    SECRET=$(docker logs --tail 50 ${NAME} 2>&1 | grep "MTProxy Secret" | awk '{print $NF}' | tail -n1)

    echo -e "\n${GREEN}✅ 安装完成！代理信息如下：${RESET}"
    echo "服务器 IP: $IP"
    echo "端口     : $PORT"
    echo "Secret   : $SECRET"
    echo "domain   : $DOMAIN"
    echo
    echo "👉 Telegram 链接："
    echo "tg://proxy?server=$IP&port=$PORT&secret=$SECRET"
}


function uninstall_proxy() {
    echo -e "\n${GREEN}=== 卸载 MTProto Proxy ===${RESET}\n"
    docker rm -f ${NAME} >/dev/null 2>&1
    docker volume rm -f ${VOLUME} >/dev/null 2>&1
    echo "✅ 已卸载并清理配置。"
}

function show_logs() {
    if ! docker ps --format '{{.Names}}' | grep -Eq "^${NAME}\$"; then
        echo "❌ 容器未运行，请先安装或启动代理。"
        return
    fi
    echo -e "\n${GREEN}=== MTProto Proxy 日志 (最近50行) ===${RESET}\n"
    docker logs --tail=50 -f ${NAME}
}

# ========= 修改配置并重启容器 =========
function modify_proxy() {
    echo -e "\n${YELLOW}=== 修改配置并重启 MTProto Proxy ===${RESET}\n"
    read -p "请输入新的端口 (留空则不修改): " NEW_PORT
    read -p "请输入新的 domain (留空则不修改): " NEW_DOMAIN
    read -p "IP 白名单选项 (OFF/IP/IPSEG, 留空则不修改): " NEW_IPWL

    # 删除旧容器
    docker rm -f ${NAME} >/dev/null 2>&1

    PORT=${NEW_PORT:-8443}
    DOMAIN=${NEW_DOMAIN:-cloudflare.com}
    IPWL=${NEW_IPWL:-OFF}

    docker run -d --name ${NAME} \
        --restart=always \
        -v ${VOLUME}:/data \
        -e domain="${DOMAIN}" \
        -e ip_white_list="${IPWL}" \
        -p 8080:80 \
        -p ${PORT}:443 \
        ${IMAGE}

    echo "⏳ 等待 5 秒让容器重启..."
    sleep 5

    if ! docker ps --format '{{.Names}}' | grep -Eq "^${NAME}\$"; then
        echo "❌ 容器未启动，请查看 Docker 日志。"
        return
    fi

    IP=$(get_ip)
    SECRET=$(docker logs --tail 50 ${NAME} 2>&1 | grep -oE "MTProxy Secret: [a-f0-9]+" | awk '{print $3}' | tail -n1)
    
    echo -e "\n${GREEN}✅ 配置修改完成！代理信息如下：${RESET}"
    echo "服务器 IP: $IP"
    echo "端口     : $PORT"
    echo "Secret   : $SECRET"
    echo "domain   : $DOMAIN"
    echo
    echo "👉 Telegram 链接："
    echo "tg://proxy?server=$IP&port=$PORT&secret=$SECRET"
}

function menu() {
    echo -e "\n${GREEN}===== MTProto Proxy 管理脚本 =====${RESET}"
    echo -e "${GREEN}1. 安装并启动代理${RESET}"
    echo -e "${GREEN}2. 卸载代理${RESET}"
    echo -e "${GREEN}3. 查看运行日志${RESET}"
    echo -e "${GREEN}4. 修改配置并重启容器${RESET}"
    echo -e "${GREEN}0. 退出${RESET}"
    echo -e "${GREEN}=================================${RESET}"
    read -p "请输入选项: " choice
    case "$choice" in
        1) install_proxy ;;
        2) uninstall_proxy ;;
        3) show_logs ;;
        4) modify_proxy ;;
        0) exit 0 ;;
        *) echo "❌ 无效输入" ;;
    esac
}

while true; do
    menu
done
