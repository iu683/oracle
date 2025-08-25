#!/bin/bash

# ================== 颜色定义 ==================
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# ================== 检查是否 root ==================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行此脚本！${RESET}"
    exit 1
fi

# ================== 安装目录 ==================
INSTALL_DIR="/www/wwwroot/mcy-shop"

# ================== 下载地址 ==================
DOWNLOAD_URL="https://wiki.mcy.im/download.php?q=27"

# ================== 开始安装 ==================
echo -e "${GREEN}开始下载最新版安装包...${RESET}"
mkdir -p "$INSTALL_DIR"
wget -O /tmp/mcy-latest.zip "$DOWNLOAD_URL"

echo -e "${GREEN}解压安装包到 $INSTALL_DIR ...${RESET}"
unzip -o /tmp/mcy-latest.zip -d "$INSTALL_DIR"

echo -e "${GREEN}设置程序权限...${RESET}"
chmod 777 "$INSTALL_DIR/bin" "$INSTALL_DIR/console.sh"

echo -e "${GREEN}进入安装程序目录...${RESET}"
cd "$INSTALL_DIR"

echo -e "${YELLOW}启动安装程序，请保持 SSH 窗口打开...${RESET}"
./bin index.php

echo -e "${GREEN}安装完成！${RESET}"
echo -e "${YELLOW}请使用浏览器访问：http://服务器IP:端口 完成网页安装${RESET}"

# ================== 管理指令提示 ==================
echo -e "${GREEN}安装完成后，可使用以下命令管理程序：${RESET}"
echo -e "${YELLOW}重启程序: mcy service.restart${RESET}"
echo -e "${YELLOW}卸载程序: mcy service.uninstall${RESET}"
