#!/bin/bash
set -e

# ===============================
# 一键修改主机名脚本（立即生效 + SSH 提示符持久化）
# 支持 Debian / Ubuntu / CentOS / Rocky / AlmaLinux / Amazon Linux / Alpine
# ===============================

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
    "alpine" | "debian" | "ubuntu" | "centos" | "fedora" | "rocky" | "amzn" | "almalinux")
        # 写入 /etc/hostname
        echo "$new_hostname" > /etc/hostname

        # 刷新当前 shell 主机名
        hostname "$new_hostname"
        export HOSTNAME="$new_hostname"

        # 修改 /etc/hosts
        if grep -q "$current_hostname" /etc/hosts; then
            sed -i "s/$current_hostname/$new_hostname/g" /etc/hosts
        else
            echo "127.0.0.1   $new_hostname" >> /etc/hosts
        fi
        ;;
    *)
        echo -e "${RED}不支持的系统类型: ${ID}${RESET}"
        exit 1
        ;;
esac

# 更新当前 shell 提示符
PS1="\u@${new_hostname}:\w\$ "

# 持久化提示符到 root 用户 .bashrc
BASHRC_FILE="/root/.bashrc"
if ! grep -q "PS1=.*@${new_hostname}" "$BASHRC_FILE"; then
    echo "export PS1='\\u@${new_hostname}:\\w\\$ '" >> "$BASHRC_FILE"
fi

echo -e "${GREEN}✅ 主机名已更改为: ${YELLOW}${new_hostname}${RESET}"
echo -e "${YELLOW}当前 shell 已刷新，新的主机名立即生效${RESET}"
echo -e "${YELLOW}重启或新开终端后，提示符将显示新主机名${RESET}"
