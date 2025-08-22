#!/bin/bash
# LXD + LXC 菜单管理脚本（含批量生成）
# 依赖: wget, curl, screen, sudo, dos2unix, jq
# 作者: ChatGPT

# ================== 颜色定义 ==================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PURPLE="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"
RESET="\033[0m"

# ================== 工具函数 ==================
install_pkg() {
    for pkg in "$@"; do
        if ! dpkg -s $pkg >/dev/null 2>&1; then
            echo -e "${YELLOW}安装依赖: $pkg ...${RESET}"
            apt-get update -y
            apt-get install -y $pkg
        fi
    done
}

break_end() {
    echo ""
    read -p $'\033[1;36m按任意键返回菜单...\033[0m' -n 1
}

check_lxc() {
    if command -v lxc >/dev/null 2>&1; then
        echo -e "${GREEN}LXD 已安装完成${RESET}"
    else
        echo -e "${YELLOW}lxc 未找到，尝试修复软连接...${RESET}"
        export PATH=$PATH:/snap/bin
        if ! command -v lxc >/dev/null 2>&1; then
            echo -e "${RED}修复失败，请手动检查 LXD 安装${RESET}"
            return 1
        fi
    fi
}

# ================== 环境检测 ==================
pre_check() {
    echo -e "${YELLOW}开始进行环境检测...${RESET}"
    install_pkg wget
    output=$(bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/pre_check.sh))
    echo "$output"
    if echo "$output" | grep -q "本机符合作为LXC母鸡的要求，可以批量开设LXC容器"; then
        echo -e "${GREEN}你的 VPS 已通过检测，可以开设 LXC 小鸡${RESET}"
        return 0
    else
        echo -e "${RED}你的 VPS 不符合开设 LXC 母鸡要求，请选择 Incus 或 Docker 方式开设小鸡${RESET}"
        return 1
    fi
}

# ================== LXD 安装 ==================
install_lxd() {
    echo -e "${YELLOW}开始安装 LXD 主体...${RESET}"
    curl -L https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/lxdinstall.sh -o lxdinstall.sh
    chmod +x lxdinstall.sh
    bash lxdinstall.sh
    check_lxc
    echo -e "${YELLOW}安装完成，建议重启系统后再进入 LXC 管理菜单${RESET}"
    break_end
}

# ================== LXC 批量生成 ==================
batch_create_lxc() {
    while true; do
        clear
        echo -e "${PURPLE}▶ 批量生成 LXC 小鸡${RESET}"
        echo "------------------------"
        echo -e "${CYAN}1. 普通批量生成(1核/256MB/1GB/限速300Mbit)${RESET}"
        echo -e "${CYAN}2. 自定义配置批量生成${RESET}"
        echo -e "${WHITE}0. 返回上一级菜单${RESET}"
        echo "------------------------"
        read -p $'\033[1;91m请输入你的选择: \033[0m' choice

        case $choice in
            1)
                install_pkg screen wget sudo dos2unix jq
                curl -L https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/init.sh -o init.sh
                chmod +x init.sh && dos2unix init.sh
                read -p $'\033[1;35m请输入要生成小鸡的数量: \033[0m' number
                echo -e "${GREEN}正在后台自动为你开设小鸡中，可关闭 SSH，完成后运行 cat log 查看信息${RESET}"
                screen -S lxc_batch bash init.sh lxc "$number"
                echo -e "${GREEN}任务已启动在 screen 中，运行: screen -r lxc_batch 查看进度${RESET}"
                break_end
            ;;
            2)
                install_pkg screen wget sudo dos2unix jq
                curl -L https://github.com/oneclickvirt/lxd/raw/main/scripts/add_more.sh -o add_more.sh
                chmod +x add_more.sh
                echo -e "${GREEN}输入配置后将进入后台生成小鸡，可关闭 SSH，完成后运行 cat log 查看信息${RESET}"
                screen -S lxc_custom bash add_more.sh
                echo -e "${GREEN}任务已启动在 screen 中，运行: screen -r lxc_custom 查看进度${RESET}"
                break_end
            ;;
            0) break ;;
            *)
                echo -e "${RED}无效选择，请输入 0~2${RESET}"
                break_end
            ;;
        esac
    done
}

