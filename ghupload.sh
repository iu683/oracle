#!/bin/bash
# VPS <-> GitHub 工具完整版本 (SSH 自动生成 Key + 上传/下载 + 进度条 + 自动返回菜单)

BASE_DIR="$HOME/ghupload"
CONFIG_FILE="$BASE_DIR/.ghupload_config"
LOG_FILE="$BASE_DIR/github_upload.log"

BIN_DIR="$HOME/bin"
INSTALL_PATH_UPPER="$BIN_DIR/G"
INSTALL_PATH_LOWER="$BIN_DIR/g"

mkdir -p "$BASE_DIR" "$BIN_DIR"

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

REPO_URL=""
BRANCH="main"
COMMIT_PREFIX="VPS-Upload"
UPLOAD_DIR=""
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
UPLOAD_DIR="$UPLOAD_DIR"
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

    PUB_KEY_CONTENT=$(cat "$HOME/.ssh/id_rsa.pub")
    read -p "请输入 GitHub 用户名: " GH_USER
    read -s -p "请输入 GitHub Personal Access Token (需 admin:public_key 权限): " GH_TOKEN
    echo ""
    TITLE="VPS_$(date '+%Y%m%d%H%M%S')"
    RESP=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Authorization: token $GH_TOKEN" \
        -d "{\"title\":\"$TITLE\",\"key\":\"$PUB_KEY_CONTENT\"}" \
        https://api.github.com/user/keys)
    if [ "$RESP" -eq 201 ]; then
        echo -e "${GREEN}✅ SSH Key 已成功添加到 GitHub，Title: $TITLE${RESET}"
    elif [ "$RESP" -eq 422 ]; then
        echo -e "${YELLOW}⚠️ 公钥已存在，跳过添加${RESET}"
    else
        echo -e "${RED}❌ 添加公钥失败，请检查用户名和 Token 权限${RESET}"
    fi
}

init_config() {
    generate_ssh_key

    while true; do
        read -p "请输入 GitHub 仓库地址 (SSH, 例如 git@github.com:USER/REPO.git): " REPO_URL
        read -p "请输入分支名称 (默认 main): " BRANCH
        BRANCH=${BRANCH:-main}

        TMP_DIR=$(mktemp -d)
        if git clone -b "$BRANCH" "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1; then
            rm -rf "$TMP_DIR"
            break
        else
            echo -e "${RED}❌ 仓库无法访问，请确认 SSH Key 已添加到 GitHub 并输入正确的 SSH 地址${RESET}"
        fi
    done

    read -p "请输入提交前缀 (默认 VPS-Upload): " COMMIT_PREFIX
    COMMIT_PREFIX=${COMMIT_PREFIX:-VPS-Upload}

    while true; do
        read -p "请输入上传目录路径 (绝对路径): " UPLOAD_DIR
        [ -d "$UPLOAD_DIR" ] && break || echo -e "${YELLOW}⚠️ 目录不存在，请重新输入${RESET}"
    done

    read -p "是否配置 Telegram Bot 通知？(y/n): " TG_CHOICE
    if [[ "$TG_CHOICE" == "y" ]]; then
        read -p "请输入 TG Bot Token: " TG_BOT_TOKEN
        read -p "请输入 TG Chat ID: " TG_CHAT_ID
    fi

    save_config
    echo -e "${GREEN}✅ 配置已保存${RESET}"
    read -p "按回车返回菜单..."
}

change_repo() {
    load_config
    while true; do
        read -p "请输入新的 GitHub 仓库地址 (SSH): " NEW_REPO
        TMP_DIR=$(mktemp -d)
        if git clone -b "$BRANCH" "$NEW_REPO" "$TMP_DIR" >/dev/null 2>&1; then
            rm -rf "$TMP_DIR"
            break
        else
            echo -e "${RED}❌ 仓库无法访问，请确认 SSH Key 已添加到 GitHub${RESET}"
        fi
    done
    REPO_URL="$NEW_REPO"
    save_config
    echo -e "${GREEN}✅ 仓库地址已更新为: $REPO_URL${RESET}"
    read -p "按回车返回菜单..."
}

