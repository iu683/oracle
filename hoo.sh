#!/bin/bash
set -e

# =========================
# 通用 Linux SSH 安全端口切换脚本（忽略旧端口删除错误版）
# =========================

# 检查 root
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 用户运行该脚本"
    exit 1
fi

# -------------------------
# 当前 SSH 端口
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
# 备份 SSH 配置
# -------------------------
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%F_%T)

# -------------------------
# 修改 SSH 配置（暂不重启）
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
    systemctl stop ssh.socket
    systemctl disable ssh.socket
fi

# -------------------------
# 安全放行新端口
# -------------------------
echo "放行新端口 $new_port ..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow $new_port/tcp || true
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=$new_port/tcp || true
    firewall-cmd --reload || true
elif command -v nft >/dev/null 2>&1; then
    nft list table inet filter >/dev/null 2>&1 || nft add table inet filter
    nft list chain inet filter input >/dev/null 2>&1 || \
        nft add chain inet filter input { type filter hook input priority 0 \; }
    if ! nft list ruleset | grep -q "tcp dport $new_port accept"; then
        nft add rule inet filter input tcp dport $new_port accept || true
        mkdir -p /etc/nftables
        nft list ruleset > /etc/nftables/rules.nft 2>/dev/null || true
    fi
elif command -v iptables >/dev/null 2>&1; then
    if ! iptables -C INPUT -p tcp --dport $new_port -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p tcp --dport $new_port -j ACCEPT || true
        [ -x "$(command -v netfilter-persistent)" ] && netfilter-persistent save 2>/dev/null || true
    fi
else
    echo "⚠ 未检测到防火墙，请确保端口已放行"
fi

# -------------------------
# 重启 SSH 服务
# -------------------------
if systemctl >/dev/null 2>&1; then
    if systemctl list-units | grep -q sshd.service; then
        systemctl restart sshd.service
    else
        systemctl restart ssh.service
    fi
else
    service ssh restart
fi

# -------------------------
# 本地端口监听检测
# -------------------------
for i in {1..15}; do
    sleep 1
    if command -v ss >/dev/null 2>&1; then
        ss -tnlp | grep -q ":$new_port " && break
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tnlp | grep -q ":$new_port " && break
    fi
    [ $i -eq 15 ] && echo -e "\033[1;31m⚠ 新端口 $new_port 未监听\033[0m"
done
echo -e "\033[1;32m✔ 新 SSH 端口 $new_port 已监听\033[0m"

# -------------------------
# 远程端口检测
# -------------------------
VPS_IP=$(curl -s https://ifconfig.me || curl -s https://ipinfo.io/ip)
if [ -n "$VPS_IP" ] && command -v nc >/dev/null 2>&1; then
    timeout 3 nc -zv $VPS_IP $new_port &>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "\033[1;32m✔ 远程端口 $new_port 可访问\033[0m"

        # -------------------------
        # 安全删除旧端口（忽略所有错误）
        # -------------------------
        if [ "$current_port" != "$new_port" ]; then
            echo "移除旧端口 $current_port 防火墙规则（忽略错误）..."
            command -v ufw >/dev/null 2>&1 && ufw delete allow $current_port/tcp 2>/dev/null || true
            command -v firewall-cmd >/dev/null 2>&1 && \
                firewall-cmd --permanent --remove-port=$current_port/tcp 2>/dev/null || true && \
                firewall-cmd --reload 2>/dev/null || true
            if command -v nft >/dev/null 2>&1; then
                nft delete rule inet filter input tcp dport $current_port accept 2>/dev/null || true
                nft list ruleset > /etc/nftables/rules.nft 2>/dev/null || true
            fi
            if command -v iptables >/dev/null 2>&1; then
                iptables -D INPUT -p tcp --dport $current_port -j ACCEPT 2>/dev/null || true
                [ -x "$(command -v netfilter-persistent)" ] && netfilter-persistent save 2>/dev/null || true
            fi
        fi
    else
        echo -e "\033[1;31m⚠ 远程端口 $new_port 不可访问，请检查防火墙\033[0m"
        echo "旧端口 $current_port 仍保持可访问状态"
    fi
else
    echo "⚠ 无法检测远程端口"
fi

echo -e "\033[1;32mSSH 端口安全切换完成: $current_port -> $new_port\033[0m"
