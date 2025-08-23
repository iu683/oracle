#!/bin/bash

GREEN="\033[32m"
RED="\033[31m"
RESET="\033[0m"

menu() {
    clear
    echo -e "${GREEN}=== 开小鸡管理菜单 ===${RESET}"
    echo -e "${GREEN}1) KVM 小鸡${RESET}"
    echo -e "${GREEN}2) LXC 小鸡${RESET}"
    echo -e "${GREEN}3) Docker 小鸡${RESET}"
    echo -e "${GREEN}0) 退出${RESET}"
    echo
    read -p $'\033[32m请选择操作 (0-3): \033[0m' choice
    case $choice in
        1)
            echo -e "${GREEN}正在运行 KVM 小鸡脚本...${RESET}"
            bash <(curl -fsSL https://raw.githubusercontent.com/iu683/star//main/kvm.sh)
            pause
            ;;
        2)
            echo -e "${GREEN}正在运行 LXC 小鸡脚本...${RESET}"
            bash <(curl -fsSL https://raw.githubusercontent.com/iu683/star//main/lxc.sh)
            pause
            ;;
        3)
            echo -e "${GREEN}正在运行 Docker 小鸡脚本...${RESET}"
            bash <(curl -fsSL https://raw.githubusercontent.com/iu683/star//main/dockerlxc.sh)
            pause
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择，请重新输入${RESET}"
            sleep 1
            menu
            ;;
    esac
}

pause() {
    read -p $'\033[32m按回车键返回菜单...\033[0m'
    menu
}

menu
