#!/bin/bash
set -e

# ================== 颜色 ==================
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# ================== 变量 ==================
SNELL_DIR="/etc/snell"
SNELL_BIN="$SNELL_DIR/snell-server"
SNELL_CONFIG="$SNELL_DIR/snell-server.conf"
SNELL_SERVICE="/etc/systemd/system/snell.service"
LOG_FILE="/var/log/snell_manager.log"

# ================== 工具函数 ==================
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"; }
pause() { read -n 1 -s -r -p "按任意键返回菜单..."; echo; }
random_key() { tr -dc A-Za-z0-9 </dev/urandom | head -c 16; }
get_host_ip() {
    curl -s https://api64.ipify.org || curl -s https://api.ipify.org || echo "127.0.0.1"
}
get_system_dns() {
    dns=$(grep -E "^nameserver" /etc/resolv.conf | awk '{print $2}' | paste -sd ',' -)
    echo "${dns:-1.1.1.1,8.8.8.8}"
}
create_user() { id -u snell &>/dev/null || useradd -r -s /usr/sbin/nologin snell; }

# ================== 安装 / 配置 ==================
install_snell() {
    echo -e "${GREEN}[信息] 开始安装 Snell...${RESET}"
    create_user
    mkdir -p "$SNELL_DIR" && cd "$SNELL_DIR"

    ARCH=$(uname -m)
    VERSION="v5.0.0"
    [[ "$ARCH" == "aarch64" ]] && URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-aarch64.zip" || \
        URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-amd64.zip"

    echo -e "${GREEN}[信息] 下载 Snell...${RESET}"
    wget -O snell.zip "$URL"

    echo -e "${GREEN}[信息] 解压 Snell...${RESET}"
    unzip -o snell.zip >/dev/null
    chmod +x "$SNELL_BIN"
    rm -f snell.zip

    configure_snell
    create_service
    start_service
    echo -e "${GREEN}[完成] Snell 安装并启动成功${RESET}"
    pause
}

configure_snell() {
    echo -e "${GREEN}[信息] 配置 Snell...${RESET}"
    mkdir -p "$SNELL_DIR"

    read -p "$(echo -e ${YELLOW}请输入 Snell Server 端口[1-65535] ${GREEN}(默认:2345)${YELLOW}: ${RESET})" PORT
    PORT=${PORT:-2345}
    read -p "$(echo -e ${YELLOW}请输入 Snell 密钥 ${GREEN}(默认:随机生成)${YELLOW}: ${RESET})" PSK
    PSK=${PSK:-$(random_key)}

    echo -e "${YELLOW}配置 OBFS：[注意] 无特殊作用不建议启用${RESET}"
    echo -e "${YELLOW}1. TLS   2. HTTP   3. 关闭${RESET}"
    read -p "$(echo -e ${GREEN}(默认:3)${YELLOW}: ${RESET})" OBFS
    case $OBFS in 1) OBFS="tls";; 2) OBFS="http";; *) OBFS="off";; esac

    echo -e "${YELLOW}是否开启 IPv6 解析？${RESET}"
    echo -e "${YELLOW}1. 开启   2. 关闭${RESET}"
    read -p "$(echo -e ${GREEN}(默认:2)${YELLOW}: ${RESET})" IPV6
    IPV6=${IPV6:-2}; IPV6=$([ "$IPV6" = "1" ] && echo true || echo false)

    echo -e "${YELLOW}是否开启 TCP Fast Open？${RESET}"
    echo -e "${YELLOW}1. 开启   2. 关闭${RESET}"
    read -p "$(echo -e ${GREEN}(默认:1)${YELLOW}: ${RESET})" TFO
    TFO=${TFO:-1}; TFO=$([ "$TFO" = "1" ] && echo true || echo false)

    DEFAULT_DNS=$(get_system_dns)
    read -p "$(echo -e ${YELLOW}请输入 DNS ${GREEN}(默认:${DEFAULT_DNS})${YELLOW}: ${RESET})" DNS
    DNS=${DNS:-$DEFAULT_DNS}

    cat > "$SNELL_CONFIG" <<EOF
[snell-server]
listen = 0.0.0.0:$PORT
psk = $PSK
obfs = $OBFS
ipv6 = $IPV6
tfo = $TFO
dns = $DNS
EOF

    HOST_IP=$(get_host_ip)
    cat > "$SNELL_DIR/config.txt" <<EOF
iu = snell, $HOST_IP, $PORT, psk=$PSK, version=5, tfo=$TFO, reuse=true, ecn=true
EOF

    echo -e "${GREEN}[完成] 配置已写入 $SNELL_CONFIG${RESET}"
}

create_service() {
    cat > "$SNELL_SERVICE" <<EOF
[Unit]
Description=Snell Server
After=network.target

[Service]
ExecStart=$SNELL_BIN -c $SNELL_CONFIG
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
}

start_service() { systemctl start snell && echo -e "${GREEN}Snell 已启动${RESET}"; log "启动 Snell"; pause; }
stop_service() { systemctl stop snell && echo -e "${GREEN}Snell 已停止${RESET}"; log "停止 Snell"; pause; }
restart_service() { systemctl restart snell && echo -e "${GREEN}Snell 已重启${RESET}"; log "重启 Snell"; pause; }
view_log() { journalctl -u snell -n 20 --no-pager; pause; }
view_config() { cat "$SNELL_CONFIG" || echo -e "${RED}配置文件不存在${RESET}"; pause; }

uninstall_snell() {
    stop_service || true
    systemctl disable snell || true
    rm -f "$SNELL_SERVICE"
    rm -rf "$SNELL_DIR"
    systemctl daemon-reload
    echo -e "${GREEN}Snell 已卸载${RESET}"
    log "卸载 Snell"
    pause
}

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
    echo -e "${GREEN}9. 查看配置${RESET}"
    echo -e "${GREEN}0. 退出${RESET}"
    read -p "请输入选项: " choice
}

main() {
    [ "$(id -u)" != "0" ] && echo -e "${RED}请使用 root 用户运行${RESET}" && exit 1
    while true; do
        show_menu
        case $choice in
            1) install_snell ;;
            2) update_snell ;;
            3) uninstall_snell ;;
            4) configure_snell ;;
            5) start_service ;;
            6) stop_service ;;
            7) restart_service ;;
            8) view_log ;;
            9) view_config ;;
            0) exit ;;
            *) echo -e "${RED}无效选项${RESET}"; pause ;;
        esac
    done
}

main
