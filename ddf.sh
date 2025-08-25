#!/bin/bash

# ================== 颜色 ==================
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

CONTAINER_NAME="bepusdt"
IMAGE_NAME="v03413/bepusdt:latest"

# 默认路径
DEFAULT_CONF_PATH="/root/bepusdt/conf.toml"
DEFAULT_DB_PATH="/root/bepusdt/sqlite.db"

# ================== 检查 root ==================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行此脚本！${RESET}"
    exit 1
fi

# ================== 函数 ==================

check_port() {
    local port=$1
    while lsof -i :"$port" >/dev/null 2>&1; do
        echo -e "${YELLOW}端口 $port 已被占用，请输入新的端口: ${RESET}"
        read port
    done
    echo $port
}

start_container() {
    if [ "$(docker ps -a -q -f name=^/${CONTAINER_NAME}$)" ]; then
        echo -e "${YELLOW}容器 ${CONTAINER_NAME} 已存在${RESET}"
        echo "请选择操作："
        echo "1) 重启容器"
        echo "2) 更新镜像并重建容器"
        echo "3) 删除容器并重新创建"
        echo "0) 返回菜单"
        read -p "选择: " opt
        case $opt in
            1)
                docker restart ${CONTAINER_NAME} && echo -e "${GREEN}容器已重启${RESET}" ;;
            2)
                docker pull ${IMAGE_NAME}
                docker rm -f ${CONTAINER_NAME}
                echo -e "${GREEN}镜像已更新，容器已删除${RESET}" ;;
            3)
                docker rm -f ${CONTAINER_NAME} && echo -e "${GREEN}容器已删除${RESET}" ;;
            0)
                return ;;
            *)
                echo -e "${RED}无效选择，返回菜单${RESET}" ;;
        esac
    fi

    # 输入配置文件路径，支持默认
    read -p "请输入宿主机 conf.toml 配置文件路径 [默认: ${DEFAULT_CONF_PATH}]: " CONF_PATH
    CONF_PATH=${CONF_PATH:-$DEFAULT_CONF_PATH}

    # 输入数据库路径，支持默认
    read -p "请输入宿主机数据库文件路径 [默认: ${DEFAULT_DB_PATH}]: " DB_PATH
    DB_PATH=${DB_PATH:-$DEFAULT_DB_PATH}

    # 输入端口，支持默认 8080
    read -p "请输入宿主机映射端口 [默认: 8080]: " PORT
    PORT=${PORT:-8080}
    PORT=$(check_port $PORT)
    # 检查文件
    if [ ! -f "$CONF_PATH" ]; then
        echo -e "${RED}配置文件不存在: $CONF_PATH${RESET}"
        return
    fi

    if [ ! -f "$DB_PATH" ]; then
        echo -e "${YELLOW}数据库文件不存在，启动后容器会自动创建: $DB_PATH${RESET}"
    fi

    # 启动容器
    docker run -d --name ${CONTAINER_NAME} --restart=unless-stopped \
    -p ${PORT}:8080 \
    -v ${CONF_PATH}:/usr/local/bepusdt/conf.toml \
    -v ${DB_PATH}:/var/lib/bepusdt/sqlite.db \
    ${IMAGE_NAME}

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}容器已启动成功！端口: ${PORT}${RESET}"
    else
        echo -e "${RED}容器启动失败，请检查配置！${RESET}"
    fi
}

stop_container() {
    docker stop ${CONTAINER_NAME} && echo -e "${GREEN}容器已停止${RESET}"
}

restart_container() {
    docker restart ${CONTAINER_NAME} && echo -e "${GREEN}容器已重启${RESET}"
}

remove_container() {
    if [ "$(docker ps -a -q -f name=^/${CONTAINER_NAME}$)" ]; then
        read -p "确认删除容器 ${CONTAINER_NAME} 并删除挂载的数据库文件吗？[y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            docker rm -f ${CONTAINER_NAME} && echo -e "${GREEN}容器已删除${RESET}"
            # 删除数据库文件
            if [ -f "$DB_PATH" ]; then
                rm -f "$DB_PATH" && echo -e "${GREEN}数据库文件已删除: $DB_PATH${RESET}"
            fi
            # 删除配置文件（可选，通常不删除以防误操作）
            # if [ -f "$CONF_PATH" ]; then
            #     rm -f "$CONF_PATH" && echo -e "${GREEN}配置文件已删除: $CONF_PATH${RESET}"
            # fi
        else
            echo "取消删除操作，返回菜单"
        fi
    else
        echo -e "${YELLOW}容器 ${CONTAINER_NAME} 不存在${RESET}"
    fi
}


status_container() {
    docker ps -a --filter "name=${CONTAINER_NAME}"
}

# ================== 菜单 ==================

while true; do
    echo -e "\n${GREEN}====== BEPUSDT 容器管理 ======${RESET}"
    echo -e "${GREEN}1) 启动容器 / 检测容器是否存在${RESET}"
    echo -e "${GREEN}2) 停止容器${RESET}"
    echo -e "${GREEN}3) 重启容器${RESET}"
    echo -e "${GREEN}4) 删除容器${RESET}"
    echo -e "${GREEN}5) 查看状态${RESET}"
    echo -e "${GREEN}0) 退出${RESET}"
    read -p "请选择操作: " choice

    case $choice in
        1) start_container ;;
        2) stop_container ;;
        3) restart_container ;;
        4) remove_container ;;
        5) status_container ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选择，返回菜单${RESET}" ;;
    esac
done
