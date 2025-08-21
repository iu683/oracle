#!/bin/bash
# ========================================
# 独角数卡 一键安装 & 管理脚本
# (含 Caddy 反代 + HTTPS + 域名解析检测 + 端口检测)
# ========================================

PROJECT_DIR=~/Shop
COMPOSE_FILE=$PROJECT_DIR/docker-compose.yml
ENV_FILE=$PROJECT_DIR/env.conf
CADDY_FILE=$PROJECT_DIR/Caddyfile

GREEN="\033[32m"
RED="\033[31m"
RESET="\033[0m"

# ---------- 检查 80/443 端口 ----------
check_ports() {
    for port in 80 443; do
        if lsof -i :$port &>/dev/null; then
            pid=$(lsof -ti :$port)
            pname=$(ps -p $pid -o comm=)
            echo -e "${RED}警告: 端口 $port 被进程 $pname (PID $pid) 占用！${RESET}"
            read -p "是否要停止该进程？(y/n): " yn
            if [[ "$yn" == "y" ]]; then
                kill -9 $pid
                echo -e "${GREEN}已停止 $pname 进程，释放端口 $port${RESET}"
            else
                echo -e "${RED}请手动释放端口 $port 后再继续安装！${RESET}"
                exit 1
            fi
        fi
    done
}

# ---------- 检查域名解析 ----------
check_domain() {
    local domain=$1
    local local_ip=$(curl -s ipv4.icanhazip.com)
    local domain_ip=$(dig +short $domain | tail -n1)

    echo -e "${GREEN}本机公网 IP: $local_ip${RESET}"
    echo -e "${GREEN}域名解析 IP: $domain_ip${RESET}"

    if [[ "$local_ip" != "$domain_ip" ]]; then
        echo -e "${RED}⚠️ 警告: 域名 $domain 未解析到本机！${RESET}"
        read -p "是否继续安装？(y/n): " yn
        [[ "$yn" != "y" ]] && exit 1
    else
        echo -e "${GREEN}✅ 域名解析正常${RESET}"
    fi
}

# ---------- 自动生成 APP_KEY ----------
gen_app_key() {
    KEY="base64:$(openssl rand -base64 32)"
    if grep -q "^APP_KEY=" "$ENV_FILE"; then
        sed -i "s|^APP_KEY=.*|APP_KEY=$KEY|" "$ENV_FILE"
    else
        echo "APP_KEY=$KEY" >> "$ENV_FILE"
    fi
    echo -e "${GREEN}已生成 APP_KEY: $KEY${RESET}"
}

# ---------- 安装 ----------
install() {
    check_ports   # 🔥 检查端口占用

    mkdir -p $PROJECT_DIR/{storage,uploads,data,redis}
    chmod 777 $PROJECT_DIR/storage $PROJECT_DIR/uploads

    read -p "请输入绑定的域名 (例如 shop.example.com): " DOMAIN

    # 🔥 检查域名解析
    check_domain $DOMAIN

    # 生成 docker-compose.yml
    cat > $COMPOSE_FILE <<EOF
version: "3"
services:
  faka:
    image: ghcr.io/apocalypsor/dujiaoka:latest
    container_name: faka
    environment:
      - INSTALL=true
    volumes:
      - ./env.conf:/dujiaoka/.env
      - ./uploads:/dujiaoka/public/uploads
      - ./storage:/dujiaoka/storage
    restart: always

  db:
    image: mariadb:focal
    container_name: faka-data
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=RootPass123
      - MYSQL_DATABASE=dujiaoka
      - MYSQL_USER=dujiaoka
      - MYSQL_PASSWORD=DbPass123
    volumes:
      - ./data:/var/lib/mysql

  redis:
    image: redis:alpine
    container_name: faka-redis
    restart: always
    volumes:
      - ./redis:/data

  caddy:
    image: caddy:latest
    container_name: faka-caddy
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./caddy_data:/data
      - ./caddy_config:/config
EOF

    # 生成 env.conf
    cat > $ENV_FILE <<EOF
APP_NAME=独角数卡
APP_ENV=local
APP_KEY=
APP_DEBUG=false
APP_URL=https://$DOMAIN

LOG_CHANNEL=stack

DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=dujiaoka
DB_USERNAME=dujiaoka
DB_PASSWORD=DbPass123

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
EOF

    # 生成 Caddyfile
    cat > $CADDY_FILE <<EOF
$DOMAIN {
    reverse_proxy faka:80
}
EOF

    # 自动生成 APP_KEY
    gen_app_key

    echo -e "${GREEN}安装文件已生成，请检查 $ENV_FILE 是否正确！${RESET}"
    echo -e "${RED}首次启动会自动安装，请用 https://$DOMAIN 打开网站完成配置。${RESET}"
    echo -e "${RED}完成安装后，请手动修改 docker-compose.yml，把 INSTALL=true 改成 false！${RESET}"
}

# ---------- 管理 ----------
start() { docker compose -f $COMPOSE_FILE up -d; }
stop() { docker compose -f $COMPOSE_FILE down; }
restart() { stop && start; }
logs() { docker logs -f faka; }
update() { docker compose -f $COMPOSE_FILE pull && restart; }
uninstall_keep() { docker compose -f $COMPOSE_FILE down; }
uninstall_all() { docker compose -f $COMPOSE_FILE down -v && rm -rf $PROJECT_DIR; }
enter_app() { docker exec -it faka bash; }
enter_db() { docker exec -it faka-data bash; }

# ---------- 菜单 ----------
menu() {
    clear
    echo -e "${GREEN}=== 独角数卡 管理菜单 ===${RESET}"
    echo -e "${GREEN}1) 一键安装 (含 Caddy 自动 HTTPS + 检查域名+端口)${RESET}"
    echo -e "${GREEN}2) 启动服务${RESET}"
    echo -e "${GREEN}3) 停止服务${RESET}"
    echo -e "${GREEN}4) 重启服务${RESET}"
    echo -e "${GREEN}5) 查看日志${RESET}"
    echo -e "${GREEN}6) 更新服务 (拉取最新镜像)${RESET}"
    echo -e "${GREEN}7) 卸载 (保留数据)${RESET}"
    echo -e "${GREEN}8) 卸载 (删除所有数据)${RESET}"
    echo -e "${GREEN}9) 进入应用容器${RESET}"
    echo -e "${GREEN}10) 进入数据库容器${RESET}"
    echo -e "${GREEN}11) 重新生成 APP_KEY${RESET}"
    echo -e "${GREEN}0) 退出${RESET}"
    echo
}

while true; do
    menu
    read -p "请选择操作: " choice
    case $choice in
        1) install ;;
        2) start ;;
        3) stop ;;
        4) restart ;;
        5) logs ;;
        6) update ;;
        7) uninstall_keep ;;
        8) uninstall_all ;;
        9) enter_app ;;
        10) enter_db ;;
        11) gen_app_key ;;
        0) exit 0 ;;
        *) echo "无效选项，请重新输入！" ;;
    esac
    read -p "按回车键继续..." 
done
