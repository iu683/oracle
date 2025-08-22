#!/bin/bash
# =====================================
# Dujiaoka Docker 管理脚本（最终版）
# 支持自定义 APP_URL，显示数据库/Redis 信息
# =====================================
set -e

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

INSTALL_DIR="$(pwd)"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
DUJIAOKA_APP_NAME="dujiaoka"

# 数据库和 Redis 信息
DB_HOST="mysql"
DB_PORT=3306
DB_NAME="dujiaoka"
DB_USER="dujiaoka"
DB_PASSWORD="dujiaoka_password"

REDIS_HOST="redis"
REDIS_PORT=6379

APP_URL_DEFAULT="http://127.0.0.1:8080"
APP_URL="$APP_URL_DEFAULT"

# ==============================
# 自动生成 docker-compose.yml
# ==============================
generate_compose() {
cat > "$COMPOSE_FILE" <<EOF
version: "3.8"

services:
  mysql:
    image: mysql:5.7
    container_name: dujiaoka_mysql
    environment:
      MYSQL_DATABASE: $DB_NAME
      MYSQL_USER: $DB_USER
      MYSQL_PASSWORD: $DB_PASSWORD
      MYSQL_ROOT_PASSWORD: $DB_PASSWORD
    volumes:
      - ./data/mysql:/var/lib/mysql
    restart: always

  redis:
    image: redis:alpine
    container_name: dujiaoka_redis
    restart: always

  dujiaoka:
    image: jiangjuhong/dujiaoka:latest
    container_name: $DUJIAOKA_APP_NAME
    ports:
      - "8080:80"
    environment:
      - APP_URL=$APP_URL
      - ADMIN_HTTPS=false
      - ADMIN_ROUTE_PREFIX=/admin
      - WEB_DOCUMENT_ROOT=/app/public
      - TZ=Asia/Shanghai
    restart: always
EOF
echo -e "${GREEN}docker-compose.yml 已生成，APP_URL=$APP_URL${RESET}"
}

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}Docker 未安装，请先安装 Docker${RESET}"
        exit 1
    fi
}

# 启动容器
start() {
    # 让用户输入 APP_URL
    read -p "请输入 APP_URL（默认 $APP_URL_DEFAULT）: " input_url
    if [[ -n "$input_url" ]]; then
        APP_URL="$input_url"
    else
        APP_URL="$APP_URL_DEFAULT"
    fi

    # 提示用户反代
    echo -e "${YELLOW}请确保您的域名已反向代理到本机 8080 端口，并且开启 HTTPS${RESET}"
    echo -e "${YELLOW}如果使用本地测试，可直接使用 http://127.0.0.1:8080${RESET}"

    generate_compose
    echo -e "${GREEN}启动 Dujiaoka 容器...${RESET}"
    docker compose -f "$COMPOSE_FILE" up -d

    echo -e "${GREEN}启动完成！${RESET}"
    show_access
    show_db_info
}

# 停止容器
stop() {
    echo -e "${YELLOW}停止 Dujiaoka 容器...${RESET}"
    docker compose -f "$COMPOSE_FILE" down
    echo -e "${YELLOW}已停止${RESET}"
}

# 重启容器
restart() {
    stop
    start
}

# 查看日志
logs() {
    docker logs -f "$DUJIAOKA_APP_NAME"
}

# 卸载 Dujiaoka
uninstall() {
    echo -e "${RED}即将卸载 Dujiaoka 并删除数据！${RESET}"
    read -p "确定吗？(y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        docker compose -f "$COMPOSE_FILE" down -v
        echo -e "${RED}已卸载${RESET}"
    else
        echo -e "${YELLOW}已取消卸载${RESET}"
    fi
}

# 显示访问地址
show_access() {
    local ip
    ip=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}本地访问: $APP_URL${RESET}"
    echo -e "${GREEN}局域网访问: http://$ip:8080${RESET}"
}

# 显示数据库和 Redis 信息
show_db_info() {
    echo -e "\n${YELLOW}=== 数据库信息 ===${RESET}"
    echo -e "${GREEN}数据库地址: $DB_HOST${RESET}"
    echo -e "${GREEN}端口: $DB_PORT${RESET}"
    echo -e "${GREEN}数据库名称: $DB_NAME${RESET}"
    echo -e "${GREEN}用户名: $DB_USER${RESET}"
    echo -e "${GREEN}密码: $DB_PASSWORD${RESET}"

    echo -e "\n${YELLOW}=== Redis 信息 ===${RESET}"
    echo -e "${GREEN}Redis 地址: $REDIS_HOST${RESET}"
    echo -e "${GREEN}端口: $REDIS_PORT${RESET}"
}

# 菜单
menu() {
    while true; do
        echo -e "\n${GREEN}=== Dujiaoka Docker 管理菜单 ===${RESET}"
        echo -e "${GREEN}1) 启动服务${RESET}"
        echo -e "${YELLOW}2) 停止服务${RESET}"
        echo -e "${YELLOW}3) 重启服务${RESET}"
        echo -e "${GREEN}4) 查看日志${RESET}"
        echo -e "${RED}5) 卸载 Dujiaoka${RESET}"
        echo -e "0) 退出"
        read -p "请输入选项: " choice
        case "$choice" in
            1) start ;;
            2) stop ;;
            3) restart ;;
            4) logs ;;
            5) uninstall ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选择，请重新输入！${RESET}" ;;
        esac
    done
}

check_docker
menu
