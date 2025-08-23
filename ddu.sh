#!/bin/bash
set -e

# ================== 颜色 ==================
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# ================== 变量 ==================
SNELL_DIR="/etc/snell"
SNELL_CONFIG="$SNELL_DIR/snell-server.conf"
SNELL_SERVICE="/etc/systemd/system/snell.service"
LOG_FILE="/var/log/snell_manager.log"

# ================== 工具函数 ==================
create_user() {
    id -u snell &>/dev/null || useradd -r -s /usr/sbin/nologin snell
}

random_key() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

random_port() {
    shuf -i 2000-65000 -n 1
}

get_system_dns() {
    grep -E "^nameserver" /etc/resolv.conf | awk '{print $2}' | paste -sd "," -
}

pause() {
    read -n 1 -s -r -p "按任意键返回菜单..."
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# ================== 配置 Snell ==================
configure_snell() {
    echo -e "${GREEN}\n[信息] 开始配置 Snell...${RESET}"
    mkdir -p $SNELL_DIR

    read -p "请输入 Snell Server 端口[1-65535] (默认: 2345): " port
    port=${port:-2345}

    read -p "请输入 Snell Server 密钥 (默认: 随机生成): " key
    key=${key:-$(random_key)}

    echo -e "${YELLOW}\n配置 OBFS：[注意] 无特殊作用不建议启用${RESET}"
    echo "1. TLS   2. HTTP   3. 关闭"
    read -p "(默认: 3): " obfs
    case $obfs in
        1) obfs="tls" ;;
        2) obfs="http" ;;
        *) obfs="off" ;;
    esac

    echo -e "${YELLOW}\n是否开启 IPv6 解析？${RESET}"
    echo "1. 开启   2. 关闭"
    read -p "(默认: 2): " ipv6
    ipv6=${ipv6:-2}
    ipv6=$([ "$ipv6" = "1" ] && echo true || echo false)

    echo -e "${YELLOW}\n是否开启 TCP Fast Open？${RESET}"
    echo "1. 开启   2. 关闭"
    read -p "(默认: 1): " tfo
    tfo=${tfo:-1}
    tfo=$([ "$tfo" = "1" ] && echo true || echo false)

    default_dns=$(get_system_dns)
    [[ -z "$default_dns" ]] && default_dns="1.1.1.1,8.8.8.8"
    read -p "请输入 DNS (默认: $default_dns): " dns
    dns=${dns:-$default_dns}

    cat > $SNELL_CONFIG <<EOF
[snell-server]
listen = 0.0.0.0:$port
psk = $key
obfs = $obfs
ipv6 = $ipv6
tfo = $tfo
dns = $dns
EOF

    # 获取公网 IP
    HOST_IP=$(curl -s https://api64.ipify.org || curl -s https://ifconfig.me || curl -s https://ipinfo.io/ip)

    # 写 Surge 示例
    cat <<EOF > $SNELL_DIR/config.txt
iu = snell, $HOST_IP, $port, psk=$key, version=5, tfo=$tfo, reuse=true, ecn=true
EOF

    echo -e "${GREEN}\n[完成] 配置已写入 $SNELL_CONFIG${RESET}"
    echo -e "${GREEN}====== Snell Server 配置信息 ======${RESET}"
    echo -e "${GREEN} IPv4 地址      : $HOST_IP${RESET}"
    echo -e "${GREEN} 端口           : $port${RESET}"
    echo -e "${GREEN} 密钥           : $key${RESET}"
    echo -e "${GREEN} OBFS           : $obfs${RESET}"
    echo -e "${GREEN} IPv6           : $ipv6${RESET}"
    echo -e "${GREEN} TFO            : $tfo${RESET}"
    echo -e "${GREEN} DNS            : $dns${RESET}"
    echo -e "${GREEN} 版本           : 5${RESET}"
    echo -e "${GREEN}---------------------------------${RESET}"
    echo -e "${GREEN}[信息] Surge 配置：${RESET}"
    cat $SNELL_DIR/config.txt
    echo -e "${GREEN}---------------------------------\n${RESET}"
}

