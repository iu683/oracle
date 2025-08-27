#!/bin/bash
set -e

# ================== 颜色 ==================
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

info() { echo -e "${GREEN}[INFO] $1${RESET}"; }
warn() { echo -e "${YELLOW}[WARN] $1${RESET}"; }
error() { echo -e "${RED}[ERROR] $1${RESET}"; }

COMPOSE_FILE="docker-compose.yml"
KV_VOLUME="kvrocks-data"

# ================== 用户输入 ==================
read_input() {
    # 强制输入用户名
    while true; do
        read -p "请输入 MoonTV 用户名: " TV_USER
        if [[ -n "$TV_USER" ]]; then
            break
        else
            echo "用户名不能为空，请重新输入。"
        fi
    done

    # 强制输入密码
    while true; do
        read -p "请输入 MoonTV 密码: " TV_PASS
        if [[ -n "$TV_PASS" ]]; then
            break
        else
            echo "密码不能为空，请重新输入。"
        fi
    done

    # 端口可以使用默认值
    read -p "请输入 MoonTV 访问端口 (默认 3000): " TV_PORT
    TV_PORT=${TV_PORT:-3000}

    read -p "请输入 KVrocks 端口 (默认 6666): " KV_PORT
    KV_PORT=${KV_PORT:-6666}
}

# ================== 生成 docker-compose.yml ==================
generate_compose() {
    info "正在生成 docker-compose.yml 文件..."
    cat > $COMPOSE_FILE <<EOF
services:
  moontv-core:
    image: ghcr.io/moontechlab/lunatv:latest
    container_name: moontv-core
    restart: on-failure
    ports:
      - '${TV_PORT}:3000'
    environment:
      - USERNAME=${TV_USER}
      - PASSWORD=${TV_PASS}
      - NEXT_PUBLIC_STORAGE_TYPE=kvrocks
      - KVROCKS_URL=redis://moontv-kvrocks:${KV_PORT}
    networks:
      - moontv-network
    depends_on:
      - moontv-kvrocks

  moontv-kvrocks:
    image: apache/kvrocks
    container_name: moontv-kvrocks
    restart: unless-stopped
    ports:
      - '${KV_PORT}:${KV_PORT}'
    volumes:
      - ${KV_VOLUME}:/var/lib/kvrocks
    networks:
      - moontv-network

networks:
  moontv-network:
    driver: bridge

volumes:
  ${KV_VOLUME}:
EOF
    info "docker-compose.yml 文件生成完成！"
}

# ================== 安装 ==================
install() {
    read_input
    generate_compose
    info "启动容器中..."
    docker-compose up -d

    # 获取公网 IP
    SERVER_IP=$(curl -s https://ifconfig.me)

    info "部署完成！访问: http://${SERVER_IP}:${TV_PORT} 用户名: ${TV_USER} 密码: ${TV_PASS}"
}

# ================== 卸载 ==================
uninstall() {
    warn "即将停止并删除容器，并清除 KVrocks 数据！"
    read -p "确定吗？(y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        docker-compose down
        docker volume rm ${KV_VOLUME} || true
        info "卸载完成，KVrocks 数据已清除。"
    else
        info "已取消卸载。"
    fi
}

# ================== 更新 ==================
update() {
    info "拉取最新 MoonTV 镜像..."
    docker pull ghcr.io/moontechlab/lunatv:latest
    info "拉取最新 KVrocks 镜像..."
    docker pull apache/kvrocks

    info "停止当前容器..."
    docker-compose down

    info "启动最新容器..."
    docker-compose up -d

    info "更新完成！MoonTV 和 KVrocks 已使用最新镜像启动。"
}

# ================== 查看日志 ==================
show_logs() {
    info "显示 MoonTV 和 KVrocks 日志，按 Ctrl+C 停止查看..."
    docker-compose logs -f
    read -p "按回车返回主菜单..." dummy
}

# ================== 主菜单 ==================
while true; do
    echo -e "${GREEN}================ MoonTV 管理脚本 ================${RESET}"
    echo -e "${GREEN}1. 安装/部署${RESET}"
    echo -e "${GREEN}2. 卸载/清理${RESET}"
    echo -e "${GREEN}3. 更新（拉取最新镜像并重启）${RESET}"
    echo -e "${GREEN}4. 查看日志${RESET}"
    echo -e "${GREEN}5. 退出${RESET}"
    read -p "请选择操作 [1-5]: " choice

    case $choice in
        1) install ;;
        2) uninstall ;;
        3) update ;;
        4) show_logs ;;
        5) exit 0 ;;
        *) warn "无效选项，请重新输入！" ;;
    esac
done
