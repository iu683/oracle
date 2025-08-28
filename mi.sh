#!/bin/bash

# ===============================
# SSH 管理菜单脚本
# ===============================

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

SSH_CONF="/etc/ssh/sshd_config"

# ===============================
# 函数：配置密钥登录
# ===============================
setup_ssh_key() {
    echo -e "${YELLOW}Step 1: 生成 SSH 密钥并配置公钥登录${RESET}"
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    read -p "请输入密钥保存路径（默认 /root/.ssh/id_ed25519）: " keypath
    keypath=${keypath:-/root/.ssh/id_ed25519}

    ssh-keygen -t ed25519 -f "$keypath"

    cat "${keypath}.pub" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys

    sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/g' "$SSH_CONF"

    echo -e "${GREEN}密钥登录配置完成${RESET}"
    echo "公钥路径: ${keypath}.pub"
    echo "私钥路径: ${keypath}"
}

# ===============================
# 函数：禁用 root 密码登录
# ===============================
disable_root_password() {
    SSH_CONF="/etc/ssh/sshd_config"

    echo -e "${YELLOW}Step 2: 禁用 root 密码登录${RESET}"

    # 备份配置文件
    cp "$SSH_CONF" "${SSH_CONF}.bak_$(date +%F_%T)"

    # 禁用 root 密码登录
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/g' "$SSH_CONF"
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/g' "$SSH_CONF"

    # 重启 SSH 服务
    systemctl restart sshd

    echo -e "${GREEN}root 密码登录已禁用，并已重启 SSH 服务${RESET}"
}

# ===============================
# 函数：重启 SSH 服务
# ===============================
restart_ssh() {
    echo -e "${YELLOW}Step 3: 重启 SSH 服务${RESET}"

    if systemctl status sshd &>/dev/null; then
        systemctl restart sshd
    elif systemctl status ssh &>/dev/null; then
        systemctl restart ssh
    else
        service sshd restart
    fi

    echo -e "${GREEN}SSH 服务已重启，操作完成！${RESET}"
}

# ===============================
# 菜单循环
# ===============================
while true; do
    echo -e "\n${YELLOW}========== SSH 管理菜单 ==========${RESET}"
    echo -e "${GREEN}1) 配置 SSH 密钥登录${RESET}"
    echo -e "${GREEN}2) 禁用 root 密码登录${RESET}"
    echo -e "${GREEN}3) 重启 SSH 服务${RESET}"
    echo -e "${RED}0) 退出${RESET}"
    read -p "$(echo -e ${YELLOW}请选择操作 [0-3]:${RESET}) " choice

    case $choice in
        1) setup_ssh_key ;;
        2) disable_root_password ;;
        3) restart_ssh ;;
        0) echo "退出脚本"; break ;;
        *) echo -e "${RED}无效选择，请重新输入${RESET}" ;;
    esac
done
