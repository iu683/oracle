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

get_system_dns() {
    grep -E "^nameserver" /etc/resolv.conf | awk '{print $2}' | paste -sd "," -
}

pause() { read -n 1 -s -r -p "按任意键返回菜单..."; }
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"; }

check_port_open() {
    local host_ip=$1
    local port=$2
    echo -e "${GREEN}[信息] 检测端口 $port 是否开放...${RESET}"

    if nc -z -w3 $host_ip $port &>/dev/null; then
        tcp_status="${GREEN}开放${RESET}"
    else
        tcp_status="${RED}未开放${RESET}"
    fi

    if command -v nmap &>/dev/null; then
        udp_result=$(nmap -sU -p $port $host_ip | grep $port | grep open || true)
        if [[ -n "$udp_result" ]]; then
            udp_status="${GREEN}开放${RESET}"
        else
            udp_status="${RED}未开放${RESET}"
        fi
    else
        udp_status="${YELLOW}未检测（未安装 nmap）${RESET}"
    fi

    echo -e "${GREEN}TCP 端口状态: $tcp_status${RESET}"
    echo -e "${GREEN}UDP 端口状态: $udp_status${RESET}"
    echo ""
}

download_snell() {
    local url=$1
    local output=$2
    echo -e "${GREEN}[信息] 开始下载 Snell...${RESET}"
    wget --progress=bar:force:noscroll -O "$output" "$url" 2>&1 | grep --line-buffered "%" | sed -u -e "s,\.,,g"
    echo -e "${GREEN}[完成] 下载完成${RESET}"
}

unzip_snell() {
    local zip_file=$1
    local dest_dir=$2
    echo -e "${GREEN}[信息] 开始解压 Snell...${RESET}"
    unzip -o "$zip_file" -d "$dest_dir" >/dev/null
    echo -e "${GREEN}[完成] 解压完成${RESET}"
}

configure_snell() {
    echo -e "${GREEN}\n[信息] 开始配置 Snell...${RESET}"
    mkdir -p $SNELL_DIR

    read -p "$(echo -e ${YELLOW}请输入 Snell Server 端口[1-65535] ${GREEN}(默认: 2345)${YELLOW}: ${RESET})" port
    port=${port:-2345}

    read -p "$(echo -e ${YELLOW}请输入 Snell Server 密钥 ${GREEN}(默认: 随机生成)${YELLOW}: ${RESET})" key
    key=${key:-$(random_key)}

    echo -e "${YELLOW}\n配置 OBFS：[注意] 无特殊作用不建议启用${RESET}"
    echo -e "${YELLOW}1. TLS   2. HTTP   3. 关闭${RESET}"
    read -p "$(echo -e ${GREEN}(默认: 3)${YELLOW}: ${RESET})" obfs
    case $obfs in
        1) obfs="tls" ;;
        2) obfs="http" ;;
        *) obfs="off" ;;
    esac

    echo -e "${YELLOW}\n是否开启 IPv6 解析？${RESET}"
    echo -e "${YELLOW}1. 开启   2. 关闭${RESET}"
    read -p "$(echo -e ${GREEN}(默认: 2)${YELLOW}: ${RESET})" ipv6
    ipv6=${ipv6:-2}
    ipv6=$([ "$ipv6" = "1" ] && echo true || echo false)

    echo -e "${YELLOW}\n是否开启 TCP Fast Open？${RESET}"
    echo -e "${YELLOW}1. 开启   2. 关闭${RESET}"
    read -p "$(echo -e ${GREEN}(默认: 1)${YELLOW}: ${RESET})" tfo
    tfo=${tfo:-1}
    tfo=$([ "$tfo" = "1" ] && echo true || echo false)

    default_dns=$(get_system_dns)
    [[ -z "$default_dns" ]] && default_dns="1.1.1.1,8.8.8.8"
    read -p "$(echo -e ${YELLOW}请输入 DNS ${GREEN}(默认: $default_dns)${YELLOW}: ${RESET})" dns
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

    # 安全获取公网 IP，避免 $() 内使用 || 导致语法错误
    HOST_IP=$(curl -s https://api64.ipify.org)
    if [ -z "$HOST_IP" ]; then
        HOST_IP=$(curl -s https://ifconfig.me)
    fi
    if [ -z "$HOST_IP" ]; then
        HOST_IP=$(curl -s https://ipinfo.io/ip)
    fi

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

    check_port_open $HOST_IP $port
}

create_service() {
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
}

start_service() {
    echo -e "${GREEN}[信息] 启动 Snell 服务...${RESET}"
    systemctl daemon-reload
    systemctl enable snell
    systemctl start snell
    sleep 1
    echo -e "${GREEN}[完成] Snell 已启动${RESET}"
}

# ================== 安装 / 更新 / 卸载 ==================
install_snell() {
    create_user
    mkdir -p $SNELL_DIR
    cd $SNELL_DIR

    ARCH=$(uname -m)
    VERSION="v5.0.0"
    [[ "$ARCH" == "aarch64" ]] && SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-aarch64.zip" || \
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-amd64.zip"

    download_snell "$SNELL_URL" "snell.zip"
    unzip_snell "snell.zip" "$SNELL_DIR"
    chmod +x "$SNELL_DIR/snell-server"
    rm -f snell.zip

    configure_snell
    create_service
    start_service
    log "Snell 已安装并启动"
    pause
}

update_snell() { systemctl stop snell || true; install_snell; systemctl restart snell; echo -e "${GREEN}[完成] Snell 已更新${RESET}"; log "Snell 已更新"; pause; }
uninstall_snell() { systemctl stop snell || true; systemctl disable snell || true; rm -f $SNELL_SERVICE; rm -rf $SNELL_DIR; systemctl daemon-reload; echo -e "${GREEN}[完成] Snell 已卸载${RESET}"; log "Snell 已卸载"; pause; }
start_snell() { systemctl start snell && echo -e "${GREEN}Snell 已启动${RESET}" && log "Snell 启动" && pause; }
stop_snell() { systemctl stop snell && echo -e "${GREEN}Snell 已停止${RESET}" && log "Snell 停止" && pause; }
restart_snell() { systemctl restart snell && echo -e "${GREEN}Snell 已重启${RESET}" && log "Snell 重启" && pause; }
view_log() { echo -e "${GREEN}[信息] Snell 日志输出（最近20行）${RESET}"; journalctl -u snell -n 20 --no-pager; pause; }
view_config() { [ -f $SNELL_CONFIG ] && cat $SNELL_CONFIG || echo -e "${RED}配置文件不存在${RESET}"; pause; }

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
    echo -e "${GREEN}9. 查看配置${RESET}"
    echo -e "${GREEN}0. 退出${RESET}"
    echo -e "${GREEN}============================${RESET}"
    read -p "请输入选项: " choice
}

# ================== 主循环 ==================
main() {
    [ "$(id -u)" != "0" ] && echo -e "${RED}请使用 root 用户运行${RESET}" && exit 1
    while true; do
        show_menu
        case $choice in
            1) install_snell ;;
            2) update_snell ;;
            3) uninstall_snell ;;
            4) configure_snell ;;
            5) start_snell ;;
            6) stop_snell ;;
            7) restart_snell ;;
            8) view_log ;;
            9) view_config ;;
            0) exit ;;
            *) echo -e "${RED}无效选项${RESET}" && pause ;;
        esac
    done
}

main
