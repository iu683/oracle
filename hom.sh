#!/bin/bash
set -e

# 颜色
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# 检查 root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行此脚本${RESET}"
    exit 1
fi

# 获取系统信息
if [ -f /etc/os-release ]; then
    source /etc/os-release
else
    echo -e "${RED}无法检测系统版本，退出！${RESET}"
    exit 1
fi

# 当前主机名
current_hostname=$(hostname)
echo -e "${YELLOW}当前系统: ${RED}${PRETTY_NAME}${RESET}"
echo -e "${GREEN}当前主机名: ${YELLOW}${current_hostname}${RESET}"

# 输入新主机名
read -p $'\033[1;35m请输入新的主机名: \033[0m' new_hostname

# 校验输入
if [[ -z "$new_hostname" || "$new_hostname" =~ [[:space:]] ]]; then
    echo -e "${RED}无效的主机名，请输入一个合法的主机名（不能有空格）。${RESET}"
    exit 1
fi

# 修改主机名
case $ID in
    "alpine")
        echo "$new_hostname" > /etc/hostname
        hostname "$new_hostname"
        if ! grep -q "$new_hostname" /etc/hosts; then
            echo "127.0.0.1   $new_hostname" >> /etc/hosts
        fi
        ;;
    "debian" | "ubuntu" | "centos" | "fedora" | "rocky" | "amzn" | "almalinux")
        hostnamectl set-hostname "$new_hostname"
        hostname "$new_hostname"
        export HOSTNAME="$new_hostname"
        if ! grep -q "$new_hostname" /etc/hosts; then
            echo "127.0.0.1   $new_hostname" >> /etc/hosts
        fi
        ;;
    *)
        echo -e "${RED}不支持的系统类型: ${ID}${RESET}"
        exit 1
        ;;
esac

# 刷新 shell 的 hostname 显示
PS1="\u@${new_hostname}:\w\$ "

echo -e "${GREEN}✅ 主机名已更改为: ${YELLOW}${new_hostname}${RESET}"
echo -e "${YELLOW}当前 shell 已刷新，新的主机名立即生效${RESET}"