# ================== LXC 管理 ==================
manage_lxc() {
    while true; do
        clear
        echo -e "${PURPLE}▶ 管理 LXC 小鸡${RESET}"
        echo "------------------------"
        echo -e "${CYAN}1. 查看所有 LXC 小鸡${RESET}"
        echo -e "${CYAN}2. 暂停所有 LXC 小鸡${RESET}"
        echo -e "${CYAN}3. 启动所有 LXC 小鸡${RESET}"
        echo -e "${CYAN}4. 暂停指定 LXC 小鸡${RESET}"
        echo -e "${CYAN}5. 启动指定 LXC 小鸡${RESET}"
        echo -e "${CYAN}6. 重装指定 LXC 小鸡系统${RESET}"
        echo -e "${CYAN}7. 批量生成 LXC 小鸡${RESET}"
        echo -e "${CYAN}8. 新增 LXC 小鸡${RESET}"
        echo -e "${RED}9. 删除指定 LXC 小鸡${RESET}"
        echo -e "${RED}10. 删除所有 LXC 小鸡和配置${RESET}"
        echo -e "${WHITE}0. 返回上一级菜单${RESET}"
        echo "------------------------"
        read -p $'\033[1;91m请输入你的选择: \033[0m' choice

        case $choice in
            1) clear; echo -e "${GREEN}所有 LXC 小鸡运行状态：${RESET}"; lxc list; echo -e "${GREEN}密码端口信息:${RESET}"; cat log; break_end ;;
            2) lxc stop --all; echo -e "${GREEN}已暂停所有小鸡${RESET}"; break_end ;;
            3) lxc start --all; echo -e "${GREEN}已启动所有小鸡${RESET}"; break_end ;;
            4) read -p $'\033[1;35m请输入要暂停的小鸡名字: \033[0m' name; lxc stop "$name"; echo -e "${GREEN}${name} 已暂停${RESET}"; break_end ;;
            5) read -p $'\033[1;35m请输入要启动的小鸡名字: \033[0m' name; lxc start "$name"; echo -e "${GREEN}${name} 已启动${RESET}"; break_end ;;
            6) read -p $'\033[1;35m请输入要重装的小鸡名字: \033[0m' name; lxc stop "$name" && lxc rebuild images:debian/11 "$name"; lxc start "$name"; echo -e "${GREEN}${name} 已重装系统完成${RESET}"; break_end ;;
            7) batch_create_lxc ;;
            8)
                read -p $'\033[1;35m确定新增 LXC 小鸡吗? [y/n]: \033[0m' confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    install_pkg screen wget sudo dos2unix jq
                    curl -L https://github.com/oneclickvirt/lxd/raw/main/scripts/add_more.sh -o add_more.sh
                    chmod +x add_more.sh
                    screen -S lxc_add bash add_more.sh
                    echo -e "${GREEN}任务已启动在 screen 中，运行: screen -r lxc_add 查看进度${RESET}"
                    break_end
                else
                    echo -e "${YELLOW}已取消${RESET}"
                    break_end
                fi
            ;;
            9) read -p $'\033[1;35m请输入要删除的小鸡名字: \033[0m' name; lxc delete -f "$name"; echo -e "${GREEN}${name} 已删除${RESET}"; break_end ;;
            10)
                read -p $'\033[1;35m删除后无法恢复，确定删除所有 LXC 小鸡吗 [y/n]: \033[0m' confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    lxc list -c n --format csv | xargs -I {} lxc delete -f {}
                    rm -f /root/{ssh_sh.sh,config.sh,ssh_bash.sh,buildone.sh,add_more.sh,build_ipv6_network.sh}
                    echo -e "${GREEN}已删除所有 LXC 小鸡及相关脚本${RESET}"
                else
                    echo -e "${YELLOW}已取消${RESET}"
                fi
                break_end
            ;;
            0) break ;;
            *) echo -e "${RED}无效选择，请输入 0~10${RESET}"; break_end ;;
        esac
    done
}

# ================== 主菜单 ==================
main_menu() {
    while true; do
        clear
        echo -e "${PURPLE}▶ LXD + LXC 菜单管理${RESET}"
        echo "------------------------"
        echo -e "${CYAN}1. 环境检测${RESET}"
        echo -e "${CYAN}2. 安装 LXD 主体${RESET}"
        echo -e "${CYAN}3. 管理 LXC 小鸡${RESET}"
        echo -e "${WHITE}0. 退出${RESET}"
        echo "------------------------"
        read -p $'\033[1;91m请输入你的选择: \033[0m' menu

        case $menu in
            1) pre_check ;;
            2) install_lxd ;;
            3) manage_lxc ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选择，请输入 0~3${RESET}"; break_end ;;
        esac
    done
}

# ================== 脚本入口 ==================
main_menu
