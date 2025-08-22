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

echo -e "${GREEN}✅ 部署完成${RESET}"
