#!/bin/bash

# -----------------------------
# 检查 root 权限
# -----------------------------
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[1;31m请以 root 权限运行脚本\033[0m"
    exit 1
fi

# -----------------------------
# 去掉 #Port 的注释
# -----------------------------
sed -i 's/^#Port/Port/' /etc/ssh/sshd_config

# -----------------------------
# 读取当前 SSH 端口
# -----------------------------
current_port=$(grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}')
echo "当前的 SSH 端口号是: $current_port"
echo "------------------------"

# -----------------------------
# 输入新的端口号
# -----------------------------
read -p $'\033[1;35m请输入新的 SSH 端口号: \033[0m' new_port

# -----------------------------
# 检查输入合法性
# -----------------------------
if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -le 0 ] || [ "$new_port" -gt 65535 ]; then
    echo -e "\033[1;31m错误: 请输入 1-65535 的合法端口号\033[0m"
    exit 1
fi

# -----------------------------
# 备份配置
# -----------------------------
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# -----------------------------
# 修改配置
# -----------------------------
sed -i "s/^Port [0-9]\+/Port $new_port/" /etc/ssh/sshd_config

# -----------------------------
# 放行新端口（智能检测防火墙）
# -----------------------------
if command -v ufw >/dev/null 2>&1; then
    echo -e "\033[1;34m检测到 ufw，正在放行端口 $new_port...\033[0m"
    ufw allow $new_port/tcp
elif command -v firewall-cmd >/dev/null 2>&1; then
    echo -e "\033[1;34m检测到 firewalld，正在放行端口 $new_port...\033[0m"
    firewall-cmd --permanent --add-port=$new_port/tcp
    firewall-cmd --reload
elif command -v nft >/dev/null 2>&1; then
    echo -e "\033[1;34m检测到 nftables，正在放行端口 $new_port...\033[0m"
    # 检查 nftables 是否已有 input 表
    if ! nft list tables | grep -q inet; then
        nft add table inet filter
        nft add chain inet filter input { type filter hook input priority 0 \; }
        nft add chain inet filter forward { type filter hook forward priority 0 \; }
        nft add chain inet filter output { type filter hook output priority 0 \; }
    fi
    # 添加端口规则，如果已有规则则跳过
    if ! nft list ruleset | grep -q "tcp dport $new_port accept"; then
        nft add rule inet filter input tcp dport $new_port accept
    fi
else
    echo -e "\033[1;33m未检测到防火墙管理命令，请手动放行端口 $new_port\033[0m"
fi

# -----------------------------
# 重启 SSH 服务（兼容多种系统）
# -----------------------------
if systemctl list-unit-files | grep -q sshd.service; then
    systemctl restart sshd
elif systemctl list-unit-files | grep -q ssh.service; then
    systemctl restart ssh
else
    service ssh restart
fi

echo -e "\033[1;32mSSH 端口已修改为: $new_port\033[0m"
