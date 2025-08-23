#!/bin/bash
set -e

GREEN="\033[32m"
RESET="\033[0m"

if [ "$EUID" -ne 0 ]; then
    echo "请用 root 运行此脚本"
    exit 1
fi

echo -e "${GREEN}=== VPS 设置中文环境 (zh_CN.UTF-8) ===${RESET}"

apt-get update -y
apt-get install -y locales fonts-wqy-microhei fonts-wqy-zenhei

locale-gen zh_CN.UTF-8
update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8

cat > /etc/default/locale <<EOF
LANG=zh_CN.UTF-8
LC_ALL=zh_CN.UTF-8
EOF

echo -e "${GREEN}配置完成，请重新登录 VPS 查看效果！${RESET}"
locale
