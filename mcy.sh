#!/bin/bash
set -e

# ================== 配置 ==================
DOWNLOAD_URL="https://wiki.mcy.im/download.php?q=27"   # 安装包下载地址
INSTALL_DIR="/www/wwwroot/mcy-shop"                    # 安装目录
ZIP_FILE="/tmp/mcy-shop.zip"                           # 临时文件路径

# ================== 检查 root ==================
if [ "$EUID" -ne 0 ]; then
  echo -e "\033[31m请以 root 用户运行此脚本！\033[0m"
  exit 1
fi

# ================== 创建目录 ==================
mkdir -p $INSTALL_DIR
cd /www/wwwroot/

# ================== 下载安装包 ==================
echo -e "\033[33m开始下载安装包...\033[0m"
curl -L -o $ZIP_FILE $DOWNLOAD_URL

# ================== 解压 ==================
echo -e "\033[33m解压到 $INSTALL_DIR ...\033[0m"
unzip -o $ZIP_FILE -d $INSTALL_DIR

# ================== 赋权 ==================
echo -e "\033[33m设置权限...\033[0m"
chmod 777 $INSTALL_DIR/bin $INSTALL_DIR/console.sh || true
chmod 777 $INSTALL_DIR/bin/console.sh || true

# ================== 执行安装 ==================
cd $INSTALL_DIR
echo -e "\033[32m开始执行安装程序...\033[0m"
echo -e "\033[33m⚠️ 注意：此窗口不能关闭，关闭会导致安装中断！\033[0m"
./bin index.php
