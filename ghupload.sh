#!/bin/bash
# VPS <-> GitHub 工具 (固定上传/下载目录, 不清理临时目录, 支持多次上传/下载)

BASE_DIR="$HOME/ghupload"
CONFIG_FILE="$BASE_DIR/.ghupload_config"
LOG_FILE="$BASE_DIR/github_upload.log"

BIN_DIR="$HOME/bin"
INSTALL_PATH_UPPER="$BIN_DIR/G"
INSTALL_PATH_LOWER="$BIN_DIR/g"

UPLOAD_DIR="/root/github/upload"
DOWNLOAD_DIR="/root/github/download"

mkdir -p "$BASE_DIR" "$BIN_DIR" "$UPLOAD_DIR" "$DOWNLOAD_DIR"

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

REPO_URL=""
BRANCH="main"
COMMIT_PREFIX="VPS-Upload"
TG_BOT_TOKEN=""
TG_CHAT_ID=""

send_tg() {
    local MSG="$1"
    if [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
        curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
            -d chat_id="$TG_CHAT_ID" -d text="$MSG" >/dev/null || echo "⚠️ TG 消息发送失败"
    fi
}

save_config() {
    cat > "$CONFIG_FILE" <<EOC
REPO_URL="$REPO_URL"
BRANCH="$BRANCH"
COMMIT_PREFIX="$COMMIT_PREFIX"
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_CHAT_ID="$TG_CHAT_ID"
EOC
}

load_config() { [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"; }

generate_ssh_key() {
    if [ ! -f "$HOME/.ssh/id_rsa" ]; then
        ssh-keygen -t rsa -b 4096 -N "" -f "$HOME/.ssh/id_rsa"
        echo -e "${GREEN}✅ SSH Key 已生成${RESET}"
    else
        echo -e "${YELLOW}ℹ️ SSH Key 已存在${RESET}"
    fi

    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_rsa
    mkdir -p ~/.ssh
    ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
}

init_config() {
    generate_ssh_key

    while true; do
        read -p "请输入 GitHub 仓库地址 (SSH, 例如 git@github.com:USER/REPO.git): " REPO_URL
        read -p "请输入分支名称 (默认 main): " BRANCH
        BRANCH=${BRANCH:-main}

        TMP_DIR=$(mktemp -d)
        if git clone -b "$BRANCH" "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1; then
            # 不删除临时目录
            break
        else
            echo -e "${RED}❌ 仓库无法访问，请确认 SSH Key 已添加到 GitHub 并输入正确的 SSH 地址${RESET}"
        fi
    done

    read -p "请输入提交前缀 (默认 VPS-Upload): " COMMIT_PREFIX
    COMMIT_PREFIX=${COMMIT_PREFIX:-VPS-Upload}

    read -p "是否配置 Telegram Bot 通知？(y/n): " TG_CHOICE
    if [[ "$TG_CHOICE" == "y" ]]; then
        read -p "请输入 TG Bot Token: " TG_BOT_TOKEN
        read -p "请输入 TG Chat ID: " TG_CHAT_ID
    fi

    save_config
    echo -e "${GREEN}✅ 配置已保存${RESET}"
    read -p "按回车返回菜单..."
}

upload_files() {
    load_config
    if [ ! -d "$UPLOAD_DIR" ]; then
        echo -e "${RED}❌ 上传目录不存在: $UPLOAD_DIR${RESET}" | tee -a "$LOG_FILE"
        read -p "按回车返回菜单..."
        return
    fi

    shopt -s nullglob
    FILE_LIST=("$UPLOAD_DIR"/*)
    shopt -u nullglob
    TOTAL_FILES=${#FILE_LIST[@]}
    if [ "$TOTAL_FILES" -eq 0 ]; then
        echo -e "${YELLOW}⚠️ 上传目录为空: $UPLOAD_DIR${RESET}" | tee -a "$LOG_FILE"
        read -p "按回车返回菜单..."
        return
    fi

    TMP_DIR=$(mktemp -d)
    echo -e "${GREEN}ℹ️ 正在 clone 仓库...${RESET}"
    git clone -b "$BRANCH" "$REPO_URL" "$TMP_DIR/repo" >>"$LOG_FILE" 2>&1 || {
        echo -e "${RED}❌ Git clone 失败${RESET}" | tee -a "$LOG_FILE"
        send_tg "❌ VPS 上传失败：无法 clone 仓库"
        read -p "按回车返回菜单..."
        return
    }

    rsync -a --ignore-times "$UPLOAD_DIR"/ "$TMP_DIR/repo/"

    cd "$TMP_DIR/repo" || { read -p "按回车返回菜单..."; return; }

    git pull --rebase origin "$BRANCH" >>"$LOG_FILE" 2>&1 || true
    git add -A

    if git diff-index --quiet HEAD --; then
        COMMIT_MSG="$COMMIT_PREFIX keep-alive $(date '+%Y-%m-%d %H:%M:%S')"
        git commit --allow-empty -m "$COMMIT_MSG" >>"$LOG_FILE" 2>&1
    else
        COMMIT_MSG="$COMMIT_PREFIX $(date '+%Y-%m-%d %H:%M:%S')"
        git commit -m "$COMMIT_MSG" >>"$LOG_FILE" 2>&1
    fi

    if git push origin "$BRANCH" >>"$LOG_FILE" 2>&1; then
        echo -e "${GREEN}✅ 上传成功: $COMMIT_MSG${RESET}" | tee -a "$LOG_FILE"
        send_tg "✅ VPS 上传成功：$COMMIT_MSG，文件数：$TOTAL_FILES"
    else
        echo -e "${RED}❌ 上传失败${RESET}" | tee -a "$LOG_FILE"
        send_tg "❌ VPS 上传失败：git push 出错"
    fi

    # 不删除 TMP_DIR
    echo -e "${YELLOW}⚠️ 临时目录保留: $TMP_DIR${RESET}"
    read -p "按回车返回菜单..."
}

download_from_github() {
    load_config
    mkdir -p "$DOWNLOAD_DIR"

    TMP_DIR=$(mktemp -d)
    echo -e "${GREEN}ℹ️ 正在从 GitHub 仓库下载...${RESET}"

    if ! git clone -b "$BRANCH" "$REPO_URL" "$TMP_DIR/repo" >>"$LOG_FILE" 2>&1; then
        echo -e "${RED}❌ Git clone 失败，请检查仓库地址和 SSH Key${RESET}" | tee -a "$LOG_FILE"
        read -p "按回车返回菜单..."
        return
    fi

    rsync -a --delete "$TMP_DIR/repo/" "$DOWNLOAD_DIR/"

    echo -e "${GREEN}✅ 下载完成，文件已同步到 $DOWNLOAD_DIR${RESET}" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}⚠️ 临时目录保留: $TMP_DIR${RESET}"
    read -p "按回车返回菜单..."
}

set_cron() {
    load_config
    echo "请选择定时任务："
    echo -e "${GREEN}1) 每 5 分钟一次${RESET}"
    echo -e "${GREEN}2) 每 10 分钟一次${RESET}"
    echo -e "${GREEN}3) 每 30 分钟一次${RESET}"
    echo -e "${GREEN}4) 每小时一次${RESET}"
    echo -e "${GREEN}5) 每天凌晨 3 点${RESET}"
    echo -e "${GREEN}6) 每周一凌晨 0 点${RESET}"
    echo -e "${GREEN}7) 自定义${RESET}"
    read -p "请输入选项 [1-7]: " choice
    case $choice in
        1) cron_expr="*/5 * * * *" ;;
        2) cron_expr="*/10 * * * *" ;;
        3) cron_expr="*/30 * * * *" ;;
        4) cron_expr="0 * * * *" ;;
        5) cron_expr="0 3 * * *" ;;
        6) cron_expr="0 0 * * 1" ;;
        7) read -p "请输入自定义 cron 表达式: " cron_expr ;;
        *) echo "无效选项"; read -p "按回车返回菜单..."; return ;;
    esac
    CRON_CMD="bash $HOME/ghupload/gh_tool.sh upload >> $LOG_FILE 2>&1 #GHUPLOAD"
    (crontab -l 2>/dev/null | grep -v "#GHUPLOAD"; echo "$cron_expr $CRON_CMD") | crontab -
    echo -e "${GREEN}✅ 定时任务已添加: $cron_expr${RESET}"
    read -p "按回车返回菜单..."
}

