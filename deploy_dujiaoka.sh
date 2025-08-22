#!/bin/bash
set -e

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

INSTALL_DIR="/root/dujiaoka"
SRC_DIR="$INSTALL_DIR/dujiaoka"

echo -e "${GREEN}=== 开始部署 Dujiaoka Docker 环境 ===${RESET}"

# 安装 git
if ! command -v git &>/dev/null; then
    echo -e "${GREEN}安装 git...${RESET}"
    yum install -y git
fi

# 创建安装目录
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 拉取源码（如果不存在就 clone）
if [ ! -d "$SRC_DIR" ]; then
    echo -e "${GREEN}拉取 Dujiaoka 源码...${RESET}"
    git clone https://github.com/assimon/dujiaoka.git
else
    echo -e "${GREEN}源码已存在，执行 git pull 更新...${RESET}"
    cd "$SRC_DIR"
    git pull
    cd "$INSTALL_DIR"
fi

# -------------------------------
# 1. Dockerfile
# -------------------------------
cat > "$INSTALL_DIR/Dockerfile" <<'EOF'
FROM webdevops/php-nginx:7.4
WORKDIR /app
COPY dujiaoka/ /app
RUN COMPOSER_ALLOW_SUPERUSER=1 composer install --ignore-platform-reqs
RUN echo "#!/bin/bash\nphp artisan queue:work >/tmp/work.log 2>&1 &\nsupervisord" > /app/start.sh \
    && chmod +x /app/start.sh \
    && chmod -R 777 /app
CMD [ "sh", "-c", "/app/start.sh" ]
EOF

# -------------------------------
# 2. laravel-worker.conf
# -------------------------------
cat > "$INSTALL_DIR/laravel-worker.conf" <<'EOF'
[program:laravel-worker]
process_name=%(program_name)s_%(process_num)02d
command=php /app/artisan queue:work --sleep=3 --tries=3 --daemon
autostart=true
autorestart=true
user=root
numprocs=1
redirect_stderr=true
stdout_logfile=/app/storage/logs/worker.log
EOF

# -------------------------------
# 3. docker-compose.yml
# -------------------------------
cat > "$INSTALL_DIR/docker-compose.yml" <<'EOF'
services:
  web:
    build: .
    container_name: dujiaoka
    ports:
      - "8020:80"
      - "9000:9000"
    volumes:
      - ./dujiaoka/.env:/app/.env
      - ./dujiaoka/install.lock:/app/install.lock
      - ./dujiaoka/public/uploads:/app/public/uploads
    environment:
      WEB_DOCUMENT_ROOT: "/app/public"
      TZ: Asia/Shanghai
    tty: true
    restart: always
    depends_on:
      - db
      - redis

  db:
    image: mysql:5.7
    container_name: dujiaoka_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: root123
      MYSQL_DATABASE: dujiaoka
      MYSQL_USER: dujiaoka
      MYSQL_PASSWORD: dujiaoka123
    ports:
      - "3306:3306"
    volumes:
      - ./mysql:/var/lib/mysql

  redis:
    image: redis:6
    container_name: dujiaoka_redis
    restart: always
    ports:
      - "6379:6379"
EOF

# -------------------------------
# 4. .env 配置
# -------------------------------
cat > "$SRC_DIR/.env" <<'EOF'
APP_NAME=独角数卡
APP_ENV=local
APP_KEY=
APP_DEBUG=true
APP_URL=http://localhost

LOG_CHANNEL=stack

DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=dujiaoka
DB_USERNAME=dujiaoka
DB_PASSWORD=dujiaoka123

REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=6379

BROADCAST_DRIVER=log
SESSION_DRIVER=file
SESSION_LIFETIME=120

CACHE_DRIVER=file
QUEUE_CONNECTION=redis

DUJIAO_ADMIN_LANGUAGE=zh_CN
ADMIN_ROUTE_PREFIX=/admin
EOF

# -------------------------------
# 5. menu.sh（管理脚本，带数据库就绪等待）
# -------------------------------
cat > "$INSTALL_DIR/menu.sh" <<'EOF'
#!/bin/bash
set -e

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

COMPOSE_FILE="docker-compose.yml"
ENV_FILE="./dujiaoka/.env"

menu() {
    clear
    echo -e "${GREEN}=== Dujiaoka Docker 管理菜单 ===${RESET}"
    echo -e "${GREEN}1) 启动服务 (自动生成 APP_KEY + migrate + seed)${RESET}"
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
    until docker-compose -f $COMPOSE_FILE exec -T db mysqladmin ping -h"db" --silent; do
        sleep 2
        echo -n "."
    done
    echo -e "\n${GREEN}✅ 数据库就绪${RESET}"
}

start_service() {
    echo -e "${GREEN}🚀 启动 Dujiaoka 服务中...${RESET}"
    docker-compose -f $COMPOSE_FILE up -d

    # 等待数据库
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

    # 执行迁移与填充
    echo -e "${GREEN}📦 执行 migrate 与 seed...${RESET}"
    docker-compose -f $COMPOSE_FILE exec -T web php artisan migrate --force
    docker-compose -f $COMPOSE_FILE exec -T web php artisan db:seed --force
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
    echo -e "0) 返回上级"
    read -p "请输入选项: " log_choice
    case $log_choice in
        1) docker-compose -f $COMPOSE_FILE logs -f web ;;
        2) docker-compose -f $COMPOSE_FILE logs -f db ;;
        3) docker-compose -f $COMPOSE_FILE logs -f redis ;;
        0) return ;;
        *) echo -e "${YELLOW}无效输入，请重试...${RESET}" ;;
    esac
}

uninstall() {
    echo -e "${RED}⚠️ 卸载 Dujiaoka...${RESET}"
    docker-compose -f $COMPOSE_FILE down -v
    rm -rf "$PWD/dujiaoka" "$PWD/mysql"
    echo -e "${RED}✅ 卸载完成${RESET}"
}

menu
EOF

chmod +x "$INSTALL_DIR/menu.sh"

echo -e "${GREEN}✅ 部署完成，可执行 ./menu.sh 管理 Dujiaoka${RESET}"
