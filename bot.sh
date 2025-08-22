#!/bin/bash
# SaveAny-Bot 管理脚本
# Author: xiaoxim

#=================================
# 基础配置（可自定义挂载路径）
#=================================
CONTAINER_NAME="saveany-bot"
IMAGE_NAME="ghcr.io/krau/saveany-bot:latest"
COMPOSE_FILE="docker-compose.yml"
CONFIG_FILE="./config.toml"

# 默认挂载路径（可修改）
DATA_DIR="./data"
DOWNLOADS_DIR="./downloads"
CACHE_DIR="./cache"

# 颜色
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

#=================================
# 功能函数
#=================================
function check_container() {
    docker ps -a --format '{{.Names}}' | grep -w "$CONTAINER_NAME" >/dev/null 2>&1
}

function start_bot() {
    if check_container; then
        echo -e "${GREEN}>>> 启动 $CONTAINER_NAME ...${RESET}"
        docker start "$CONTAINER_NAME"
    else
        echo -e "${YELLOW}>>> 未找到容器，使用 docker run 创建 ...${RESET}"
        docker run -d \
            --name "$CONTAINER_NAME" \
            --restart unless-stopped \
            --network host \
            -v "$DATA_DIR:/app/data" \
            -v "$CONFIG_FILE:/app/config.toml" \
            -v "$DOWNLOADS_DIR:/app/downloads" \
            -v "$CACHE_DIR:/app/cache" \
            "$IMAGE_NAME"
    fi
}

function stop_bot() {
    echo -e "${GREEN}>>> 停止 $CONTAINER_NAME ...${RESET}"
    docker stop "$CONTAINER_NAME"
}

function restart_bot() {
    echo -e "${GREEN}>>> 重启 $CONTAINER_NAME ...${RESET}"
    docker restart "$CONTAINER_NAME"
}

function logs_bot() {
    echo -e "${GREEN}>>> 查看 $CONTAINER_NAME 日志 (Ctrl+C 退出) ...${RESET}"
    docker logs -f "$CONTAINER_NAME"
}

function update_bot() {
    echo -e "${GREEN}>>> 更新镜像并重启 $CONTAINER_NAME ...${RESET}"
    docker pull "$IMAGE_NAME"
    stop_bot
    docker rm -f "$CONTAINER_NAME"
    start_bot
}

function remove_bot() {
    echo -e "${RED}>>> 删除 $CONTAINER_NAME 容器 (保留数据卷) ...${RESET}"
    docker rm -f "$CONTAINER_NAME"
}

function edit_config() {
    echo -e "${YELLOW}>>> 正在打开配置文件: $CONFIG_FILE ${RESET}"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，已自动创建一个空文件${RESET}"
        touch "$CONFIG_FILE"
    fi
    if command -v nano >/dev/null 2>&1; then
        nano "$CONFIG_FILE"
    else
        vi "$CONFIG_FILE"
    fi
    echo -e "${GREEN}配置文件修改完成，可选择重启 Bot 生效${RESET}"
}

function set_paths() {
    echo -e "${YELLOW}>>> 当前路径配置:${RESET}"
    echo "DATA_DIR      = $DATA_DIR"
    echo "DOWNLOADS_DIR = $DOWNLOADS_DIR"
    echo "CACHE_DIR     = $CACHE_DIR"
    echo "CONFIG_FILE   = $CONFIG_FILE"
    echo ""
    read -p "请输入新的数据目录路径(回车跳过): " new_data
    read -p "请输入新的下载目录路径(回车跳过): " new_dl
    read -p "请输入新的缓存目录路径(回车跳过): " new_cache
    read -p "请输入新的配置文件路径(回车跳过): " new_cfg

    [ -n "$new_data" ] && DATA_DIR="$new_data"
    [ -n "$new_dl" ] && DOWNLOADS_DIR="$new_dl"
    [ -n "$new_cache" ] && CACHE_DIR="$new_cache"
    [ -n "$new_cfg" ] && CONFIG_FILE="$new_cfg"

    echo -e "${GREEN}路径修改完成！下次启动将使用新的挂载路径${RESET}"
}

#=================================
# 菜单
#=================================
function menu() {
    clear
    echo -e "${YELLOW}========== SaveAny-Bot 管理菜单 ==========${RESET}"
    echo -e "${GREEN}1.${RESET} 启动 Bot"
    echo -e "${GREEN}2.${RESET} 停止 Bot"
    echo -e "${GREEN}3.${RESET} 重启 Bot"
    echo -e "${GREEN}4.${RESET} 查看日志"
    echo -e "${GREEN}5.${RESET} 更新镜像并重启"
    echo -e "${GREEN}6.${RESET} 删除容器"
    echo -e "${GREEN}7.${RESET} 编辑配置文件 (config.toml)"
    echo -e "${GREEN}8.${RESET} 设置挂载路径"
    echo -e "${GREEN}0.${RESET} 退出"
    echo -e "${YELLOW}==========================================${RESET}"
}

while true; do
    menu
    read -p "请选择操作: " choice
    case "$choice" in
        1) start_bot ;;
        2) stop_bot ;;
        3) restart_bot ;;
        4) logs_bot ;;
        5) update_bot ;;
        6) remove_bot ;;
        7) edit_config ;;
        8) set_paths ;;
        0) echo "退出"; exit 0 ;;
        *) echo -e "${RED}无效的选择，请重新输入${RESET}" ;;
    esac
    echo -e "\n按任意键返回菜单..."
    read -n 1
done
