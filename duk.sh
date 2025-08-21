#!/bin/bash
# ========================================
# 独角数卡终极管理脚本
# ========================================

PROJECT_DIR=~/dujiaoka
DOMAIN="你的域名"            # 替换为你的域名
EMAIL="你的邮箱@example.com"  # 用于HTTPS
MYSQL_ROOT_PASSWORD="dujiaoka_password"
MYSQL_USER="dujiaoka"
MYSQL_PASSWORD="dujiaoka_password"
MYSQL_DB="dujiaoka"
TZ="Asia/Shanghai"

GREEN="\033[32m"
RED="\033[31m"
RESET="\033[0m"

# --------- 创建 Docker Compose 文件 ---------
create_compose() {
    mkdir -p $PROJECT_DIR
    cd $PROJECT_DIR || exit
    cat > docker-compose.yml <<EOF
version: "3.8"

services:
  mysql:
    image: mysql:5.7
    environment:
      MYSQL_DATABASE: $MYSQL_DB
      MYSQL_USER: $MYSQL_USER
      MYSQL_PASSWORD: $MYSQL_PASSWORD
      MYSQL_ROOT_PASSWORD: $MYSQL_ROOT_PASSWORD
    volumes:
      - ./data/mysql:/var/lib/mysql
    restart: always

  redis:
    image: redis:alpine
    restart: always

  dujiaoka:
    image: jiangjuhong/dujiaoka:latest
    container_name: dujiaoka
    ports:
      - "8080:80"
    environment:
      - APP_URL=https://$DOMAIN
      - ADMIN_HTTPS=true
      - ADMIN_ROUTE_PREFIX=/admin
      - WEB_DOCUMENT_ROOT=/app/public
      - TZ=$TZ
    restart: always

  caddy:
    image: caddy:2
    container_name: caddy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    restart: always

volumes:
  caddy_data:
  caddy_config:
EOF

    cat > Caddyfile <<EOF
$DOMAIN {
    reverse_proxy dujiaoka:80
    tls $EMAIL
}
EOF
}

# --------- 检查域名解析 ---------
check_domain() {
    IP=$(ping -c 1 $DOMAIN | grep 'bytes from' | awk -F' ' '{print $4}' | sed 's/://')
    if [ -z "$IP" ]; then
        echo -e "${RED}域名解析失败，请确保 $DOMAIN 已解析到本服务器${RESET}"
        exit 1
    else
        echo -e "${GREEN}域名解析正常：$IP${RESET}"
    fi
}

# --------- 检查端口 ---------
check_ports() {
    for PORT in 80 443 8080; do
        if lsof -i:$PORT &>/dev/null; then
            echo -e "${RED}端口 $PORT 已被占用，请先释放${RESET}"
            exit 1
        fi
    done
}

# --------- 菜单功能 ---------
menu() {
    echo -e "${GREEN}=== 独角数卡管理菜单 ===${RESET}"
    echo "1) 安装并启动"
    echo "2) 启动服务"
    echo "3) 停止服务"
    echo "4) 重启服务"
    echo "5) 查看日志"
    echo "6) 卸载 (删除容器和数据)"
    echo "0) 退出"
    read -rp "选择操作: " CHOICE
    case $CHOICE in
        1) check_domain; check_ports; create_compose; docker-compose up -d;;
        2) docker-compose start;;
        3) docker-compose stop;;
        4) docker-compose restart;;
        5) docker-compose logs -f;;
        6) docker-compose down -v;;
        0) exit 0;;
        *) echo "无效选项";;
    esac
}

# --------- 主循环 ---------
while true; do
    menu
done