# ================== 安装 Snell ==================
install_snell() {
    echo -e "${GREEN}[信息] 开始安装 Snell...${RESET}"
    create_user
    mkdir -p $SNELL_DIR
    cd $SNELL_DIR

    ARCH=$(uname -m)
    VERSION="v5.0.0"
    if [[ "$ARCH" == "aarch64" ]]; then
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-aarch64.zip"
    else
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-amd64.zip"
    fi

    wget -O snell.zip "$SNELL_URL"
    unzip -o snell.zip -d $SNELL_DIR
    rm -f snell.zip
    chmod +x $SNELL_DIR/snell-server

    configure_snell

    # systemd 文件
    cat > $SNELL_SERVICE <<EOF
[Unit]
Description=Snell Server
After=network.target

[Service]
ExecStart=$SNELL_DIR/snell-server -c $SNELL_CONFIG
Restart=on-failure
User=snell
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable snell
    systemctl start snell
    echo -e "${GREEN}[完成] Snell 已安装并启动${RESET}"
    log "Snell 已安装并启动"
}

# ================== 更新 Snell ==================
update_snell() {
    echo -e "${GREEN}[信息] 更新 Snell...${RESET}"
    systemctl stop snell || true
    install_snell
    systemctl restart snell
    echo -e "${GREEN}[完成] Snell 已更新${RESET}"
    log "Snell 已更新"
}

# ================== 卸载 Snell ==================
uninstall_snell() {
    echo -e "${RED}[警告] 卸载 Snell...${RESET}"
    systemctl stop snell || true
    systemctl disable snell || true
    rm -f $SNELL_SERVICE
    rm -rf $SNELL_DIR
    systemctl daemon-reload
    echo -e "${GREEN}[完成] Snell 已卸载${RESET}"
    log "Snell 已卸载"
}

# ================== 菜单 ==================
show_menu() {
    clear
    echo -e "${GREEN}====== Snell 管理脚本 ======${RESET}"
    echo -e "${GREEN}1. 安装 Snell${RESET}"
    echo -e "${GREEN}2. 更新 Snell${RESET}"
    echo -e "${GREEN}3. 卸载 Snell${RESET}"
    echo -e "${GREEN}4. 修改配置${RESET}"
    echo -e "${GREEN}5. 启动 Snell${RESET}"
    echo -e "${GREEN}6. 停止 Snell${RESET}"
    echo -e "${GREEN}7. 重启 Snell${RESET}"
    echo -e "${GREEN}8. 查看日志${RESET}"
    echo -e "${GREEN}9. 查看当前配置${RESET}"
    echo -e "${GREEN}0. 退出${RESET}"
    echo -e "${GREEN}============================${RESET}"
}

# ================== 主循环 ==================
while true; do
    show_menu
    read -p "请输入选项: " choice
    case $choice in
        1) install_snell; pause ;;
        2) update_snell; pause ;;
        3) uninstall_snell; pause ;;
        4) configure_snell; systemctl restart snell; pause ;;
        5) systemctl start snell; echo -e "${GREEN}[完成] Snell 已启动${RESET}"; log "Snell 启动"; pause ;;
        6) systemctl stop snell; echo -e "${GREEN}[完成] Snell 已停止${RESET}"; log "Snell 停止"; pause ;;
        7) systemctl restart snell; echo -e "${GREEN}[完成] Snell 已重启${RESET}"; log "Snell 重启"; pause ;;
        8) journalctl -u snell -e --no-pager; pause ;;
        9)
            if [ -f "$SNELL_CONFIG" ]; then
                echo -e "${GREEN}====== 当前 Snell 配置 ======${RESET}"
                cat "$SNELL_CONFIG"
                echo -e "${GREEN}====== Surge 配置示例 ======${RESET}"
                cat "$SNELL_DIR/config.txt"
            else
                echo -e "${RED}配置文件不存在${RESET}"
            fi
            pause
            ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效输入${RESET}"; pause ;;
    esac
done
