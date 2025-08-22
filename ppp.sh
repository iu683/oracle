#!/bin/bash
# =====================================
# PHP 7.4 + Composer 管理脚本（Debian 12 专用）
# 安装 / 卸载 / 检查关键函数
# =====================================

set -e

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo -e "${RED}无法识别系统类型${RESET}"
        exit 1
    fi
}

# ---------------- 安装 PHP7.4 + Composer ----------------
install_php() {
    detect_os
    echo -e "${GREEN}开始安装 PHP 7.4 和 Composer...${RESET}"

    if [[ "$OS" == "debian" || "$OS" == "ubuntu" ]]; then
        apt update
        apt install -y lsb-release ca-certificates apt-transport-https curl gnupg2 unzip
        # 添加 sury PHP 源
        echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
        curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/sury.gpg
        apt update
        apt install -y php7.4 php7.4-cli php7.4-fpm php7.4-mbstring php7.4-xml php7.4-mysql
    else
        echo -e "${RED}暂不支持该系统${RESET}"
        exit 1
    fi

    PHP_INI_PATH=$(php -r "echo php_ini_loaded_file();")
    echo -e "${GREEN}PHP 安装完成，版本如下:${RESET}"
    php -v

    # 安装 Composer
    echo -e "${YELLOW}开始安装 Composer...${RESET}"
    EXPECTED_SIGNATURE=$(curl -s https://composer.github.io/installer.sig)
    curl -sS https://getcomposer.org/installer -o composer-setup.php
    ACTUAL_SIGNATURE=$(php -r "echo hash_file('sha384', 'composer-setup.php');")

    if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]; then
        echo -e "${RED}Composer 校验失败${RESET}"
        rm composer-setup.php
        exit 1
    fi

    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm composer-setup.php

    echo -e "${GREEN}Composer 安装完成，版本如下:${RESET}"
    composer --version
}

# ---------------- 检查并修复关键函数 ----------------
check_fix_functions() {
    detect_os
    if ! command -v php >/dev/null 2>&1; then
        echo -e "${RED}PHP 未安装，请先安装 PHP${RESET}"
        return
    fi

    PHP_INI_PATH=$(php -r "echo php_ini_loaded_file();")
    echo -e "${YELLOW}检查关键函数是否可用...${RESET}"
    REQUIRED_FUNCS=("putenv" "proc_open" "pcntl_signal" "pcntl_alarm")
    DISABLED=$(php -r 'echo ini_get("disable_functions");')
    FIXED=0

    for func in "${REQUIRED_FUNCS[@]}"; do
        if [[ $DISABLED == *"$func"* ]]; then
            echo -e "${RED}函数 $func 被禁用，尝试修复...${RESET}"
            FIXED=1
            sed -i "s/\b$func\b//g" "$PHP_INI_PATH"
            sed -i 's/,,/,/g; s/disable_functions = ,/disable_functions = /g; s/disable_functions = $/disable_functions = /' "$PHP_INI_PATH"
        else
            echo -e "${GREEN}函数 $func 可用${RESET}"
        fi
    done

    if [ $FIXED -eq 1 ]; then
        echo -e "${YELLOW}已修改 php.ini，尝试重启 PHP-FPM...${RESET}"
        systemctl restart php7.4-fpm || echo -e "${RED}请手动重启 PHP-FPM${RESET}"
        echo -e "${GREEN}关键函数修复完成!${RESET}"
    else
        echo -e "${GREEN}所有关键函数均可用${RESET}"
    fi
}

# ---------------- 卸载 PHP + Composer ----------------
uninstall_php() {
    detect_os
    echo -e "${YELLOW}开始卸载 PHP 和 Composer...${RESET}"
    apt remove -y php7.4* composer
    apt autoremove -y
    rm -f /etc/apt/sources.list.d/php.list
    rm -f /etc/apt/trusted.gpg.d/sury.gpg
    apt update
    echo -e "${GREEN}卸载完成${RESET}"
}

# ---------------- 菜单 ----------------
while true; do
    echo -e "\n${GREEN}=== PHP 7.4 管理菜单 ===${RESET}"
    echo -e "1) 安装 PHP 7.4 + Composer"
    echo -e "2) 检查/修复关键函数 (putenv, proc_open, pcntl_signal, pcntl_alarm)"
    echo -e "3) 卸载 PHP + Composer"
    echo -e "0) 退出"
    read -p "请输入选项: " choice

    case $choice in
        1) install_php ;;
        2) check_fix_functions ;;
        3) uninstall_php ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项${RESET}" ;;
    esac
done
