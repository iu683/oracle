#!/bin/bash

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

INSTALL_DIR="/www/wwwroot/dujiaoka"
SITE_DOMAIN=""
SSL_EMAIL=""

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用 root 用户运行脚本${RESET}"
        exit 1
    fi
}

install_dependencies() {
    echo -e "${YELLOW}安装基础依赖...${RESET}"
    if [ -f /etc/redhat-release ]; then
        yum update -y
        yum install wget git unzip epel-release nginx mariadb-server redis supervisor -y
        yum install php74 php74-cli php74-fpm php74-mbstring php74-mysqlnd php74-zip php74-gd php74-xml php74-bcmath php74-curl -y
        systemctl enable nginx php-fpm mariadb redis supervisord
        systemctl start nginx php-fpm mariadb redis supervisord
    else
        apt update -y
        apt install wget git unzip software-properties-common -y
        add-apt-repository -y ppa:ondrej/php
        apt update -y
        apt install nginx php7.4 php7.4-cli php7.4-fpm php7.4-mbstring php7.4-mysql php7.4-zip php7.4-gd php7.4-xml php7.4-bcmath php7.4-curl mariadb-server redis-server supervisor -y
        systemctl enable nginx php7.4-fpm mariadb redis-server supervisor
        systemctl start nginx php7.4-fpm mariadb redis-server supervisor
    fi

    # 安装 Composer
    if ! command -v composer &>/dev/null; then
        echo -e "${YELLOW}安装 Composer...${RESET}"
        php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
        php composer-setup.php
        php -r "unlink('composer-setup.php');"
        mv composer.phar /usr/local/bin/composer
    fi
}

check_php_cli() {
    echo -e "${YELLOW}检查 PHP CLI 环境...${RESET}"

    if ! command -v php &>/dev/null; then
        echo -e "${RED}PHP CLI 未安装，请先安装 PHP 7.4${RESET}"
        exit 1
    fi

    php -v >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}PHP CLI 不可用，请检查安装${RESET}"
        exit 1
    fi

    DISABLED=$(php -r 'echo implode(",", array_intersect(["putenv","proc_open","pcntl_signal","pcntl_alarm"], array_map("trim", explode(",", ini_get("disable_functions")))));')
    if [ -n "$DISABLED" ]; then
        echo -e "${RED}PHP 禁用了以下必需函数: $DISABLED${RESET}"
        echo -e "${YELLOW}请在 php.ini 中启用这些函数后重试${RESET}"
        exit 1
    fi

    echo -e "${GREEN}PHP CLI 环境检查通过！${RESET}"
}

install_dujiaoka() {
    read -p "请输入项目安装目录 [${INSTALL_DIR}]: " DIR
    INSTALL_DIR=${DIR:-$INSTALL_DIR}
    mkdir -p "$INSTALL_DIR"
    git clone https://github.com/assimon/dujiaoka.git "$INSTALL_DIR"
    cd "$INSTALL_DIR" || return
    composer install

    read -p "请输入数据库地址 [127.0.0.1]: " DB_HOST
    DB_HOST=${DB_HOST:-127.0.0.1}
    read -p "请输入数据库端口 [3306]: " DB_PORT
    DB_PORT=${DB_PORT:-3306}
    read -p "请输入数据库名 [dujiaoka]: " DB_NAME
    DB_NAME=${DB_NAME:-dujiaoka}
    read -p "请输入数据库用户名 [root]: " DB_USER
    DB_USER=${DB_USER:-root}
    read -sp "请输入数据库密码: " DB_PASS
    echo
    read -p "请输入 Redis 地址 [127.0.0.1]: " REDIS_HOST
    REDIS_HOST=${REDIS_HOST:-127.0.0.1}
    read -p "请输入 Redis 端口 [6379]: " REDIS_PORT
    REDIS_PORT=${REDIS_PORT:-6379}
    read -sp "请输入 Redis 密码（无密码直接回车）: " REDIS_PASS
    echo
    read -p "请输入网站域名（需解析到当前服务器）: " SITE_DOMAIN

    cat > .env <<EOF
APP_NAME=Dujiaoka
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=https://$SITE_DOMAIN

DB_CONNECTION=mysql
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_DATABASE=$DB_NAME
DB_USERNAME=$DB_USER
DB_PASSWORD=$DB_PASS

REDIS_HOST=$REDIS_HOST
REDIS_PASSWORD=$REDIS_PASS
REDIS_PORT=$REDIS_PORT
EOF

    php artisan key:generate
    php artisan migrate --force
    php artisan db:seed --force

    configure_nginx
    enable_https
    configure_supervisor
}

