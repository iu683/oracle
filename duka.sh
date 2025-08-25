#!/bin/bash
set -e

# ================== 配置 ==================
DOWNLOAD_URL="https://wiki.mcy.im/download.php?q=27"   # 安装包下载地址
INSTALL_DIR="/www/wwwroot/mcy-shop"                    # 安装目录
ZIP_FILE="/tmp/mcy-shop.zip"                           # 临时文件路径
SERVICE_CMD="php index.php"                            # 安装启动命令

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

# ================== 功能函数 ==================
install_app() {
    echo -e "${YELLOW}开始下载安装包...${RESET}"
    mkdir -p $INSTALL_DIR
    curl -L -o $ZIP_FILE $DOWNLOAD_URL
    echo -e "${YELLOW}解压到 $INSTALL_DIR...${RESET}"
    unzip -o $ZIP_FILE -d $INSTALL_DIR
    chmod -R 755 $INSTALL_DIR
    chmod +x $INSTALL_DIR/bin/* || true
    rm -f $ZIP_FILE
    echo -e "${GREEN}安装完成！${RESET}"
    cd $INSTALL_DIR
    $SERVICE_CMD
}

uninstall_app() {
    echo -e "${RED}正在卸载...${RESET}"
    rm -rf $INSTALL_DIR
    echo -e "${GREEN}卸载完成！${RESET}"
}

restart_app() {
    echo -e "${YELLOW}正在重启...${RESET}"
    cd $INSTALL_DIR
    pkill -f "$SERVICE_CMD" || true
    $SERVICE_CMD &
    echo -e "${GREEN}已重启！${RESET}"
}

# ================== 菜单 ==================
while true; do
    echo -e "${GREEN}====== MCY-SHOP 管理脚本 ======${RESET}"
    echo -e "1) 安装"
    echo -e "2) 卸载"
    echo -e "3) 重启"
    echo -e "0) 退出"
    echo -n -e "${YELLOW}请选择: ${RESET}"
    read opt
    case $opt in
        1) install_app ;;
        2) uninstall_app ;;
        3) restart_app ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选择！${RESET}" ;;
    esac
    echo ""
done
