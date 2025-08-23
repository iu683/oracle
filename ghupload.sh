#!/bin/bash
# 一键安装 / 管理 VPS -> GitHub 上传工具
# 路径统一，G/g 可全局运行

BASE_DIR="$HOME/ghupload"
UPLOAD_SCRIPT="$BASE_DIR/upload_to_github.sh"
CONFIG_FILE="$BASE_DIR/.ghupload_config"
LOG_FILE="$BASE_DIR/github_upload.log"
SSH_KEY="$BASE_DIR/id_rsa_ghupload"
SCRIPT_URL="https://raw.githubusercontent.com/iu683/star/main/ghupload.sh"

INSTALL_BIN_DIR="$HOME/bin"
INSTALL_PATH_UPPER="$INSTALL_BIN_DIR/G"
INSTALL_PATH_LOWER="$INSTALL_BIN_DIR/g"

mkdir -p "$BASE_DIR" "$INSTALL_BIN_DIR"

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
SSH_KEY="$HOME/ghupload/id_rsa_ghupload"
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

init_config() {
    if ! git config --global user.name >/dev/null; then
        read -p "请输入 Git 用户名: " GIT_USER
        git config --global user.name "$GIT_USER"
    fi
    if ! git config --global user.email >/dev/null; then
        read -p "请输入 Git 邮箱: " GIT_EMAIL
        git config --global user.email "$GIT_EMAIL"
    fi

    read -p "请输入 GitHub 仓库地址 (SSH): " REPO_URL
    read -p "请输入分支名称 (默认 main): " BRANCH
    BRANCH=${BRANCH:-main}
    read -p "请输入提交前缀 (默认 VPS-Upload): " COMMIT_PREFIX
    COMMIT_PREFIX=${COMMIT_PREFIX:-VPS-Upload}

    while true; do
        read -p "请输入上传目录路径 (绝对路径): " UPLOAD_DIR
        [ -d "$UPLOAD_DIR" ] && break || echo "⚠️ 目录不存在，请重新输入"
    done

    if [ ! -f "$SSH_KEY" ]; then
        echo "⚙️ 正在生成 SSH 密钥..."
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N "" -C "ghupload@VPS"
        echo "✅ SSH 密钥生成完成"
    fi
    echo "请将以下公钥添加到 GitHub 仓库的 SSH Keys 中:"
    cat "${SSH_KEY}.pub"
    echo "------------------------------------"

    read -p "是否配置 Telegram Bot 通知？(y/n): " TG_CHOICE
    if [[ "$TG_CHOICE" == "y" ]]; then
        read -p "请输入 TG Bot Token: " TG_BOT_TOKEN
        read -p "请输入 TG Chat ID: " TG_CHAT_ID
    fi

    save_config
    echo "✅ 配置已保存"
    upload_files  # 初始化完成后自动上传一次
}

change_repo() {
    load_config
    read -p "请输入新的 GitHub 仓库地址 (SSH): " NEW_REPO
    REPO_URL="$NEW_REPO"
    save_config
    echo "✅ 仓库地址已更新为: $REPO_URL"
}

