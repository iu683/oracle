#!/bin/bash
# SaveAny-Bot Docker 管理脚本（最终整合版）
# 功能：
# 1. 按1启动容器时可自定义挂载路径、Bot Token、用户ID
# 2. 批量添加用户并指定可用存储
# 3. 启动/停止/重启/日志/删除容器
# 4. 编辑配置文件
# 5. 卸载并删除所有数据

CONTAINER_NAME="saveany-bot"
IMAGE_NAME="ghcr.io/krau/saveany-bot:latest"
CONFIG_FILE_NAME="config.toml"
CONFIG_PATH_FILE="/root/.saveany_path"

GREEN="\033[32m"
RESET="\033[0m"

# ======== 功能函数 ========
check_container() { docker ps -a --format '{{.Names}}' | grep -w "$CONTAINER_NAME" >/dev/null 2>&1; }

# 启动容器，首次生成配置时输入自定义参数
start_bot() {
    # 检查配置文件
    if [ ! -f "$CONFIG_FILE" ]; then
        # 挂载目录
        echo -e "${GREEN}请输入挂载路径 (默认: /root/saveany):${RESET}"
        read -p ">>> " USER_PATH
        if [ -z "$USER_PATH" ]; then
            BASE_DIR="/root/saveany"
        else
            BASE_DIR="$USER_PATH"
        fi
        echo "$BASE_DIR" > "$CONFIG_PATH_FILE"
        DATA_DIR="$BASE_DIR/data"
        DOWNLOADS_DIR="$BASE_DIR/downloads"
        CACHE_DIR="$BASE_DIR/cache"
        CONFIG_FILE="$BASE_DIR/$CONFIG_FILE_NAME"
        mkdir -p "$DATA_DIR" "$DOWNLOADS_DIR" "$CACHE_DIR"

        # Telegram Token 和用户ID
        echo -e "${GREEN}请输入 Telegram Bot Token:${RESET}"
        read -p ">>> " BOT_TOKEN
        echo -e "${GREEN}请输入 Telegram 用户 ID:${RESET}"
        read -p ">>> " TELEGRAM_ID

        # 生成最简配置
        cat > "$CONFIG_FILE" <<EOF
# SaveAny-Bot 最简配置
workers = 4
retry = 3
threads = 4
stream = false

[telegram]
token = "$BOT_TOKEN"

[[storages]]
name = "本机存储"
type = "local"
enable = true
base_path = "./downloads"

[[users]]
id = $TELEGRAM_ID
storages = []
blacklist = true
EOF
        echo -e "${GREEN}已生成配置文件: $CONFIG_FILE${RESET}"
    else
        # 如果已有配置，则加载挂载路径
        BASE_DIR=$(cat "$CONFIG_PATH_FILE")
        DATA_DIR="$BASE_DIR/data"
        DOWNLOADS_DIR="$BASE_DIR/downloads"
        CACHE_DIR="$BASE_DIR/cache"
        CONFIG_FILE="$BASE_DIR/$CONFIG_FILE_NAME"
    fi

    # 启动容器
    if check_container; then
        echo -e "${GREEN}>>> 启动 $CONTAINER_NAME ...${RESET}"
        docker start "$CONTAINER_NAME"
    else
        echo -e "${GREEN}>>> 创建并启动容器 ...${RESET}"
        docker run -d \
            --name $CONTAINER_NAME \
            --restart unless-stopped \
            --network host \
            -v "$DATA_DIR:/app/data" \
            -v "$CONFIG_FILE:/app/config.toml" \
            -v "$DOWNLOADS_DIR:/app/downloads" \
            -v "$CACHE_DIR:/app/cache" \
            $IMAGE_NAME
    fi
}

stop_bot() { docker stop $CONTAINER_NAME; }
restart_bot() { docker restart $CONTAINER_NAME; }
logs_bot() { docker logs -f $CONTAINER_NAME; }
remove_bot() { docker rm -f $CONTAINER_NAME; }
edit_config() { nano "$CONFIG_FILE"; }

set_mount_path() {
    echo -e "${GREEN}请输入新的挂载路径:${RESET}"
    read -p ">>> " NEW_PATH
    if [ -n "$NEW_PATH" ]; then
        echo "$NEW_PATH" > "$CONFIG_PATH_FILE"
        echo -e "${GREEN}挂载路径已修改为: $NEW_PATH${RESET}"
        echo -e "${GREEN}请重新运行脚本以生效。${RESET}"
    fi
}

