#!/bin/bash
set -e

# ================== 配置 ==================
DOWNLOAD_URL="https://wiki.mcy.im/download.php?q=27"   # 安装包下载地址
INSTALL_DIR="/www/wwwroot/mcy-shop"                    # 安装目录
ZIP_FILE="/tmp/mcy-shop.zip"                           # 临时文件路径
SERVICE_CMD="php index.php"                            # 启动命令

# ================== 颜色 ==================
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# ================== 检查 root ==================
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请以 root 用户运行此脚本！${RESET}"
  exit 1
fi

# ================== 检查系统类型 ==================
detect_os() {
  if [ -f /etc/debian_version ]; then
    OS="debian"
  elif [ -f /etc/alpine-release ]; then
    OS="alpine"
  elif [ -f /etc/redhat-release ]; then
    OS="centos"
  else
    echo -e "${RED}不支持的系统！${RESET}"
    exit 1
  fi
}

# ================== 安装 PHP ==================
install_php() {
  if command -v php &>/dev/null; then
    echo -e "${GREEN}PHP 已安装: $(php -v | head -n1)${RESET}"
    return
  fi

  echo -e "${YELLOW}检测到 PHP 未安装，开始安装...${RESET}"
  case $OS in
    debian)
      apt update
      apt install -y php php-cli php-mysql unzip curl
      ;;
    centos)
      yum install -y php php-cli php-mysql unzip curl
      ;;
    alpine)
      apk add --no-cache php php-cli php-mysqli unzip curl
      ;;
  esac
  echo -e "${GREEN}PHP 安装完成！${RESET}"
}

# ================== 安装程序 ==================
install_app() {
  mkdir -p $INSTALL_DIR
  echo -e "${YELLOW}开始下载安装包...${RESET}"
  curl -L -o $ZIP_FILE $DOWNLOAD_URL
  echo -e "${YELLOW}解压到 $INSTALL_DIR ...${RESET}"
  unzip -o $ZIP_FILE -d $INSTALL_DIR
  chmod -R 755 $INSTALL_DIR
  rm -f $ZIP_FILE
  echo -e "${GREEN}安装完成！${RESET}"
}

# ================== 卸载程序 ==================
uninstall_app() {
  echo -e "${RED}正在卸载 $INSTALL_DIR ...${RESET}"
  pkill -f "$SERVICE_CMD" || true
  rm -rf $INSTALL_DIR
  echo -e "${GREEN}卸载完成！${RESET}"
}

# ================== 重启程序 ==================
restart_app() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}程序未安装！${RESET}"
    return
  fi
  echo -e "${YELLOW}正在重启程序...${RESET}"
  pkill -f "$SERVICE_CMD" || true
  cd $INSTALL_DIR
  $SERVICE_CMD &
  echo -e "${GREEN}重启完成！${RESET}"
}

# ================== 菜单 ==================
detect_os
install_php

while true; do
  echo -e "${GREEN}====== MCY-SHOP 管理脚本 ======${RESET}"
  echo -e "1) 安装"
  echo -e "2) 卸载"
  echo -e "3) 重启"
  echo -e "0) 退出"
  echo -n -e "${YELLOW}请选择: ${RESET}"
  read opt
  case $opt in
    1) install_app; echo -e "${YELLOW}开始执行安装程序...${RESET}"; cd $INSTALL_DIR; $SERVICE_CMD ;;
    2) uninstall_app ;;
    3) restart_app ;;
    0) exit 0 ;;
    *) echo -e "${RED}无效选择！${RESET}" ;;
  esac
  echo ""
done
