#!/bin/bash
set -e

# 检查是否 root
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[1;31m请使用 root 权限运行脚本\033[0m"
    exit 1
fi

# 检测系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS=$(uname -s)
fi

# 去掉 #Port 注释
sed -i 's/^#Port/Port/' /etc/ssh/sshd_config

# 读取当前 SSH 端口
current_port=$(grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}')
echo "当前的 SSH 端口号是: $current_port"
echo "------------------------"

# 输入新的端口号
read -p $'\033[1;35m请输入新的 SSH 端口号: \033[0m' new_port

# 检查端口合法性
if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -le 0 ] || [ "$new_port" -gt 65535 ]; then
    echo -e "\033[1;31m错误: 请输入 1-65535 的合法端口号\033[0m"
    exit 1
fi

# 检测端口是否被占用
if ss -tuln | grep -q ":$new_port\b"; then
    echo -e "\033[1;31m错误: 端口 $new_port 已被占用，请选择其他端口\033[0m"
    exit 1
fi

# 备份 SSH 配置
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%F_%T)

# 修改 SSH 配置
sed -i "s/^Port [0-9]\+/Port $new_port/" /etc/ssh/sshd_config

# 放行新端口函数
allow_port() {
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $new_port/tcp
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=$new_port/tcp
        firewall-cmd --reload
    elif command -v iptables >/dev/null 2>&1; then
        iptables -C INPUT -p tcp --dport $new_port -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p tcp --dport $new_port -j ACCEPT
        command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save
    else
        # 自动安装 iptables
        if [[ "$OS" =~ (debian|ubuntu|kali) ]]; then
            apt update && apt install -y iptables
        elif [[ "$OS" =~ (centos|rhel|fedora) ]]; then
            yum install -y iptables-services
        elif [[ "$OS" =~ alpine ]]; then
            apk add iptables
        else
            echo -e "\033[1;33m警告: 未知系统，无法自动安装 iptables，请手动放行端口 $new_port\033[0m"
            return
        fi
        iptables -I INPUT -p tcp --dport $new_port -j ACCEPT
        command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save
    fi
}

# 临时放行新端口以避免断开连接
allow_port

# 重启 SSH 服务
systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null

echo -e "\033[1;32mSSH 端口已修改为: $new_port\033[0m"
echo -e "\033[1;33m请确认防火墙已放行端口 $new_port，否则远程连接可能中断\033[0m"
