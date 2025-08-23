#!/bin/bash
# ========================================
# VPS 管理菜单脚本
# ========================================

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[1;36m"
RESET="\033[0m"

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 权限运行脚本${RESET}"
    exit 1
fi

# 安装必备工具
install_tool() {
    if ! command -v "$1" &> /dev/null; then
        apt-get update
        apt-get install -y "$1"
    fi
}

# ========================================
# 功能函数
# ========================================

swap_manage() {
    echo -e "${YELLOW}开设虚拟内存(Swap)${RESET}"
    curl -L https://raw.githubusercontent.com/spiritLHLS/addswap/main/addswap.sh -o addswap.sh
    chmod +x addswap.sh
    bash addswap.sh
}

docker_install() {
    echo -e "${YELLOW}开始安装 Docker${RESET}"
    curl -L https://raw.githubusercontent.com/spiritLHLS/docker/main/scripts/dockerinstall.sh -o dockerinstall.sh
    chmod +x dockerinstall.sh
    bash dockerinstall.sh
}

docker_one() {
    install_tool screen
    curl -L https://raw.githubusercontent.com/spiritLHLS/docker/main/scripts/onedocker.sh -o onedocker.sh
    chmod +x onedocker.sh
    screen -S onedocker -dm bash onedocker.sh
    echo -e "${GREEN}单个 Docker 小鸡已启动在后台${RESET}"
}

docker_batch() {
    install_tool screen
    curl -L https://raw.githubusercontent.com/spiritLHLS/docker/main/scripts/create_docker.sh -o create_docker.sh
    chmod +x create_docker.sh
    screen -S dockerbatch -dm bash create_docker.sh
    echo -e "${GREEN}批量 Docker 小鸡已启动在后台${RESET}"
}

docker_cleanup() {
    echo -e "${YELLOW}删除 ndpresponder Docker 容器和镜像${RESET}"
    containers=$(docker ps -aq --format '{{.Names}}' | grep -E '^ndpresponder')
    [ -n "$containers" ] && docker rm -f $containers

    images=$(docker images -aq --format '{{.Repository}}:{{.Tag}}' | grep -E '^ndpresponder')
    [ -n "$images" ] && docker rmi $images

    rm -rf dclog
    echo -e "${GREEN}清理完成${RESET}"
}

system_reboot() {
    echo -e "${YELLOW}系统即将重启...${RESET}"
    sleep 2
    reboot
}

# ========================================
# 主菜单
# ========================================

while true; do
    clear
    echo -e "${CYAN}================= VPS 管理菜单 =================${RESET}"
    echo -e "${GREEN}1. 开设/移除 Swap${RESET}"
    echo -e "${GREEN}2. 安装 Docker${RESET}"
    echo -e "${GREEN}3. 单个开设 Docker 小鸡${RESET}"
    echo -e "${GREEN}4. 批量开设 Docker 小鸡${RESET}"
    echo -e "${GREEN}5. 删除 Docker 容器和镜像${RESET}"
    echo -e "${GREEN}6. 重启系统${RESET}"
    echo -e "${GREEN}0. 退出脚本${RESET}"
    echo -e "${CYAN}===============================================${RESET}"

    read -p "请输入你的选择 [0-6]: " choice

    case "$choice" in
        1) swap_manage ;;
        2) docker_install ;;
        3) docker_one ;;
        4) docker_batch ;;
        5) docker_cleanup ;;
        6) system_reboot ;;
        0) echo -e "${GREEN}退出脚本${RESET}"; exit 0 ;;
        *) echo -e "${RED}输入错误，请输入 0-6${RESET}"; sleep 2 ;;
    esac

    echo -e "${CYAN}按回车键返回主菜单...${RESET}"
    read
done
