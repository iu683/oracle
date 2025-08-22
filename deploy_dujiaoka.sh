#!/bin/bash
set -e

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

INSTALL_DIR="/root/dujiaoka/dujiaoka"
SRC_DIR="$INSTALL_DIR/dujiaoka"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
ENV_FILE="$SRC_DIR/.env"
MIGRATE_LOG="$INSTALL_DIR/migrate_seed.log"

menu() {
    clear
    echo -e "${GREEN}=== Dujiaoka Docker 管理菜单 ===${RESET}"
    echo -e "${GREEN}1) 启动服务 (自动生成 APP_KEY + migrate/seed)${RESET}"
    echo -e "${GREEN}2) 停止服务${RESET}"
    echo -e "${GREEN}3) 重启服务${RESET}"
    echo -e "${GREEN}4) 查看数据库/Redis 信息${RESET}"
    echo -e "${GREEN}5) 查看日志${RESET}"
    echo -e "${GREEN}6) 卸载 Dujiaoka${RESET}"
    echo -e "${GREEN}0) 退出${RESET}"
    echo
    read -p "请输入选项: " choice

    case $choice in
        1) start_service ;;
        2) docker-compose -f $COMPOSE_FILE down ;;
        3) docker-compose -f $COMPOSE_FILE restart ;;
        4) show_info ;;
        5) show_logs ;;
        6) uninstall ;;
        0) exit 0 ;;
        *) echo -e "${YELLOW}无效输入，请重试...${RESET}" ;;
    esac
    read -p "按回车返回菜单..." enter
    menu
}

wait_for_db() {
    echo -e "${GREEN}⏳ 等待数据库启动...${RESET}"
    until docker-compose -f $COMPOSE_FILE exec -T db mysqladmin ping -h db --silent; do
        printf "."
        sleep 2
    done
    echo
    echo -e "${GREEN}✅ 数据库就绪${RESET}"
}

migrate_and_seed() {
    echo -e "${GREEN}📦 执行 migrate 与 seed...${RESET}"
    docker-compose -f $COMPOSE_FILE exec -T web sh -c "
    RETRY=0
    until php artisan migrate --force; do
        RETRY=\$((RETRY+1))
        echo 'Migration 未完成，等待 3 秒后重试... (\$RETRY)'
        sleep 3
        [ \$RETRY -gt 10 ] && echo 'Migration 超过 10 次失败，退出!' && exit 1
    done
    php artisan db:seed --force
    " &> "$MIGRATE_LOG" &
    echo -e "${YELLOW}ℹ️ migrate/seed 日志: tail -f $MIGRATE_LOG${RESET}"
}

start_service() {
    echo -e "${GREEN}🚀 启动 Dujiaoka 服务中...${RESET}"
    docker-compose -f $COMPOSE_FILE up -d

    wait_for_db

    # 生成 APP_KEY
    APP_KEY=$(grep '^APP_KEY=' $ENV_FILE | cut -d '=' -f2)
    if [ -z "$APP_KEY" ]; then
        echo -e "${GREEN}⚙️ 生成 APP_KEY...${RESET}"
        docker-compose -f $COMPOSE_FILE exec -T web php artisan key:generate
        echo -e "${GREEN}✅ APP_KEY 已生成并写入 .env${RESET}"
    else
        echo -e "${GREEN}🔑 APP_KEY 已存在，跳过生成${RESET}"
    fi

    migrate_and_seed

    echo -e "${GREEN}✅ 服务启动完成${RESET}"
}

show_info() {
    echo -e "${GREEN}=== MySQL 信息 ===${RESET}"
    echo "主机: localhost"
    echo "端口: 3306"
    echo "用户名: dujiaoka"
    echo "密码: dujiaoka123"
    echo
    echo -e "${GREEN}=== Redis 信息 ===${RESET}"
    echo "主机: localhost"
    echo "端口: 6379"
    echo "密码: 无"
}

show_logs() {
    echo -e "${GREEN}请选择要查看的日志:${RESET}"
    echo -e "1) Web (Dujiaoka)"
    echo -e "2) MySQL"
    echo -e "3) Redis"
    echo -e "4) migrate/seed 日志"
    echo -e "0) 返回上级"
    read -p "请输入选项: " log_choice
    case $log_choice in
        1) docker-compose -f $COMPOSE_FILE logs -f web ;;
        2) docker-compose -f $COMPOSE_FILE logs -f db ;;
        3) docker-compose -f $COMPOSE_FILE logs -f redis ;;
        4) tail -f "$MIGRATE_LOG" ;;
        0) return ;;
        *) echo -e "${YELLOW}无效输入，请重试...${RESET}" ;;
    esac
}

uninstall() {
    echo -e "${RED}⚠️ 卸载 Dujiaoka，将删除所有容器、数据和源码！${RESET}"
    read -p "确认卸载请输入 y: " confirm
    if [ "$confirm" = "y" ]; then
        docker-compose -f $COMPOSE_FILE down -v
        rm -rf "$SRC_DIR"
        rm -rf "$INSTALL_DIR/mysql"
        rm -f "$COMPOSE_FILE"
        rm -f "$MIGRATE_LOG"
        echo -e "${GREEN}✅ 卸载完成${RESET}"
        exit 0
    else
        echo -e "${YELLOW}取消卸载${RESET}"
    fi
}

menu