upload_files() {
    load_config
    if [ -z "$UPLOAD_DIR" ] || [ ! -d "$UPLOAD_DIR" ]; then
        echo -e "${RED}❌ 上传目录未配置或不存在，请先初始化配置${RESET}" | tee -a "$LOG_FILE"
        read -p "按回车返回菜单..."
        return
    fi

    FILE_LIST=("$UPLOAD_DIR"/*)
    TOTAL_FILES=${#FILE_LIST[@]}
    if [ "$TOTAL_FILES" -eq 0 ]; then
        echo -e "${YELLOW}⚠️ 上传目录为空${RESET}" | tee -a "$LOG_FILE"
        read -p "按回车返回菜单..."
        return
    fi

    [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -ge 10485760 ] && echo "[`date '+%Y-%m-%d %H:%M:%S'`] --- 日志清理 ---" > "$LOG_FILE"

    TMP_DIR=$(mktemp -d)
    echo -e "${GREEN}ℹ️ 正在 clone 仓库...${RESET}"
    git clone -b "$BRANCH" "$REPO_URL" "$TMP_DIR/repo" >>"$LOG_FILE" 2>&1 || { echo -e "${RED}❌ Git clone 失败${RESET}" | tee -a "$LOG_FILE"; send_tg "❌ VPS 上传失败：无法 clone 仓库"; rm -rf "$TMP_DIR"; read -p "按回车返回菜单..."; return; }

    COUNT=0
    for f in "${FILE_LIST[@]}"; do
        ((COUNT++))
        cp -r "$f" "$TMP_DIR/repo/"
        echo -ne "${GREEN}上传进度: $COUNT/$TOTAL_FILES 文件\r${RESET}"
    done
    echo -e "\n${GREEN}✅ 文件复制完成${RESET}"

    cd "$TMP_DIR/repo" || { read -p "按回车返回菜单..."; return; }
    git add .

    if git diff-index --quiet HEAD --; then
        echo -e "${YELLOW}ℹ️ 没有文件改动，无需提交${RESET}" | tee -a "$LOG_FILE"
        send_tg "ℹ️ VPS 上传：没有文件改动"
        rm -rf "$TMP_DIR"
        read -p "按回车返回菜单..."
        return
    fi

    COMMIT_MSG="$COMMIT_PREFIX $(date '+%Y-%m-%d %H:%M:%S')"
    git commit -m "$COMMIT_MSG" >>"$LOG_FILE" 2>&1
    if git push origin "$BRANCH" >>"$LOG_FILE" 2>&1; then
        echo -e "${GREEN}✅ 上传成功: $COMMIT_MSG${RESET}" | tee -a "$LOG_FILE"
        send_tg "✅ VPS 上传成功：$COMMIT_MSG，文件数：$TOTAL_FILES"
    else
        echo -e "${RED}❌ 上传失败${RESET}" | tee -a "$LOG_FILE"
        send_tg "❌ VPS 上传失败：git push 出错"
    fi
    rm -rf "$TMP_DIR"
    read -p "按回车返回菜单..."
}

download_from_github() {
    load_config
    read -p "请输入下载目录 (绝对路径): " DOWNLOAD_DIR
    mkdir -p "$DOWNLOAD_DIR"

    TMP_DIR=$(mktemp -d)
    echo -e "${GREEN}ℹ️ 正在从 GitHub 仓库下载...${RESET}"
    git clone -b "$BRANCH" "$REPO_URL" "$TMP_DIR/repo" >>"$LOG_FILE" 2>&1 || { echo -e "${RED}❌ Git clone 失败${RESET}" | tee -a "$LOG_FILE"; rm -rf "$TMP_DIR"; read -p "按回车返回菜单..."; return; }

    FILE_LIST=("$TMP_DIR/repo"/*)
    TOTAL_FILES=${#FILE_LIST[@]}
    COUNT=0
    for f in "${FILE_LIST[@]}"; do
        ((COUNT++))
        cp -r "$f" "$DOWNLOAD_DIR/"
        echo -ne "${GREEN}下载进度: $COUNT/$TOTAL_FILES 文件\r${RESET}"
    done
    echo -e "\n${GREEN}✅ 下载完成，文件已保存到 $DOWNLOAD_DIR${RESET}" | tee -a "$LOG_FILE"
    rm -rf "$TMP_DIR"
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
    (crontab -l 2>/dev/null | grep -v "gh_tool.sh upload"; echo "$cron_expr bash $HOME/ghupload/gh_tool.sh upload >> $LOG_FILE 2>&1") | crontab -
    echo -e "${GREEN}✅ 定时任务已添加: $cron_expr${RESET}"
    read -p "按回车返回菜单..."
}

show_log() {
    [ -f "$LOG_FILE" ] && tail -n 50 "$LOG_FILE" || echo -e "${YELLOW}⚠️ 日志文件不存在${RESET}"
    read -p "按回车返回菜单..."
}

update_tool() {
    curl -fsSL "https://raw.githubusercontent.com/iu683/star/main/ghupload.sh" -o "$HOME/ghupload/gh_tool.sh" && chmod +x "$HOME/ghupload/gh_tool.sh"
    echo -e "${GREEN}✅ 脚本已更新${RESET}"
    read -p "按回车返回菜单..."
}

uninstall_tool() {
    echo -e "${GREEN}ℹ️ 正在卸载 VPS <-> GitHub 工具...${RESET}"
    rm -rf "$HOME/ghupload"
    rm -f "$HOME/bin/G" "$HOME/bin/g"
    crontab -l 2>/dev/null | grep -v "gh_tool.sh upload" | crontab -
    echo -e "${GREEN}✅ 卸载完成！${RESET}"
    exit 0
}

menu() {
    clear
    echo -e "${GREEN}==============================${RESET}"
    echo -e "${GREEN} VPS <-> GitHub 工具 ${RESET}"
    echo -e "${GREEN}==============================${RESET}"
    echo -e "${GREEN}1) 初始化配置${RESET}"
    echo -e "${GREEN}2) 上传文件到 GitHub${RESET}"
    echo -e "${GREEN}3) 下载 GitHub 仓库到 VPS${RESET}"
    echo -e "${GREEN}4) 设置定时任务${RESET}"
    echo -e "${GREEN}5) 查看最近日志${RESET}"
    echo -e "${GREEN}6) 修改仓库地址${RESET}"
    echo -e "${GREEN}7) 更新脚本${RESET}"
    echo -e "${GREEN}8) 卸载脚本${RESET}"
    echo -e "${GREEN}0) 退出${RESET}"
    read -p "请输入选项: " opt
    case $opt in
        1) init_config ;;
        2) upload_files ;;
        3) download_from_github ;;
        4) set_cron ;;
        5) show_log ;;
        6) change_repo ;;
        7) update_tool ;;
        8) uninstall_tool ;;
        0) exit 0 ;;
        *) echo "无效选项"; read -p "按回车返回菜单..." ;;
    esac
    menu
}

# 自动启动菜单
menu
