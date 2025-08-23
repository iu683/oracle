#!/bin/bash
# VPS -> GitHub 上传工具完整版本 (SSH 自动生成 Key + 推送)

BASE_DIR="$HOME/ghupload"
UPLOAD_SCRIPT="$BASE_DIR/upload_to_github.sh"
CONFIG_FILE="$BASE_DIR/.ghupload_config"
LOG_FILE="$BASE_DIR/github_upload.log"

BIN_DIR="$HOME/bin"
INSTALL_PATH_UPPER="$BIN_DIR/G"
INSTALL_PATH_LOWER="$BIN_DIR/g"

mkdir -p "$BASE_DIR" "$BIN_DIR"

# ===============================
# 写入主脚本
# ===============================
write_main_script() {
cat > "$UPLOAD_SCRIPT" <<'EOF'
#!/bin/bash
GREEN="\033[32m"
RESET="\033[0m"

CONFIG_FILE="$HOME/ghupload/.ghupload_config"
LOG_FILE="$HOME/ghupload/github_upload.log"
MAX_LOG_SIZE=10485760

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
        echo "✅ SSH Key 已生成"
    else
        echo "ℹ️ SSH Key 已存在"
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
        echo "✅ SSH Key 已成功添加到 GitHub，Title: $TITLE"
    elif [ "$RESP" -eq 422 ]; then
        echo "⚠️ 公钥已存在，跳过添加"
    else
        echo "❌ 添加公钥失败，请检查用户名和 Token 权限"
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
            echo "❌ 仓库无法访问，请确认 SSH Key 已添加到 GitHub 并输入正确的 SSH 地址"
        fi
    done

    read -p "请输入提交前缀 (默认 VPS-Upload): " COMMIT_PREFIX
    COMMIT_PREFIX=${COMMIT_PREFIX:-VPS-Upload}

    while true; do
        read -p "请输入上传目录路径 (绝对路径): " UPLOAD_DIR
        [ -d "$UPLOAD_DIR" ] && break || echo "⚠️ 目录不存在，请重新输入"
    done

    read -p "是否配置 Telegram Bot 通知？(y/n): " TG_CHOICE
    if [[ "$TG_CHOICE" == "y" ]]; then
        read -p "请输入 TG Bot Token: " TG_BOT_TOKEN
        read -p "请输入 TG Chat ID: " TG_CHAT_ID
    fi

    save_config
    echo "✅ 配置已保存"
    upload_files
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
            echo "❌ 仓库无法访问，请确认 SSH Key 已添加到 GitHub"
        fi
    done
    REPO_URL="$NEW_REPO"
    save_config
    echo "✅ 仓库地址已更新为: $REPO_URL"
}

