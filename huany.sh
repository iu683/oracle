#!/bin/bash

# =========================================
# 系统更新源切换菜单脚本（Debian 安全源修正 + 自动更新缓存）
# 支持 Ubuntu / Debian / CentOS
# =========================================

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

# 获取系统信息
source /etc/os-release

# 获取系统 codename（Ubuntu/Debian）
get_codename() {
    if command -v lsb_release >/dev/null 2>&1; then
        codename=$(lsb_release -cs)
    elif [ -n "$VERSION_CODENAME" ]; then
        codename=$VERSION_CODENAME
    elif [ -n "$VERSION_ID" ]; then
        case "$ID" in
            ubuntu)
                case "$VERSION_ID" in
                    "18.04") codename="bionic" ;;
                    "20.04") codename="focal" ;;
                    "22.04") codename="jammy" ;;
                    *) codename="focal" ;;
                esac
                ;;
            debian)
                case "$VERSION_ID" in
                    "10") codename="buster" ;;
                    "11") codename="bullseye" ;;
                    "12") codename="bookworm" ;;
                    *) codename="bookworm" ;;
                esac
                ;;
        esac
    else
        codename="stable"
    fi
}

get_codename

# 定义更新源
aliyun_ubuntu_source="http://mirrors.aliyun.com/ubuntu/"
official_ubuntu_source="http://archive.ubuntu.com/ubuntu/"
tsinghua_ubuntu_source="https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"

aliyun_debian_source="http://mirrors.aliyun.com/debian/"
official_debian_source="http://deb.debian.org/debian/"
tsinghua_debian_source="https://mirrors.tuna.tsinghua.edu.cn/debian/"

aliyun_centos_source="http://mirrors.aliyun.com/centos/"
official_centos_source="http://mirror.centos.org/centos/"
tsinghua_centos_source="https://mirrors.tuna.tsinghua.edu.cn/centos/"

# 备份当前源
backup_sources() {
    case "$ID" in
        ubuntu|debian)
            cp /etc/apt/sources.list /etc/apt/sources.list.bak
            ;;
        centos)
            cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak
            ;;
    esac
    echo -e "${GREEN}已备份当前更新源${RESET}"
}

# 还原初始源
restore_sources() {
    case "$ID" in
        ubuntu|debian)
            if [ -f /etc/apt/sources.list.bak ]; then
                cp /etc/apt/sources.list.bak /etc/apt/sources.list
                echo -e "${GREEN}已还原初始更新源${RESET}"
            else
                echo -e "${RED}备份文件不存在，无法还原${RESET}"
            fi
            ;;
        centos)
            if [ -f /etc/yum.repos.d/CentOS-Base.repo.bak ]; then
                cp /etc/yum.repos.d/CentOS-Base.repo.bak /etc/yum.repos.d/CentOS-Base.repo
                echo -e "${GREEN}已还原初始更新源${RESET}"
            else
                echo -e "${RED}备份文件不存在，无法还原${RESET}"
            fi
            ;;
    esac
}

# 切换 Ubuntu/Debian 源
switch_apt_source() {
    local new_source="$1"
    local source_name="$2"

    if [ "$ID" = "debian" ]; then
        # Debian 不包含 backports
        cat >/etc/apt/sources.list <<EOF
deb ${new_source} ${codename} main contrib non-free
deb ${new_source} ${codename}-updates main contrib non-free
deb http://security.debian.org/debian-security ${codename}-security main contrib non-free
EOF
    elif [ "$ID" = "ubuntu" ]; then
        # Ubuntu 保留 backports
        cat >/etc/apt/sources.list <<EOF
deb ${new_source} ${codename} main restricted universe multiverse
deb ${new_source} ${codename}-updates main restricted universe multiverse
deb ${new_source} ${codename}-backports main restricted universe multiverse
deb ${new_source} ${codename}-security main restricted universe multiverse
EOF
    fi

    echo -e "${GREEN}已切换到 ${source_name} 源（${codename}）${RESET}"
}


# 切换 CentOS 源（支持多个 repo 区块）
switch_yum_source() {
    local new_source="$1"
    local source_name="$2"
    for repo_file in /etc/yum.repos.d/*.repo; do
        sed -i "s|^baseurl=.*$|baseurl=${new_source}\$releasever|g" "$repo_file"
    done
    echo -e "${GREEN}已切换到 ${source_name} 源${RESET}"
}

# 更新缓存
update_cache() {
    case "$ID" in
        ubuntu|debian)
            echo -e "${YELLOW}正在更新 apt 缓存...${RESET}"
            apt update -y >/dev/null 2>&1
            ;;
        centos)
            echo -e "${YELLOW}正在生成 yum 缓存...${RESET}"
            yum makecache fast -y >/dev/null 2>&1
            ;;
    esac
    echo -e "${GREEN}更新完成${RESET}"
}

# 暂停函数
pause() {
    read -rp "$(echo -e "${YELLOW}按回车键继续...${RESET}")"
}

# 显示国内/国外推荐源列表
show_recommended_sources() {
    clear
    echo -e "${GREEN}正在获取国内推荐源列表...${RESET}"
    bash <(curl -sSL https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh)
    pause
    clear
    echo -e "${GREEN}正在获取国外推荐源列表...${RESET}"
    bash <(curl -sSL https://linuxmirrors.cn/main.sh) --abroad
    pause
}

# 主菜单
while true; do
    clear
    echo -e "${GREEN}==========================="
    case "$ID" in
        ubuntu) echo -e "Ubuntu 更新源切换菜单" ;;
        debian) echo -e "Debian 更新源切换菜单" ;;
        centos) echo -e "CentOS 更新源切换菜单" ;;
    esac
    echo -e "==========================="
    echo -e "1. 切换到阿里云源并更新缓存"
    echo -e "2. 切换到官方源并更新缓存"
    echo -e "3. 切换到清华源并更新缓存"
    echo -e "4. 备份当前更新源"
    echo -e "5. 还原初始更新源并更新缓存"
    echo -e "6. 国内/国外推荐源列表"
    echo -e "0. 退出"
    echo -e "---------------------------${RESET}"
    
    read -rp "$(echo -e "${GREEN}请选择操作: ${RESET}")" choice

    case $choice in
        1)
            backup_sources
            case "$ID" in
                ubuntu) switch_apt_source "$aliyun_ubuntu_source" "阿里云" ;;
                debian) switch_apt_source "$aliyun_debian_source" "阿里云" ;;
                centos) switch_yum_source "$aliyun_centos_source" "阿里云" ;;
            esac
            update_cache
            pause
            ;;
        2)
            backup_sources
            case "$ID" in
                ubuntu) switch_apt_source "$official_ubuntu_source" "官方" ;;
                debian) switch_apt_source "$official_debian_source" "官方" ;;
                centos) switch_yum_source "$official_centos_source" "官方" ;;
            esac
            update_cache
            pause
            ;;
        3)
            backup_sources
            case "$ID" in
                ubuntu) switch_apt_source "$tsinghua_ubuntu_source" "清华" ;;
                debian) switch_apt_source "$tsinghua_debian_source" "清华" ;;
                centos) switch_yum_source "$tsinghua_centos_source" "清华" ;;
            esac
            update_cache
            pause
            ;;
        4)
            backup_sources
            pause
            ;;
        5)
            restore_sources
            update_cache
            pause
            ;;
        6)
            show_recommended_sources
            ;;
        0)
            echo -e "${GREEN}退出脚本...${RESET}"
            break
            ;;
        *)
            echo -e "${RED}无效选择，请重新输入${RESET}"
            pause
            ;;
    esac
done
