#!/bin/bash

# =========================================
# Dujiaoka Docker 一键安装 + 管理脚本
# =========================================

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# 安装目录
INSTALL_DIR="/root/data/docker_data/shop"

# ---------------- 函数：安装 ----------------
install_dujiaoka() {
    echo -e "${GREEN}创建安装目录和必要子目录...${RESET}"
    mkdir -p "$INSTALL_DIR"/{storage,uploads,mysql,redis}
    chmod -R 777 "$INSTALL_DIR"/{storage,uploads}

    ENV_FILE="$INSTALL_DIR/env.conf"
    echo -e "${GREEN}生成 env.conf 文件...${RESET}"

    read -p "请输入你的域名 (例 https://example.com): " DOMAIN
    read -p "请输入数据库密码: " DB_PASS

    cat > "$ENV_FILE" <<EOF
APP_NAME=咕咕的小卖部
APP_ENV=local
APP_KEY=base64:rKwRuI6eRpCw/9e2XZKKGj/Yx3iZy5e7+FQ6+aQl8Zg=
APP_DEBUG=true
APP_URL=$DOMAIN

LOG_CHANNEL=stack

DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=dujiaoka
DB_USERNAME=dujiaoka
DB_PASSWORD=$DB_PASS

REDIS_HOST=redis
REDIS_PASSWORD=
REDIS_PORT=6379

BROADCAST_DRIVER=log
SESSION_DRIVER=file
SESSION_LIFETIME=120

CACHE_DRIVER=redis
QUEUE_CONNECTION=redis

DUJIAO_ADMIN_LANGUAGE=zh_CN
ADMIN_ROUTE_PREFIX=/admin
ADMIN_HTTPS=true
EOF

    chmod 777 "$ENV_FILE"

    DOCKER_COMPOSE="$INSTALL_DIR/docker-compose.yml"
    echo -e "${GREEN}生成 docker-compose.yml 文件...${RESET}"

    cat > "$DOCKER_COMPOSE" <<EOF
version: "3"

services:
  web:
    image: stilleshan/dujiaoka
    environment:
        - INSTALL=true
    volumes:
      - ./env.conf:/dujiaoka/.env
      - ./uploads:/dujiaoka/public/uploads
      - ./storage:/dujiaoka/storage
    ports:
      - 8090:80
    restart: always
 
  db:
    image: mariadb:focal
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=$DB_PASS
      - MYSQL_DATABASE=dujiaoka
      - MYSQL_USER=dujiaoka
      - MYSQL_PASSWORD=$DB_PASS
    volumes:
      - ./mysql:/var/lib/mysql

  redis:
    image: redis:alpine
    restart: always
    volumes:
      - ./redis:/data
EOF

    echo -e "${GREEN}安装完成！现在启动容器...${RESET}"
    cd "$INSTALL_DIR"
    docker-compose up -d
    echo -e "${GREEN}访问: http://<服务器IP>:8090${RESET}"
}

# ---------------- 函数：管理菜单 ----------------
manage_dujiaoka() {
    cd "$INSTALL_DIR" || exit

    menu() {
        clear
        echo -e "${GREEN}=== Dujiaoka 容器管理菜单 ===${RESET}"
        echo -e "${YELLOW}1) 启动容器${RESET}"
        echo -e "${YELLOW}2) 停止容器${RESET}"
        echo -e "${YELLOW}3) 重启容器${RESET}"
        echo -e "${YELLOW}4) 删除容器（保留数据）${RESET}"
        echo -e "${YELLOW}5) 删除容器和数据${RESET}"
        echo -e "${YELLOW}6) 查看容器状态${RESET}"
        echo -e "${YELLOW}0) 退出${RESET}"
        echo
        read -p "请选择操作 [0-6]: " choice
        case $choice in
            1) docker-compose up -d; pause ;;
            2) docker-compose stop; pause ;;
            3) docker-compose restart; pause ;;
            4) docker-compose down; pause ;;
            5) docker-compose down && rm -rf ./mysql ./uploads ./storage ./redis; pause ;;
            6) docker ps -a; pause ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选项${RESET}"; sleep 1; menu ;;
        esac
    }

    pause() {
        read -p "按回车返回菜单..."
        menu
    }

    menu
}

# ---------------- 主菜单 ----------------
main_menu() {
    clear
    echo -e "${GREEN}=== Dujiaoka 安装与管理一体化脚本 ===${RESET}"
    echo -e "${YELLOW}1) 安装 Dujiaoka${RESET}"
    echo -e "${YELLOW}2) 管理 Dujiaoka 容器${RESET}"
    echo -e "${YELLOW}0) 退出${RESET}"
    echo
    read -p "请选择操作 [0-2]: " main_choice
    case $main_choice in
        1) install_dujiaoka; main_menu ;;
        2) manage_dujiaoka; main_menu ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项${RESET}"; sleep 1; main_menu ;;
    esac
}

main_menu
