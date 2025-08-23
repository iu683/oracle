#!/bin/bash
# ==========================================
# 一键重装系统脚本（密码保持原密码）
# ==========================================

green="\033[32m"
red="\033[31m"
yellow="\033[33m"
purple="\033[1;35m"
re="\033[0m"

# 主菜单函数示例
main_menu() {
    echo -e "${green}返回主菜单${re}"
    # 这里可以调用你原来的菜单函数
    # 比如：./your_menu.sh
    exit 0
}

# 网络检查函数
check_network() {
    echo -e "${yellow}正在检查网络连接...${re}"
    if ! curl -s --head https://raw.githubusercontent.com/LloydAsp/OsMutation/main/OsMutation.sh | head -n 1 | grep "200" >/dev/null; then
        echo -e "${red}网络无法访问 GitHub，请检查网络后重试${re}"
        main_menu
    fi
}

# 重装系统函数
reinstall_os() {
    clear
    echo -e "${green}重装系统将无法恢复数据，请提前做好备份${re}"
    echo -e "${yellow}注意：NAT重装后SSH端口密码保持原端口密码不变${re}"
    echo ""
    
    while true; do
        read -p $'\033[1;35m确定要重装吗？(y/n): \033[0m' confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            check_network
            echo -e "${yellow}正在下载并执行重装脚本...${re}"
            sleep 1
            curl -so OsMutation.sh https://raw.githubusercontent.com/LloydAsp/OsMutation/main/OsMutation.sh
            chmod +x OsMutation.sh
            ./OsMutation.sh
            break
        elif [[ $confirm =~ ^[Nn]$ ]]; then
            echo -e "${green}已取消重装，返回主菜单${re}"
            main_menu
        else
            echo -e "${red}无效输入，请输入 y 或 n${re}"
        fi
    done
}

# 调用重装函数
reinstall_os
