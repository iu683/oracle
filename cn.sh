#!/bin/bash
set -e

GREEN="\033[32m"
RESET="\033[0m"

if [ "$EUID" -ne 0 ]; then
    echo "请用 root 运行此脚本"
    exit 1
fi

echo -e "${GREEN}=== VPS 设置中文环境 (zh_CN.UTF-8) ===${RESET}"

# 注释掉无效 backports 源
sed -i.bak '/-backports/ s/^/#/' /etc/apt/sources.list

# 更新系统包索引
apt-get update -y

# 安装必要包
apt-get install -y locales fonts-wqy-microhei fonts-wqy-zenhei

# 确保 /etc/locale.gen 含有 zh_CN.UTF-8
grep -qxF "zh_CN.UTF-8 UTF-8" /etc/locale.gen || echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen

# 生成 locale
locale-gen

# 设置系统默认语言
update-locale LANG=zh_CN.UTF-8

# 立即生效当前 shell
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
source /etc/default/locale

echo -e "${GREEN}✅ 中文环境已配置完成${RESET}"
locale
