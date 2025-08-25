#!/bin/bash

# ===========================
# 颜色定义
# ===========================
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# ===========================
# 安装路径（统一管理）
# ===========================
INSTALL_DIR="/opt/dujiaoka"   # 可根据需要修改
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
DATA_DIR="$INSTALL_DIR/data"

# ===========================
# 检查是否 root
# ===========================
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}请使用 root 用户运行此脚本！${RESET}"
    exit 1
fi

# 创建安装目录
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_DIR/mysql"

# ===========================
# 检查端口是否被占用
# ===========================
check_port() {
    local port=$1
    while lsof -i :"$port" &>/dev/null; do
        echo -e "${RED}端口 $port 已被占用，请输入其他端口！${RESET}"
        read -rp "请输入前台访问端口: " port
    done
    echo "$port"
}

# ===========================
# Docker Compose 文件生成
# ===========================
create_compose_file() {
cat > "$COMPOSE_FILE" <<EOF
version: '3'
services:
  mysql:
    image: mysql:5.7
    environment:
      MYSQL_DATABASE: dujiaoka
      MYSQL_USER: dujiaoka
      MYSQL_PASSWORD: ${DB_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}
    volumes:
      - $DATA_DIR/mysql:/var/lib/mysql
    restart: always

  redis:
    image: redis:alpine
    restart: always

  dujiaoka:
    image: jiangjuhong/dujiaoka:latest
    container_name: dujiaoka
    ports:
      - "${APP_PORT}:80"
    environment:
      - APP_URL=${APP_URL}
      - ADMIN_HTTPS=true
      - ADMIN_ROUTE_PREFIX=/admin
      - WEB_DOCUMENT_ROOT=/app/public
      - TZ=Asia/Shanghai
    restart: always
EOF
}

# ===========================
# 菜单函数
# ===========================
show_menu() {
    echo -e "${GREEN}===== DuJiaoka Docker 管理脚本 =====${RESET}"
    echo -e "${GREEN}1.${RESET} 安装并启动 DuJiaoka"
    echo -e "${GREEN}2.${RESET} 启动服务"
    echo -e "${GREEN}3.${RESET} 停止服务"
    echo -e "${GREEN}4.${RESET} 重启服务"
    echo -e "${GREEN}5.${RESET} 查看服务状态"
    echo -e "${GREEN}6.${RESET} 卸载 DuJiaoka（删除全部数据）"
    echo -e "${GREEN}0.${RESET} 退出"
}

# ===========================
# 功能函数
# ===========================
install_dujiaoka() {
    read -rp "请输入你的域名（例如 https://example.com）: " APP_URL

    read -rp "请输入前台访问端口（默认 8080）: " APP_PORT
    APP_PORT=${APP_PORT:-8080}
    APP_PORT=$(check_port "$APP_PORT")

    read -rp "请输入数据库密码（默认 dujiaoka_password）: " DB_PASSWORD
    DB_PASSWORD=${DB_PASSWORD:-dujiaoka_password}

    create_compose_file
    docker compose -f "$COMPOSE_FILE" up -d

    echo -e "${GREEN}DuJiaoka 安装并启动完成！${RESET}"
    echo -e "${GREEN}数据库信息:${RESET}"
    echo -e "${YELLOW}数据库地址: mysql${RESET}"
    echo -e "${YELLOW}端口: 3306${RESET}"
    echo -e "${YELLOW}数据库名称: dujiaoka${RESET}"
    echo -e "${YELLOW}用户名: dujiaoka${RESET}"
    echo -e "${YELLOW}密码: ${DB_PASSWORD}${RESET}"

    echo -e "${GREEN}Redis 信息:${RESET}"
    echo -e "${YELLOW}Redis 地址: redis${RESET}"
}

start_dujiaoka() {
    docker compose -f "$COMPOSE_FILE" up -d
    echo -e "${GREEN}服务已启动！${RESET}"
}

stop_dujiaoka() {
    docker compose -f "$COMPOSE_FILE" down
    echo -e "${RED}服务已停止！${RESET}"
}

restart_dujiaoka() {
    docker compose -f "$COMPOSE_FILE" down
    docker compose -f "$COMPOSE_FILE" up -d
    echo -e "${GREEN}服务已重启！${RESET}"
}

status_dujiaoka() {
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

uninstall_dujiaoka() {
    docker compose -f "$COMPOSE_FILE" down
    rm -rf "$INSTALL_DIR"
    echo -e "${RED}DuJiaoka 已彻底卸载，所有数据已清除！${RESET}"
}

# ===========================
# 主循环
# ===========================
while true; do
    show_menu
    read -rp "请输入选项: " choice
    case $choice in
        1) install_dujiaoka ;;
        2) start_dujiaoka ;;
        3) stop_dujiaoka ;;
        4) restart_dujiaoka ;;
        5) status_dujiaoka ;;
        6) uninstall_dujiaoka ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项，请重新输入！${RESET}" ;;
    esac
done