configure_nginx() {
    echo -e "${GREEN}配置 Nginx 虚拟主机...${RESET}"
    if [ -f /etc/redhat-release ]; then
        NGINX_CONF="/etc/nginx/conf.d/dujiaoka.conf"
    else
        NGINX_CONF="/etc/nginx/sites-available/dujiaoka"
    fi

    cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $SITE_DOMAIN;

    root $INSTALL_DIR/public;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include fastcgi_params;
EOF

    if [ -f /etc/redhat-release ]; then
        echo "        fastcgi_pass 127.0.0.1:9000;" >> "$NGINX_CONF"
    else
        echo "        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;" >> "$NGINX_CONF"
    fi

    cat >> "$NGINX_CONF" <<EOF
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    if [ ! -f /etc/redhat-release ]; then
        ln -s /etc/nginx/sites-available/dujiaoka /etc/nginx/sites-enabled/
    fi

    nginx -t && systemctl restart nginx
}

enable_https() {
    echo -e "${YELLOW}安装 Certbot 并申请 SSL...${RESET}"
    if [ -f /etc/redhat-release ]; then
        yum install -y certbot python3-certbot-nginx
    else
        apt install -y certbot python3-certbot-nginx
    fi

    read -p "请输入邮箱（用于 SSL 过期提醒）: " SSL_EMAIL
    certbot --nginx -d $SITE_DOMAIN --non-interactive --agree-tos -m $SSL_EMAIL
}

configure_supervisor() {
    echo -e "${YELLOW}配置 Supervisor 队列...${RESET}"
    if [ -f /etc/redhat-release ]; then
        SUPERVISOR_CONF="/etc/supervisord.d/dujiaoka-queue.ini"
    else
        SUPERVISOR_CONF="/etc/supervisor/conf.d/dujiaoka-queue.conf"
    fi

    cat > "$SUPERVISOR_CONF" <<EOF
[program:dujiaoka-queue]
command=php $INSTALL_DIR/artisan queue:work --sleep=3 --tries=3
autostart=true
autorestart=true
user=www-data
numprocs=1
redirect_stderr=true
stdout_logfile=/var/log/dujiaoka_queue.log
EOF

    supervisorctl reread
    supervisorctl update
    supervisorctl start dujiaoka-queue
}

uninstall_dujiaoka() {
    echo -e "${RED}正在卸载 Dujiaoka...${RESET}"
    systemctl stop nginx php-fpm mariadb redis supervisor 2>/dev/null
    rm -rf "$INSTALL_DIR"
    if [ -f /etc/redhat-release ]; then
        rm -f /etc/nginx/conf.d/dujiaoka.conf
        rm -f /etc/supervisord.d/dujiaoka-queue.ini
    else
        rm -f /etc/nginx/sites-available/dujiaoka
        rm -f /etc/nginx/sites-enabled/dujiaoka
        rm -f /etc/supervisor/conf.d/dujiaoka-queue.conf
    fi
    nginx -s reload 2>/dev/null
    supervisorctl reread
    supervisorctl update
    echo -e "${GREEN}卸载完成！${RESET}"
}

menu() {
    clear
    echo -e "${GREEN}=== Dujiaoka 管理菜单 ===${RESET}"
    echo -e "${GREEN}1) 安装/部署 Dujiaoka${RESET}"
    echo -e "${GREEN}2) 启用 HTTPS${RESET}"
    echo -e "${GREEN}3) 启动 Supervisor 队列${RESET}"
    echo -e "${GREEN}4) 停止 Supervisor 队列${RESET}"
    echo -e "${RED}5) 卸载 Dujiaoka${RESET}"
    echo -e "${YELLOW}0) 退出${RESET}"
    read -p "请选择操作: " choice

    case $choice in
        1) install_dependencies; check_php_cli; install_dujiaoka ;;
        2) enable_https ;;
        3) supervisorctl start dujiaoka-queue ;;
        4) supervisorctl stop dujiaoka-queue ;;
        5) uninstall_dujiaoka ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选择${RESET}" ;;
    esac
}

check_root
while true; do
    menu
    read -p "按回车返回菜单..."
done
