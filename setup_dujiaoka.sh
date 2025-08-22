#!/bin/bash
set -e

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

echo -e "${GREEN}=== 开始部署 Dujiaoka Docker 环境 ===${RESET}"

# 创建目录
mkdir -p dujiaoka mysql redis logs
cd dujiaoka

# 1. 生成 Dockerfile
cat > Dockerfile <<'EOF'
FROM webdevops/php-nginx:7.4
WORKDIR /app
COPY . /app
RUN composer install --ignore-platform-reqs
RUN echo "#!/bin/bash\nphp artisan queue:work >/tmp/work.log 2>&1 &\nsupervisord" > /app/start.sh \
    && chmod +x /app/start.sh \
    && chmod -R 777 /app
CMD [ "sh", "-c", "/app/start.sh" ]
EOF

# 2. 生成 laravel-worker.conf
cat > laravel-worker.conf <<'EOF'
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

# 3. 生成 docker-compose.yml
cat > docker-compose.yml <<'EOF'
version: "2.2"
services:
  web:
    build: .
    container_name: dujiaoka
    ports:
      - "80:80"
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

# 4. 生成 .env 配置
cat > .env <<'EOF'
APP_NAME=独角数卡
APP_ENV=local
APP_KEY=
APP_DEBUG=true
APP_URL=http://localhost

LOG_CHANNEL=stack

# 数据库配置
DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=dujiaoka
DB_USERNAME=dujiaoka
DB_PASSWORD=dujiaoka123

# redis配置
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

# 5. 生成 menu.sh（启动服务自动检测 APP_KEY）
cat > menu.sh <<'EOF'
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
    echo -e "${GREEN}1) 启动服务 (自动生成 APP_KEY)${RESET}"
    echo -e "${GREEN}2) 停止服务${RESET}"
    echo -e "${GREEN}3) 重启服务${RESET}"
    echo -e "${GREEN}4) 查看数据库/Redis 信息${RESET}"
    echo -e "${GREEN}5) 查看日志${RESET}"
    echo -e "${GREEN}0) 退出${RESET}"
    echo
    read -p "请输入选项: " choice

    case $choice in
        1) start_service ;;
        2) docker-compose -f $COMPOSE_FILE down ;;
        3) docker-compose -f $COMPOSE_FILE restart ;;
        4) show_info ;;
        5) show_logs ;;
        0) exit 0 ;;
        *) echo -e "${YELLOW}无效输入，请重试...${RESET}" ;;
    esac
    read -p "按回车返回菜单..." enter
    menu
}

start_service() {
    echo -e "${GREEN}🚀 启动 Dujiaoka 服务中...${RESET}"
    docker-compose -f $COMPOSE_FILE up -d

    # 检测 APP_KEY
    APP_KEY=$(grep '^APP_KEY=' $ENV_FILE | cut -d '=' -f2)
    if [ -z "$APP_KEY" ]; then
        echo -e "${GREEN}⚙️ 生成 APP_KEY...${RESET}"
        docker-compose -f $COMPOSE_FILE exec -T web php artisan key:generate
        echo -e "${GREEN}✅ APP_KEY 已生成并写入 .env${RESET}"
    else
        echo -e "${GREEN}🔑 APP_KEY 已存在，跳过生成${RESET}"
    fi

    echo -e "${GREEN}✅ 服务已启动${RESET}"
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

menu
EOF

chmod +x menu.sh

# 6. 自动启动服务并生成 APP_KEY
echo -e "${GREEN}🚀 自动启动服务并检测 APP_KEY...${RESET}"
docker-compose -f docker-compose.yml up -d

APP_KEY=$(grep '^APP_KEY=' .env | cut -d '=' -f2)
if [ -z "$APP_KEY" ]; then
    echo -e "${GREEN}⚙️ 生成 APP_KEY...${RESET}"
    docker-compose -f docker-compose.yml exec -T web php artisan key:generate
    echo -e "${GREEN}✅ APP_KEY 已生成并写入 .env${RESET}"
else
    echo -e "${GREEN}🔑 APP_KEY 已存在，跳过生成${RESET}"
fi

echo -e "${GREEN}✅ 文件已生成，可执行 ./menu.sh 管理 Dujiaoka${RESET}"
