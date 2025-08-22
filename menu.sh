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


echo -e "${GREEN}✅ 源码部署完成${RESET}"
