#!/bin/bash
# =========================================================
# Incus 一键管理脚本（绿色无边框版）
# =========================================================

# 颜色定义
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
PURPLE="\033[0;35m"
SKYBLUE="\033[0;36m"
WHITE="\033[1;37m"
RESET="\033[0m"

# =========================================================
# 工具函数
# =========================================================
pause(){
    echo -e "${YELLOW}按任意键返回菜单...${RESET}"
    read -n 1
}

check_log(){
    for f in ./log /root/log /var/log/incus.log; do
        if [ -f "$f" ]; then
            cat "$f"
            return
        fi
    done
    echo -e "${YELLOW}未找到 log 文件，请稍后再试${RESET}"
}

install_pkg(){
    pkg=$1
    if ! command -v $pkg >/dev/null 2>&1; then
        echo -e "${YELLOW}正在安装依赖：$pkg${RESET}"
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y $pkg
        elif command -v yum >/dev/null 2>&1; then
            yum install -y $pkg
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y $pkg
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache $pkg
        fi
    fi
}

# =========================================================
# 安装和开设 Incus
# =========================================================
install_incus(){
    echo -e "${YELLOW}开始进行环境检测...${RESET}"
    install_pkg wget

    output=$(bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/oneclickvirt/incus/main/scripts/pre_check.sh))
    echo "$output"

    if echo "$output" | grep -q "本机符合作为incus母鸡的要求"; then
        echo -e "${GREEN}你的 VPS 符合要求，可以开设 incus 容器${RESET}"

        read -p $'\033[1;32m确定要安装并开设 incus 小鸡吗？ [y/n]: \033[0m' confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}开始安装 Incus 主体...${RESET}"
            sleep 1
            curl -L https://raw.githubusercontent.com/oneclickvirt/incus/main/scripts/incus_install.sh -o incus_install.sh
            chmod +x incus_install.sh
            bash incus_install.sh

            if command -v incus >/dev/null 2>&1; then
                echo -e "${GREEN}Incus 已安装完成${RESET}"
            else
                echo -e "${RED}Incus 安装失败，请更新系统后重试${RESET}"
                rm -f incus_install.sh
                return
            fi
        fi
    else
        echo -e "${RED}检测未通过，无法安装 Incus${RESET}"
    fi
}
       

# =========================================================
# 管理 Incus 小鸡
# =========================================================
manage_incus(){
    while true; do
        clear
        echo -e "${GREEN}   管理 incus 小鸡${RESET}"
        echo -e "${GREEN}--------------------------------${RESET}"
        echo -e "${GREEN}1. 查看所有小鸡状态${RESET}"
        echo -e "${GREEN}2. 暂停所有小鸡${RESET}"
        echo -e "${GREEN}3. 启动所有小鸡${RESET}"
        echo -e "${GREEN}4. 暂停指定小鸡${RESET}"
        echo -e "${GREEN}5. 启动指定小鸡${RESET}"
        echo -e "${GREEN}6. 新增开设小鸡${RESET}"
        echo -e "${GREEN}7. 删除指定小鸡${RESET}"
        echo -e "${GREEN}8. 删除所有小鸡和配置${RESET}"
        echo -e "${GREEN}0. 返回主菜单${RESET}"
        echo -e "${GREEN}--------------------------------${RESET}"
        read -p "请输入你的选择: " sub_choice

        case $sub_choice in
            1) incus list ; check_log ; pause ;;
            2) incus stop --all ; echo -e "${GREEN}已暂停${RESET}" ; pause ;;
            3) incus start --all ; echo -e "${GREEN}已重启${RESET}" ; pause ;;
            4) read -p "请输入小鸡名: " name ; incus stop $name ; incus info $name | grep Status ; echo -e "${GREEN}已暂停${RESET}" ;pause ;;
            5) read -p "请输入小鸡名: " name ; incus start $name ; incus info $name | grep Status ; echo -e "${GREEN}已暂停${RESET}" ;pause ;;
            6) install_pkg screen ; curl -L https://github.com/oneclickvirt/incus/raw/main/scripts/add_more.sh -o add_more.sh ; chmod +x add_more.sh ; screen bash add_more.sh ; check_log ; pause ;;
            7) read -p "请输入要删除的小鸡名: " name ; incus delete -f $name ; echo -e "${GREEN}$name 已删除${RESET}" ; pause ;;
            8) read -p "确定要删除所有小鸡吗? [y/n]: " confirm ; [[ "$confirm" =~ ^[Yy]$ ]] && incus list -c n --format csv | xargs -I {} incus delete -f {} ; rm -rf ~/.config/incus /var/snap/incus /var/lib/incus ; echo -e "${GREEN}已清理完成${RESET}" ; pause ;;
            0) break ;;
            *) echo -e "${RED}无效选择${RESET}" ; pause ;;
        esac
    done
}

# =========================================================
# 主菜单
# =========================================================
main_menu(){
    while true; do
        clear
        echo -e "${GREEN} Incus 管理脚本${RESET}"
        echo -e "${GREEN}--------------------------------${RESET}"
        echo -e "${GREEN}1. 开设SWAP${RESET}"
        echo -e "${GREEN}2. 安装incus${RESET}"
        echo -e "${GREEN}3. 管理 incus 小鸡${RESET}"
        echo -e "${GREEN}0. 退出${RESET}"
        echo -e "${GREEN}--------------------------------${RESET}"
        read -p "请输入你的选择: " choice
        case $choice in
            1) curl -L https://raw.githubusercontent.com/oneclickvirt/incus/main/scripts/swap.sh -o swap.sh && chmod +x swap.sh && bash swap.sh ;;
            2) install_incus ;;
            3) manage_incus ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选择${RESET}" ; pause ;;
        esac
    done
}

main_menu
