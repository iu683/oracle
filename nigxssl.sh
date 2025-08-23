#!/bin/bash
set -e

# 颜色定义
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# 检查是否 root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请以 root 用户运行此脚本！${RESET}"
  exit 1
fi

# 需要开放的端口
REQUIRED_PORTS=(80 443)

# 防火墙配置函数
configure_firewall() {
  echo -e "${YELLOW}检测并配置防火墙以开放必要端口...${RESET}"

  if command -v ufw >/dev/null 2>&1; then
    echo "检测到 ufw"
    for port in "${REQUIRED_PORTS[@]}"; do
      if ! ufw status | grep -qw "$port"; then
        ufw allow "$port"
        echo "开放端口 $port"
      fi
    done
    return
  fi

  if systemctl is-active --quiet firewalld; then
    echo "检测到 firewalld"
    for port in "${REQUIRED_PORTS[@]}"; do
      if ! firewall-cmd --list-ports | grep -qw "${port}/tcp"; then
        firewall-cmd --permanent --add-port=${port}/tcp
        echo "开放端口 $port"
      fi
    done
    firewall-cmd --reload
    return
  fi

  if command -v iptables >/dev/null 2>&1; then
    echo "检测到 iptables"
    for port in "${REQUIRED_PORTS[@]}"; do
      if ! iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
        echo "开放端口 $port"
      fi
    done
    if command -v netfilter-persistent >/dev/null 2>&1; then
      netfilter-persistent save
    elif command -v service >/dev/null 2>&1; then
      service iptables save
    fi
    return
  fi

  echo -e "${YELLOW}未检测到防火墙工具，默认所有端口已开放。${RESET}"
}

# 确保 sites-enabled 被包含
ensure_nginx_include() {
  if ! grep -q "sites-enabled" /etc/nginx/nginx.conf; then
    sed -i '/http {/a \    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
    echo "已补充 include /etc/nginx/sites-enabled/*; 到 nginx.conf"
  fi
}

# 安装函数
install_nginx() {
  echo -e "${GREEN}安装 Nginx 和 Certbot...${RESET}"
  apt update && apt upgrade -y
  apt install -y nginx certbot python3-certbot-nginx

  mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
  configure_firewall
  ensure_nginx_include

  systemctl enable --now nginx

  echo -ne "${GREEN}请输入邮箱地址: ${RESET}"
  read EMAIL
  echo -ne "${GREEN}请输入域名 (example.com): ${RESET}"
  read DOMAIN
  echo -ne "${GREEN}请输入反代目标 (http://localhost:3000): ${RESET}"
  read TARGET

  CONFIG_PATH="/etc/nginx/sites-available/$DOMAIN"
  ENABLED_PATH="/etc/nginx/sites-enabled/$DOMAIN"

  cat > "$CONFIG_PATH" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass $TARGET;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

  ln -sf "$CONFIG_PATH" "$ENABLED_PATH"
  nginx -t && systemctl reload nginx

  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" || {
    echo -e "${RED}证书申请失败，请检查域名解析！${RESET}"
    exit 1
  }

  systemctl enable --now certbot.timer
  echo -e "${GREEN}安装完成！访问: https://$DOMAIN${RESET}"
  systemctl list-timers | grep certbot
}

# 添加配置
add_config() {
  echo -ne "${GREEN}请输入域名: ${RESET}"
  read DOMAIN
  echo -ne "${GREEN}请输入反代目标: ${RESET}"
  read TARGET
  echo -ne "${GREEN}请输入邮箱地址: ${RESET}"
  read EMAIL

  CONFIG_PATH="/etc/nginx/sites-available/$DOMAIN"
  ENABLED_PATH="/etc/nginx/sites-enabled/$DOMAIN"

  if [ -f "$CONFIG_PATH" ]; then
    echo -e "${YELLOW}配置已存在: $DOMAIN${RESET}"
    return
  fi

  cat > "$CONFIG_PATH" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass $TARGET;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

  ln -sf "$CONFIG_PATH" "$ENABLED_PATH"
  nginx -t && systemctl reload nginx

  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL"
  echo -e "${GREEN}添加完成！访问: https://$DOMAIN${RESET}"
}

# 修改配置
modify_config() {
  ls /etc/nginx/sites-available/
  echo -ne "${GREEN}请输入要修改的域名: ${RESET}"
  read DOMAIN
  CONFIG_PATH="/etc/nginx/sites-available/$DOMAIN"

  [ ! -f "$CONFIG_PATH" ] && echo "配置不存在！" && return

  echo -ne "${GREEN}请输入新反代目标: ${RESET}"
  read NEW_TARGET
  echo -ne "${GREEN}是否更新邮箱 (y/n): ${RESET}"
  read choice
  if [[ "$choice" == "y" ]]; then
    echo -ne "${GREEN}新邮箱: ${RESET}"
    read NEW_EMAIL
  fi

  cat > "$CONFIG_PATH" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass $NEW_TARGET;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

  nginx -t && systemctl reload nginx
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "${NEW_EMAIL:-admin@$DOMAIN}"

  echo -e "${GREEN}修改完成！访问: https://$DOMAIN${RESET}"
}

# 卸载
uninstall_nginx() {
  echo -ne "${GREEN}确定卸载 Nginx 和配置? (y/n): ${RESET}"
  read CONFIRM
  [[ "$CONFIRM" != "y" ]] && return

  systemctl stop nginx && systemctl disable nginx
  apt remove --purge -y nginx certbot python3-certbot-nginx
  rm -rf /etc/nginx/sites-available /etc/nginx/sites-enabled

  systemctl disable --now certbot.timer || true

  echo -e "${GREEN}Nginx 已卸载${RESET}"
}

# 菜单
while true; do
  echo -e "${GREEN}====== Nginx 管理脚本 ======${RESET}"
  echo -e "${GREEN}1) 安装 Nginx + 反代 + TLS${RESET}"
  echo -e "${GREEN}2) 添加新的反代配置${RESET}"
  echo -e "${GREEN}3) 修改现有配置${RESET}"
  echo -e "${GREEN}4) 卸载 Nginx${RESET}"
  echo -e "${GREEN}0) 退出${RESET}"
  echo -ne "${GREEN}请选择 [0-4]: ${RESET}"
  read choice

  case $choice in
    1) install_nginx ;;
    2) add_config ;;
    3) modify_config ;;
    4) uninstall_nginx ;;
    0) exit 0 ;;
    *) echo -e "${RED}无效选项${RESET}" ;;
  esac
  echo ""
done
