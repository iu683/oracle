#!/bin/bash
set -e

# ================== 颜色 ==================
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

SNELL_DIR="/etc/snell"
SNELL_CONFIG="$SNELL_DIR/snell-server.conf"
SNELL_SERVICE="/etc/systemd/system/snell.service"

# ================== 工具函数 ==================
random_key() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

random_port() {
    shuf -i 2000-65000 -n 1
}

get_system_dns() {
    if command -v systemd-resolve >/dev/null 2>&1; then
        systemd-resolve --status 2>/dev/null | grep 'DNS Servers' | awk '{print $3}' | paste -sd "," -
    elif command -v resolvectl >/dev/null 2>&1; then
        resolvectl status 2>/dev/null | grep 'DNS Servers' | awk '{print $3}' | paste -sd "," -
    else
        grep -E "^nameserver" /etc/resolv.conf | awk '{print $2}' | paste -sd "," -
    fi
}

pause() {
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# ================== Snell 安装 ==================
install_snell() {
    echo -e "${GREEN}[信息] 开始安装 Snell...${RESET}"

    mkdir -p $SNELL_DIR
    cd $SNELL_DIR

    # 下载 Snell 官方稳定版本
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

    # 写入配置
    configure_snell

    # 写入 systemd 服务
    cat > $SNELL_SERVICE <<EOF
[Unit]
Description=Snell Server
After=network.target

[Service]
ExecStart=$SNELL_DIR/snell-server -c $SNELL_CONFIG
Restart=on-failure
User=nobody
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
}

# ================== Snell 卸载 ==================
uninstall_snell() {
    echo -e "${RED}[警告] 即将卸载 Snell...${RESET}"
    systemctl stop snell || true
    systemctl disable snell || true
    rm -f $SNELL_SERVICE
    rm -rf $SNELL_DIR
    systemctl daemon-reload
    echo -e "${GREEN}[完成] Snell 已卸载${RESET}"
}

# ================== Snell 更新 ==================
update_snell() {
    echo -e "${GREEN}[信息] 正在更新 Snell...${RESET}"
    systemctl stop snell || true

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

    systemctl start snell
    echo -e "${GREEN}[完成] Snell 已更新${RESET}"
}

# ================== Snell 配置 ==================
configure_snell() {
    echo -e "${GREEN}[信息] 配置 Snell...${RESET}"

    # 端口
    read -p "请输入 Snell Server 端口[1-65535] (默认: 2345): " port
    port=${port:-2345}
    echo -e "${GREEN}端口: $port${RESET}"

    # 密钥
    read -p "请输入 Snell Server 密钥 (默认: 随机生成): " key
    key=${key:-$(random_key)}
    echo -e "${GREEN}密钥: $key${RESET}"

    # OBFS
    echo -e "配置 OBFS：[注意] 无特殊作用不建议启用"
    echo -e "1. TLS   2. HTTP   3. 关闭"
    read -p "(默认: 3): " obfs
    case $obfs in
        1) obfs="tls" ;;
        2) obfs="http" ;;
        *) obfs="off" ;;
    esac
    echo -e "${GREEN}OBFS 状态: $obfs${RESET}"

    # IPv6
    echo -e "是否开启 IPv6 解析？"
    echo -e "1. 开启   2. 关闭"
    read -p "(默认: 2): " ipv6
    ipv6=${ipv6:-2}
    ipv6=$([ "$ipv6" = "1" ] && echo true || echo false)
    echo -e "${GREEN}IPv6 解析: $ipv6${RESET}"

    # TCP Fast Open
    echo -e "是否开启 TCP Fast Open？"
    echo -e "1. 开启   2. 关闭"
    read -p "(默认: 1): " tfo
    tfo=${tfo:-1}
    tfo=$([ "$tfo" = "1" ] && echo true || echo false)
    echo -e "${GREEN}TCP Fast Open: $tfo${RESET}"

    # DNS
    default_dns=$(get_system_dns)
    [[ -z "$default_dns" ]] && default_dns="1.1.1.1,8.8.8.8"
    read -p "请输入 DNS (默认: $default_dns): " dns
    dns=${dns:-$default_dns}
    echo -e "${GREEN}当前 DNS: $dns${RESET}"

    # 写入配置文件
    cat > $SNELL_CONFIG <<EOF
[snell-server]
listen = 0.0.0.0:$port
psk = $key
obfs = $obfs
ipv6 = $ipv6
tfo = $tfo
dns = $dns
EOF

    # 写入 config.txt 示例
    HOST_IP=$(curl -s https://api64.ipify.org || curl -s https://ifconfig.me || curl -s https://ipinfo.io/ip)
    IP_COUNTRY=$(curl -s http://ipinfo.io/${HOST_IP}/country)
    cat << EOF > $SNELL_DIR/config.txt
${IP_COUNTRY} = snell, ${HOST_IP}, ${port}, psk = ${key}, version = 5, reuse = true
EOF

    echo -e "${GREEN}[完成] 配置已写入 $SNELL_CONFIG${RESET}"
}

# ================== 菜单 ==================
show_menu() {
    clear
    echo -e "${GREEN}====== Snell 管理脚本 ======${RESET}"
    echo -e "1. 安装 Snell"
    echo -e "2. 更新 Snell"
    echo -e "3. 卸载 Snell"
    echo -e "4. 修改配置"
    echo -e "5. 启动 Snell"
    echo -e "6. 停止 Snell"
    echo -e "7. 重启 Snell"
    echo -e "8. 查看日志"
    echo -e "0. 退出"
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
        5) systemctl start snell; echo -e "${GREEN}Snell 已启动${RESET}"; pause ;;
        6) systemctl stop snell; echo -e "${RED}Snell 已停止${RESET}"; pause ;;
        7) systemctl restart snell; echo -e "${GREEN}Snell 已重启${RESET}"; pause ;;
        8) journalctl -u snell -e --no-pager; pause ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效输入${RESET}"; pause ;;
    esac
done
