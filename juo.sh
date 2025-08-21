#!/bin/bash
# ========================================
# 独角数卡终极管理脚本（手动输入配置 + 信息显示）
# ========================================

PROJECT_DIR=~/dujiaoka
TZ="Asia/Shanghai"

GREEN="\033[32m"
RED="\033[31m"
RESET="\033[0m"

# --------- 用户输入配置 ---------
read -rp "请输入你的域名（例：example.com）: " DOMAIN
read -rp "请输入你的邮箱（用于HTTPS证书）: " EMAIL
read -rp "请输入数据库名称（默认：dujiaoka）: " MYSQL_DB
MYSQL_DB=${MYSQL_DB:-dujiaoka}

read -rp "请输入数据库用户名（默认：dujiaoka）: " MYSQL_USER
MYSQL_USER=${MYSQL_USER:-dujiaoka}

read -rsp "请输入数据库密码（留空自动生成随机密码）: " MYSQL_PASSWORD
echo ""
if [ -z "$MYSQL_PASSWORD" ]; then
    MYSQL_PASSWORD=$(openssl rand -base64 12)
    echo "已生成随机数据库密码: $MYSQL_PASSWORD"
fi

read -rsp "请输入数据库root密码（留空同上）: " MYSQL_ROOT_PASSWORD
echo ""
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    MYSQL_ROOT_PASSWORD=$MYSQL_PASSWORD
    echo "root密码同数据库密码: $MYSQL_ROOT_PASSWORD"
fi

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

# --------- 安装并显示信息 ---------
install_and_show_info() {
    check_domain
    check_ports
    create_compose
    docker-compose up -d

    echo -e "\n${GREEN}======================================="
    echo "Dujiaoka 部署完成！"
    echo "访问地址: https://$DOMAIN"
    echo ""
    echo "数据库信息："
    echo "  地址: mysql"
    echo "  端口: 3306"
    echo "  数据库: $MYSQL_DB"
    echo "  用户名: $MYSQL_USER"
    echo "  密码: $MYSQL_PASSWORD"
    echo ""
    echo "Redis 信息："
    echo "  地址: redis"
    echo "  端口: 6379"
    echo -e "=======================================${RESET}\n"
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
        1) install_and_show_info;;
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