uninstall_tool() {
    echo -e "${GREEN}ℹ️ 正在卸载 VPS <-> GitHub 工具...${RESET}"
    rm -rf "$HOME/ghupload"
    rm -f "$HOME/bin/G" "$HOME/bin/g"
    crontab -l 2>/dev/null | grep -v "#GHUPLOAD" | crontab -
    echo -e "${GREEN}✅ 卸载完成！${RESET}"
    exit 0
}

show_log() {
    [ -f "$LOG_FILE" ] && tail -n 50 "$LOG_FILE" || echo -e "${YELLOW}⚠️ 日志文件不存在${RESET}"
    read -p "按回车返回菜单..."
}

menu() {
    clear
    echo -e "${GREEN}==============================${RESET}"
    echo -e "${GREEN} VPS <-> GitHub 工具 (固定目录, 保留临时)${RESET}"
    echo -e "${GREEN}==============================${RESET}"
    echo -e "${GREEN}1) 初始化配置${RESET}"
    echo -e "${GREEN}2) 上传文件到 GitHub ($UPLOAD_DIR)${RESET}"
    echo -e "${GREEN}3) 下载 GitHub 仓库到 VPS ($DOWNLOAD_DIR)${RESET}"
    echo -e "${GREEN}4) 设置定时任务${RESET}"
    echo -e "${GREEN}5) 查看日志${RESET}"
    echo -e "${GREEN}6) 卸载脚本${RESET}"
    echo -e "${GREEN}0) 退出${RESET}"
    read -p "请输入选项: " opt
    case $opt in
        1) init_config ;;
        2) upload_files ;;
        3) download_from_github ;;
        4) set_cron ;;
        5) show_log ;;
        6) uninstall_tool ;;
        0) exit 0 ;;
        *) echo "无效选项"; read -p "按回车返回菜单..." ;;
    esac
    menu
}

menu
