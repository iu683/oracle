#!/bin/bash

# =========================
# SSH 端口修改最终版脚本（含远程检测）
# =========================

# -------------------------
# 读取当前端口
# -------------------------
current_port=$(grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}')
current_port=${current_port:-22}
echo "当前的 SSH 端口号是: $current_port"
echo "------------------------"

# -------------------------
# 输入新端口
# -------------------------
read -p $'\033[1;35m请输入新的 SSH 端口号: \033[0m' new_port

# 检查端口合法性
if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -le 0 ] || [ "$new_port" -gt 65535 ]; then
    echo -e "\033[1;31m错误: 请输入 1-65535 的合法端口号\033[0m"
    exit 1
fi

# -------------------------
# 备份配置
# -------------------------
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%F_%T)

# -------------------------
# 修改主配置文件端口
# -------------------------
sed -i "s/^Port [0-9]\+/Port $new_port/" /etc/ssh/sshd_config

# -------------------------
# 禁用 systemd socket 激活
# -------------------------
if systemctl is-enabled ssh.socket >/dev/null 2>&1; then
    echo "禁用 ssh.socket 避免覆盖端口..."
    sudo systemctl stop ssh.socket
    sudo systemctl disable ssh.socket
fi

# -------------------------
# 放行新端口（兼容防火墙）
# -------------------------
if command -v ufw >/dev/null 2>&1; then
    ufw allow $new_port/tcp
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=$new_port/tcp
    firewall-cmd --reload
elif command -v iptables >/dev/null 2>&1; then
    if ! iptables -C INPUT -p tcp --dport $new_port -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p tcp --dport $new_port -j ACCEPT
        [ -x "$(command -v netfilter-persistent)" ] && netfilter-persistent save
    fi
elif command -v nft >/dev/null 2>&1; then
    if ! nft list ruleset | grep -q "tcp dport $new_port accept"; then
        nft add rule inet filter input tcp dport $new_port accept
        nft list ruleset > /etc/nftables.conf
    fi
else
    echo "⚠️ 未检测到已安装防火墙，端口可能未放行，请手动检查"
fi

# -------------------------
# 重启 SSH 服务
# -------------------------
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sshd 2>/dev/null || systemctl restart ssh
else
    service ssh restart
fi

echo -e "\033[1;32mSSH 端口已修改为: $new_port\033[0m"

# -------------------------
# 安装 ss/netstat/nc
# -------------------------
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

if ! command -v nc >/dev/null 2>&1; then
    echo "安装 nc (netcat)..."
    if command -v apt >/dev/null 2>&1; then
        apt update && apt install -y netcat
    elif command -v yum >/dev/null 2>&1; then
        yum install -y nc
    fi
fi

# -------------------------
# 检测本地端口是否监听
# -------------------------
echo "检测新端口 $new_port 是否已启动..."
for i in {1..10}; do
    sleep 1
    if command -v ss >/dev/null 2>&1; then
        ss -tnlp | grep -q ":$new_port " && echo -e "\033[1;32m✔ 新 SSH 端口 $new_port 正常监听\033[0m" && break
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tnlp | grep -q ":$new_port " && echo -e "\033[1;32m✔ 新 SSH 端口 $new_port 正常监听\033[0m" && break
    fi
    [ $i -eq 10 ] && echo -e "\033[1;31m⚠ SSH 端口 $new_port 没有监听，请检查配置\033[0m"
done

# -------------------------
# 测试远程端口可达性
# -------------------------
echo "检测远程端口 $new_port 是否可达..."
VPS_IP=$(curl -s https://ifconfig.me)   # 获取公网 IP
if [ -z "$VPS_IP" ]; then
    echo "⚠ 无法获取公网 IP，跳过远程检测"
else
    if command -v nc >/dev/null 2>&1; then
        timeout 3 nc -zv $VPS_IP $new_port &>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "\033[1;32m✔ 远程端口 $new_port 可访问\033[0m"
        else
            echo -e "\033[1;31m⚠ 远程端口 $new_port 无法访问，请检查 VPS 网络策略或安全组\033[0m"
        fi
    else
        echo "⚠ nc 不可用，无法测试远程端口"
    fi
fi
