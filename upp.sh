#!/bin/bash

# ==========================================
# 一键系统更新 & 常用依赖安装 & 修复 APT 源（跨发行版）
# ==========================================

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

# 检查是否 root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}❌ 请使用 root 用户运行此脚本${RESET}"
    exit 1
fi

# =============================
# 各发行版依赖包列表
# =============================
deps_debian=(curl wget git net-tools lsof tar unzip rsync pv sudo netcat-openbsd htop)
deps_rhel=(curl wget git net-tools lsof tar unzip rsync pv sudo nmap-ncat htop)
deps_fedora=(curl wget git net-tools lsof tar unzip rsync pv sudo nmap-ncat htop)
deps_alpine=(curl wget git net-tools lsof tar unzip rsync pv sudo netcat-openbsd htop)

# =============================
# 检查并安装依赖
# =============================
check_and_install() {
    local check_cmd="$1"
    local install_cmd="$2"
    shift 2
    local pkgs=("$@")
    local missing=()

    # 先单独检查命令是否已存在
    if command -v nc >/dev/null 2>&1; then
        echo -e "${GREEN}✔ 已安装: nc${RESET}"
        pkgs=("${pkgs[@]/netcat-openbsd/}" "${pkgs[@]/nmap-ncat/}")
    fi
    if command -v htop >/dev/null 2>&1; then
        echo -e "${GREEN}✔ 已安装: htop${RESET}"
        pkgs=("${pkgs[@]/htop/}")
    fi

    # 遍历剩余依赖
    for pkg in "${pkgs[@]}"; do
        [[ -z "$pkg" ]] && continue
        if ! eval "$check_cmd \"$pkg\"" &>/dev/null; then
            missing+=("$pkg")
        else
            echo -e "${GREEN}✔ 已安装: $pkg${RESET}"
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}👉 安装缺失依赖: ${missing[*]}${RESET}"
        eval "$install_cmd \"\${missing[@]}\""
    fi
}

# =============================
# 清理重复 Docker 源（仅 Debian/Ubuntu）
# =============================
fix_duplicate_docker_sources() {
    echo -e "${YELLOW}🔍 检查重复 Docker APT 源...${RESET}"
    local docker_sources
    docker_sources=$(grep -rl "download.docker.com" /etc/apt/sources.list.d/ 2>/dev/null || true)
    if [ "$(echo "$docker_sources" | grep -c .)" -gt 1 ]; then
        echo -e "${RED}⚠️ 检测到重复 Docker 源:${RESET}"
        echo "$docker_sources"
        for f in $docker_sources; do
            if [[ "$f" == *"archive_uri"* ]]; then
                rm -f "$f"
                echo -e "${GREEN}✔ 删除多余源: $f${RESET}"
            fi
        done
    else
        echo -e "${GREEN}✔ Docker 源正常${RESET}"
    fi
}

# =============================
# 修复 Debian/Ubuntu 源兼容性
# =============================
fix_sources_for_version() {
    echo -e "${YELLOW}🔍 修复 sources.list 兼容性...${RESET}"
    local version="$1"
    local files
    files=$(grep -rl "deb" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null || true)
    for f in $files; do
        if [[ "$version" == "bullseye" ]]; then
            sed -i -r 's/\bnon-free(-firmware){0,3}\b/non-free/g' "$f"
            sed -i '/bullseye-backports/s/^/##/' "$f"
        fi
    done
    echo -e "${GREEN}✔ sources.list 已优化${RESET}"
}

# =============================
# 系统更新 & 依赖安装
# =============================
update_system() {
    echo -e "${GREEN}🔄 检测系统发行版并更新...${RESET}"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo -e "${YELLOW}👉 当前系统: $PRETTY_NAME${RESET}"

        case "$ID" in
            debian|ubuntu)
                fix_duplicate_docker_sources
                fix_sources_for_version "$VERSION_CODENAME"
                apt update -y
                apt full-upgrade -y
                check_and_install "dpkg -s" "apt install -y" "${deps_debian[@]}"
                ;;
            fedora)
                dnf upgrade --refresh -y
                check_and_install "rpm -q" "dnf install -y" "${deps_fedora[@]}"
                ;;
            centos|rhel)
                yum upgrade -y
                check_and_install "rpm -q" "yum install -y" "${deps_rhel[@]}"
                ;;
            alpine)
                apk update
                apk upgrade --available
                check_and_install "apk info -e" "apk add" "${deps_alpine[@]}"
                ;;
            *)
                echo -e "${RED}❌ 暂不支持的 Linux 发行版: $ID${RESET}"
                return 1
                ;;
        esac
    else
        echo -e "${RED}❌ 无法检测系统发行版 (/etc/os-release 不存在)${RESET}"
        return 1
    fi

    echo -e "${GREEN}✅ 系统更新和依赖安装完成！${RESET}"
}

# =============================
# 执行
# =============================
clear
update_system
echo -e "${GREEN}✅ 脚本执行完成！${RESET}"
