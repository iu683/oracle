#!/bin/bash
set -e

# =========================
# Debian 12 完全兼容 SSH 端口修改脚本
# =========================

# -------------------------
# 获取当前 SSH 端口
# -------------------------
current_port=$(grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}')
current_port=${current_port:-22}
echo -e "\033[1;36m当前 SSH 端口: $current_port\033[0m"
echo "------------------------"

# -------------------------
# 输入新端口
# -------------------------
read -p $'\033[1;35m请输入新的 SSH 端口号: \033[0m' new_port

# 检查合法性
if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -le 0 ] || [ "$new_port" -gt 65535 ]; then
    echo -e "\033[1;31m错误: 请输入 1-65535 的端口号\033[0m"
    exit 1
fi

# -------------------------
# 备份配置
# -------------------------
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%F_%T)

# -------------------------
# 修改端口配置
# -------------------------
if grep -q "^Port " /etc/ssh/sshd_config; then
    sed -i "s/^Port .*/Port $new_port/" /etc/ssh/sshd_config
else
    echo "Port $new_port" >> /etc/ssh/sshd_config
fi

# -------------------------
# 停用 systemd socket
# -------------------------
if systemctl list-unit-files | grep -q ssh.socket; then
    echo "禁用 ssh.socket..."
    systemctl stop ssh.socket
    systemctl disable ssh.socket
fi

# -------------------------
# 放行新端口
# -------------------------
echo "配置防火墙放行端口 $new_port ..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow $new_port/tcp
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=$new_port/tcp
    firewall-cmd --reload
elif command -v nft >/dev/null 2>&1; then
    # 确保表和链存在
    nft list table inet filter >/dev/null 2>&1 || nft add table inet filter
    nft list chain inet filter input >/dev/null 2>&1 || \
        nft add chain inet filter input { type filter hook input priority 0 \; }
    
    # 添加规则
    if ! nft list ruleset | grep -q "tcp dport $new_port accept"; then
        nft add rule inet filter input tcp dport $new_port accept
        mkdir -p /etc/nftables
        nft list ruleset > /etc/nftables/rules.nft
    fi
elif command -v iptables >/dev/null 2>&1; then
    if ! iptables -C INPUT -p tcp --dport $new_port -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p tcp --dport $new_port -j ACCEPT
        [ -x "$(command -v netfilter-persistent)" ] && netfilter-persistent save
    fi
else
    echo "⚠ 未检测到防火墙，请确保端口已放行"
fi

# -------------------------
# 重启 SSH 服务
# -------------------------
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sshd.service
else
    service ssh restart
fi
echo -e "\033[1;32mSSH 端口已修改为 $new_port\033[0m"

# -------------------------
# 安装检测工具
# -------------------------
for pkg in iproute2 net-tools netcat; do
    cmd=$(basename $pkg)
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "安装 $cmd ..."
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y $pkg
        elif command -v yum >/dev/null 2>&1; then
            yum install -y $pkg
        fi
    fi
done

# -------------------------
# 本地端口监听检测
# -------------------------
echo "检测本地端口 $new_port 是否启动..."
for i in {1..15}; do
    sleep 1
    if command -v ss >/dev/null 2>&1; then
        ss -tnlp | grep -q ":$new_port " && echo -e "\033[1;32m✔ 新端口 $new_port 已监听\033[0m" && break
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tnlp | grep -q ":$new_port " && echo -e "\033[1;32m✔ 新端口 $new_port 已监听\033[0m" && break
    fi
    [ $i -eq 15 ] && echo -e "\033[1;31m⚠ 端口 $new_port 未监听，请检查 SSH 配置\033[0m"
done

# -------------------------
# 远程端口可达性检测
# -------------------------
VPS_IP=$(curl -s https://ifconfig.me || curl -s https://ipinfo.io/ip)
if [ -n "$VPS_IP" ] && command -v nc >/dev/null 2>&1; then
    echo "检测远程端口 $new_port ..."
    timeout 3 nc -zv $VPS_IP $new_port &>/dev/null && echo -e "\033[1;32m✔ 远程端口 $new_port 可访问\033[0m" || echo -e "\033[1;31m⚠ 远程端口 $new_port 不可访问\033[0m"
else
    echo "⚠ 无法检测远程端口"
fi