upload_files() {
    load_config
    if [ -z "$UPLOAD_DIR" ] || [ ! -d "$UPLOAD_DIR" ]; then
        echo "❌ 上传目录未配置或不存在，请先初始化配置" | tee -a "$LOG_FILE"
        exit 1
    fi

    if [ -z "$(ls -A "$UPLOAD_DIR")" ]; then
        echo "⚠️ 上传目录为空" | tee -a "$LOG_FILE"
        exit 1
    fi

    [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -ge $MAX_LOG_SIZE ] && echo "[`date '+%Y-%m-%d %H:%M:%S'`] --- 日志清理 ---" > "$LOG_FILE"

    TMP_DIR=$(mktemp -d)
    git clone -b "$BRANCH" "$REPO_URL" "$TMP_DIR/repo" >>"$LOG_FILE" 2>&1 || { echo "❌ Git clone 失败" | tee -a "$LOG_FILE"; send_tg "❌ VPS 上传失败：无法 clone 仓库"; rm -rf "$TMP_DIR"; exit 1; }

    cp -r "$UPLOAD_DIR"/* "$TMP_DIR/repo/"
    cd "$TMP_DIR/repo" || exit 1
    git add .

    if git diff-index --quiet HEAD --; then
        echo "ℹ️ 没有文件改动，无需提交" | tee -a "$LOG_FILE"
        send_tg "ℹ️ VPS 上传：没有文件改动"
        rm -rf "$TMP_DIR"
        exit 0
    fi

    COMMIT_MSG="$COMMIT_PREFIX $(date '+%Y-%m-%d %H:%M:%S')"
    git commit -m "$COMMIT_MSG" >>"$LOG_FILE" 2>&1

    if git push origin "$BRANCH" >>"$LOG_FILE" 2>&1; then
        echo "✅ 上传成功: $COMMIT_MSG" | tee -a "$LOG_FILE"
        send_tg "✅ VPS 上传成功：$COMMIT_MSG"
    else
        echo "❌ 上传失败" | tee -a "$LOG_FILE"
        send_tg "❌ VPS 上传失败：git push 出错"
    fi

    rm -rf "$TMP_DIR"
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
        *) echo "无效选项"; return ;;
    esac
    (crontab -l 2>/dev/null | grep -v "upload_to_github.sh upload"; echo "$cron_expr bash $UPLOAD_SCRIPT upload >> $LOG_FILE 2>&1") | crontab -
    echo "✅ 定时任务已添加: $cron_expr"
}

show_log() { [ -f "$LOG_FILE" ] && tail -n 50 "$LOG_FILE" || echo "⚠️ 日志文件不存在"; }
update_tool() { curl -fsSL "https://raw.githubusercontent.com/iu683/star/main/ghupload.sh" -o "$UPLOAD_SCRIPT" && chmod +x "$UPLOAD_SCRIPT"; echo "✅ 已更新"; exit 0; }

menu() {
    echo -e "${GREEN}==============================${RESET}"
    echo -e "${GREEN} VPS -> GitHub 上传工具 ${RESET}"
    echo -e "${GREEN}==============================${RESET}"
    echo -e "${GREEN}1) 初始化配置${RESET}"
    echo -e "${GREEN}2) 手动上传文件${RESET}"
    echo -e "${GREEN}3) 设置定时任务${RESET}"
    echo -e "${GREEN}4) 查看最近日志${RESET}"
    echo -e "${GREEN}5) 修改仓库地址${RESET}"
    echo -e "${GREEN}6) 更新脚本${RESET}"
    echo -e "${GREEN}7) 卸载脚本${RESET}"
    echo -e "${GREEN}0) 退出${RESET}"
    read -p "请输入选项: " opt
    case $opt in
        1) init_config ;;
        2) upload_files ;;
        3) set_cron ;;
        4) show_log ;;
        5) change_repo ;;
        6) update_tool ;;
        7) uninstall_tool ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
}

case "$1" in
    upload) upload_files ;;
    *) menu ;;
esac
EOF

chmod +x "$UPLOAD_SCRIPT"
}

# ===============================
# 安装函数
# ===============================
install_tool() {
    echo "ℹ️ 正在安装 VPS -> GitHub 上传工具..."
    write_main_script

    for path in "$INSTALL_PATH_UPPER" "$INSTALL_PATH_LOWER"; do
        cat > "$path" <<EOF
#!/bin/bash
"$UPLOAD_SCRIPT" "\$@"
EOF
        chmod +x "$path"
    done

    echo "✅ 安装完成！可用 G 或 g 运行"
    echo "ℹ️ 主脚本路径: $UPLOAD_SCRIPT"
    echo "ℹ️ 快捷启动器: $INSTALL_PATH_UPPER , $INSTALL_PATH_LOWER"
    "$UPLOAD_SCRIPT"
}

# ===============================
# 卸载函数
# ===============================
uninstall_tool() {
    echo "ℹ️ 正在卸载 VPS -> GitHub 上传工具..."
    rm -rf "$BASE_DIR"
    rm -f "$INSTALL_PATH_UPPER" "$INSTALL_PATH_LOWER"

    if crontab -l 2>/dev/null | grep -q "upload_to_github.sh upload"; then
        crontab -l 2>/dev/null | grep -v "upload_to_github.sh upload" | crontab -
        echo "✅ 定时任务已删除"
    else
        echo "ℹ️ 未发现定时任务，无需删除"
    fi

    echo "✅ 卸载完成！"
    exit 0
}

# ===============================
# 主控制
# ===============================
case "$1" in
    install) install_tool ;;
    uninstall) uninstall_tool ;;
    *) echo "用法: bash $0 {install|uninstall}" ;;
esac