# ======== 批量添加用户并指定存储 ========
add_users() {
    echo -e "${GREEN}当前配置的存储列表:${RESET}"
    STORAGE_LIST=($(grep '^\[\[storages\]\]' -A 4 "$CONFIG_FILE" | grep 'name =' | awk -F'"' '{print $2}'))
    for i in "${!STORAGE_LIST[@]}"; do
        echo "$((i+1)). ${STORAGE_LIST[$i]}"
    done

    echo -e "${GREEN}请输入要添加的 Telegram 用户 ID (用空格分隔):${RESET}"
    read -a USER_IDS

    for UID in "${USER_IDS[@]}"; do
        echo -e "${GREEN}请选择该用户模式: 1.白名单 2.黑名单 (默认黑名单)${RESET}"
        read -p ">>> " MODE
        if [ "$MODE" == "1" ]; then
            BLACKLIST="false"
            echo -e "${GREEN}请选择该用户可用的存储编号（用空格分隔）:${RESET}"
            read -a STORAGE_IDX
            USER_STORAGES=()
            for IDX in "${STORAGE_IDX[@]}"; do
                IDX=$((IDX-1))
                if [ $IDX -ge 0 ] && [ $IDX -lt ${#STORAGE_LIST[@]} ]; then
                    USER_STORAGES+=("\"${STORAGE_LIST[$IDX]}\"")
                fi
            done
            STORAGE_LINE="storages = [$(IFS=,; echo "${USER_STORAGES[*]}")]"
        else
            BLACKLIST="true"
            STORAGE_LINE="storages = []"
        fi
        echo -e "\n[[users]]\nid = $UID\n$STORAGE_LINE\nblacklist = $BLACKLIST" >> "$CONFIG_FILE"
        echo -e "${GREEN}已添加用户 $UID (blacklist=$BLACKLIST, storages=${STORAGE_LINE})${RESET}"
    done
    echo -e "${GREEN}完成添加用户，可选择重启容器使配置生效。${RESET}"
}

# ======== 卸载并删除所有数据 ========
uninstall_bot() {
    echo -e "\033[31m警告: 该操作会删除容器和所有数据，无法恢复！\033[0m"
    read -p "确定要继续吗？(y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}>>> 停止并删除容器...${RESET}"
        docker rm -f $CONTAINER_NAME >/dev/null 2>&1

        echo -e "${GREEN}>>> 删除挂载目录及所有数据...${RESET}"
        if [ -d "$BASE_DIR" ]; then
            rm -rf "$BASE_DIR"
            echo -e "${GREEN}已删除目录: $BASE_DIR${RESET}"
        fi

        if [ -f "$CONFIG_PATH_FILE" ]; then
            rm -f "$CONFIG_PATH_FILE"
        fi

        echo -e "${GREEN}>>> 卸载完成，所有数据已清理。${RESET}"
        exit 0
    else
        echo "已取消卸载。"
    fi
}

# ======== 菜单 ========
while true; do
    clear
    echo -e "${GREEN}====== SaveAny-Bot 管理菜单 ======${RESET}"
    echo -e "${GREEN}1. 启动容器${RESET}"
    echo -e "${GREEN}2. 停止容器${RESET}"
    echo -e "${GREEN}3. 重启容器${RESET}"
    echo -e "${GREEN}4. 查看日志${RESET}"
    echo -e "${GREEN}5. 编辑配置文件 (config.toml)${RESET}"
    echo -e "${GREEN}6. 删除容器${RESET}"
    echo -e "${GREEN}7. 修改挂载目录${RESET}"
    echo -e "${GREEN}8. 添加 Telegram 用户${RESET}"
    echo -e "${GREEN}9. 卸载并删除所有数据${RESET}"
    echo -e "${GREEN}0. 退出${RESET}"
    echo -e "${GREEN}=================================${RESET}"
    read -p "请选择操作: " choice
    case $choice in
        1) start_bot ;;
        2) stop_bot ;;
        3) restart_bot ;;
        4) logs_bot ;;
        5) edit_config ;;
        6) remove_bot ;;
        7) set_mount_path ;;
        8) add_users ;;
        9) uninstall_bot ;;
        0) exit 0 ;;
        *) echo -e "${GREEN}无效选项${RESET}" ;;
    esac
    echo -e "\n按任意键返回菜单..."
    read -n 1
done
