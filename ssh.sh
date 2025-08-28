#!/bin/bash

# -----------------------------
# 修改 SSH 端口并检测
# -----------------------------

# 去掉 #Port 的注释
sed -i 's/^\s*#Port/Port/' /etc/ssh/sshd_config

# 读取当前 SSH 端口
current_port=$(grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}')
current_port=${current_port:-22}
echo "当前的 SSH 端口号是: $current_port"
echo "------------------------"

# 输入新的端口号
read -p $'\033[1;35m请输入新的 SSH 端口号: \033[0m' new_port

# 检查输入合法性
if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -le 0 ] || [ "$new_port" -gt 65535 ]; then
    echo -e "\033[1;31m错误: 请输入 1-65535 的合法端口号\033[0m"
    exit 1
fi

# 备份配置
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%F_%T)

# 修改配置
sed -i "s/^Port [0-9]\+/Port $new_port/" /etc/ssh/sshd_config

# -----------------------------
# 放行新端口（兼容防火墙）
# -----------------------------
if command -v ufw >/dev/null 2>&1; then
    ufw allow $new_port/tcp
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=$new_port/tcp
    firewall-cmd --reload
elif command -v iptables >/dev/null 2>&1; then
    iptables -I INPUT -p tcp --dport $new_port -j ACCEPT
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save
    fi
elif command -v nft >/dev/null 2>&1; then
    if ! nft list ruleset | grep -q "tcp dport $new_port accept"; then
        nft add rule inet filter input tcp dport $new_port accept
    fi
    nft list ruleset > /etc/nftables.conf
else
    echo "⚠️ 未检测到已安装的防火墙，端口可能未放行，请手动检查"
fi

# -----------------------------
# 重启 SSH 服务
# -----------------------------
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sshd 2>/dev/null || systemctl restart ssh
else
    service ssh restart
fi

echo -e "\033[1;32mSSH 端口已修改为: $new_port\033[0m"

# -----------------------------
# 检测端口是否监听
# -----------------------------
echo "检测新端口 $new_port 是否已启动..."
sleep 1

# 安装 ss 或 netstat
if ! command -v ss >/dev/null 2>&1; then
    echo "安装 ss..."
    if command -v apt >/dev/null 2>&1; then
        apt update && apt install -y iproute2
    elif command -v yum >/dev/null 2>&1; then
        yum install -y iproute
    fi
fi

if ! command -v ss >/dev/null 2>&1 && ! command -v netstat >/dev/null 2>&1; then
    echo "安装 netstat..."
    if command -v apt >/dev/null 2>&1; then
        apt update && apt install -y net-tools
    elif command -v yum >/dev/null 2>&1; then
        yum install -y net-tools
    fi
fi

# 检测端口
if command -v ss >/dev/null 2>&1; then
    if ss -tnlp | grep -q ":$new_port "; then
        echo -e "\033[1;32m✔ 新 SSH 端口 $new_port 正常监听\033[0m"
    else
        echo -e "\033[1;31m⚠ SSH 端口 $new_port 没有监听，请检查配置\033[0m"
    fi
elif command -v netstat >/dev/null 2>&1; then
    if netstat -tnlp | grep -q ":$new_port "; then
        echo -e "\033[1;32m✔ 新 SSH 端口 $new_port 正常监听\033[0m"
    else
        echo -e "\033[1;31m⚠ SSH 端口 $new_port 没有监听，请检查配置\033[0m"
    fi
else
    echo "无法检测端口状态，请确保 ss/netstat 已安装"
fi