upload_files() {
    load_config
    [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -ge $MAX_LOG_SIZE ] && echo "[`date '+%Y-%m-%d %H:%M:%S'`] --- 日志清理 ---" > "$LOG_FILE"

    TMP_DIR=$(mktemp -d)
    GIT_SSH_COMMAND="ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
        git clone -b "$BRANCH" "$REPO_URL" "$TMP_DIR/repo" >>"$LOG_FILE" 2>&1 || {
        echo "❌ Git clone 失败" | tee -a "$LOG_FILE"
        send_tg "❌ VPS 上传失败：无法 clone 仓库"
        rm -rf "$TMP_DIR"
        exit 1
    }

    if [ -z "$(ls -A "$UPLOAD_DIR")" ]; then
        echo "⚠️ 上传目录为空" | tee -a "$LOG_FILE"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    cp -r "$UPLOAD_DIR"/* "$TMP_DIR/repo/"
    cd "$TMP_DIR/repo" || exit 1
    git add .

    if git diff-index --quiet HEAD --; then
        echo "ℹ️ 没有文件改动，无需提交" | tee -a "$LOG_FILE"
        rm -rf "$TMP_DIR"
        exit 0
    fi

    COMMIT_MSG="$COMMIT_PREFIX $(date '+%Y-%m-%d %H:%M:%S')"
    git commit -m "$COMMIT_MSG" >>"$LOG_FILE" 2>&1
    git push origin "$BRANCH" >>"$LOG_FILE" 2>&1 && {
        echo "✅ 上传成功: $COMMIT_MSG" | tee -a "$LOG_FILE"
        send_tg "✅ VPS 上传成功：$COMMIT_MSG"
    } || {
        echo "❌ 上传失败" | tee -a "$LOG_FILE"
        send_tg "❌ VPS 上传失败：git push 出错"
    }

    rm -rf "$TMP_DIR"
}

set_cron() {
    load_config
    echo "请选择定时任务："
    echo "1) 每 5 分钟一次"
    echo "2) 每 10 分钟一次"
    echo "3) 每 30 分钟一次"
    echo "4) 每小时一次"
    echo "5) 每天凌晨 3 点"
    echo "6) 每周一凌晨 0 点"
    echo "7) 自定义"

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

show_log() {
    [ -f "$LOG_FILE" ] && tail -n 50 "$LOG_FILE" || echo "⚠️ 日志文件不存在"
}

update_tool() {
    echo "⚙️ 正在从 GitHub 拉取最新版本..."
    if curl -fsSL "https://raw.githubusercontent.com/iu683/star/main/ghupload.sh" -o "$BASE_DIR/ghupload.sh"; then
        chmod +x "$BASE_DIR/ghupload.sh"
        echo "✅ 已更新到最新版本！请重新运行 G/g"
        exit 0
    else
        echo "❌ 更新失败，请检查网络或 URL"
    fi
}

uninstall_tool() {
    echo "⚠️ 正在卸载..."
    rm -f "$UPLOAD_SCRIPT" "$INSTALL_BIN_DIR/G" "$INSTALL_BIN_DIR/g"
    rm -f "$CONFIG_FILE" "$LOG_FILE" "$SSH_KEY" "$SSH_KEY.pub"
    crontab -l 2>/dev/null | grep -v "upload_to_github.sh upload" | crontab -
    echo "✅ 卸载完成！"
}

menu() {
    echo -e "${GREEN}==============================${RESET}"
    echo -e "${GREEN} VPS -> GitHub 上传工具 ${RESET}"
    echo -e "${GREEN}==============================${RESET}"
    echo -e "${GREEN}1) 初始化配置${RESET}"
    echo -e "${GREEN}2) 手动上传文件${RESET}"
    echo -e "${GREEN}3) 设置定时任务${RESET}"
    echo -e "${GREEN}4) 查看最近日志${RESET}"
    echo -e "${GREEN}5) 更新脚本${RESET}"
    echo -e "${GREEN}6) 卸载脚本${RESET}"
    echo -e "${GREEN}7) 修改仓库地址${RESET}"
    echo -e "${GREEN}0) 退出${RESET}"
    read -p "请输入选项: " opt
    case $opt in
        1) init_config ;;
        2) upload_files ;;
        3) set_cron ;;
        4) show_log ;;
        5) update_tool ;;
        6) uninstall_tool ;;
        7) change_repo ;;
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
    for cmd in git curl ssh; do
        command -v $cmd >/dev/null 2>&1 || { echo "❌ 请先安装 $cmd"; exit 1; }
    done

    write_main_script

    make_launcher() {
        local path=$1
        cat > "$path" <<EOF
#!/bin/bash
bash "$UPLOAD_SCRIPT" "\$@"
EOF
        chmod +x "$path"
    }

    make_launcher "$INSTALL_PATH_UPPER"
    make_launcher "$INSTALL_PATH_LOWER"

    # 自动加入 PATH
    if ! echo "$PATH" | grep -q "$INSTALL_BIN_DIR"; then
        echo "export PATH=\$PATH:$INSTALL_BIN_DIR" >> "$HOME/.bashrc"
        export PATH=$PATH:$INSTALL_BIN_DIR
        echo "✅ 已将 $INSTALL_BIN_DIR 添加到 PATH，请重新打开终端以生效"
    fi

    echo "✅ 安装完成！现在可以用 G 或 g 运行"
}

# ===============================
# 卸载函数
# ===============================
uninstall_tool() {
    "$UPLOAD_SCRIPT" uninstall 2>/dev/null || true
}

# ===============================
# 主控制
# ===============================
case "$1" in
    install) install_tool ;;
    uninstall) uninstall_tool ;;
    *) echo "用法: bash $0 {install|uninstall}" ;;
esac
