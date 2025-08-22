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

echo -e "${GREEN}✅ 部署完成${RESET}"
