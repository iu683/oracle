#!/bin/bash
set -e

# 颜色
GREEN="\033[32m"
RED="\033[31m"
RESET="\033[0m"

# 统一目录
BASE_DIR="/root/rsync_task"
CONFIG_FILE="$BASE_DIR/rsync_tasks.conf"
KEY_DIR="$BASE_DIR/keys"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$KEY_DIR" "$LOG_DIR"
touch "$CONFIG_FILE"

send_stats() { :; }  # 占位函数

install() {
    if ! command -v "$1" &> /dev/null; then
        echo "安装依赖: $1"
        if command -v apt &> /dev/null; then
            apt update && apt install -y "$1"
        elif command -v yum &> /dev/null; then
            yum install -y "$1"
        fi
    fi
}

# -------------------------
# 列表任务
# -------------------------
list_tasks() {
    echo -e "${GREEN}已保存的同步任务:${RESET}"
    echo "---------------------------------"
    [[ ! -s "$CONFIG_FILE" ]] && echo "暂无任务" && return
    awk -F'|' '{printf "%d - %s: %s -> %s:%s [%s]\n", NR, $1, $2, $3, $4, $6}' "$CONFIG_FILE"
    echo "---------------------------------"
}

# -------------------------
# 添加任务
# -------------------------
add_task() {
    send_stats "添加新同步任务"
    read -e -p "任务名称: " name
    read -e -p "本地目录: " local_path
    read -e -p "远程目录: " remote_path
    read -e -p "远程用户@IP: " remote
    read -e -p "SSH端口 (默认22): " port
    port=${port:-22}

    echo "选择认证方式: 1)密码 2)密钥"
    read -e -p "请选择: " auth_choice
    case $auth_choice in
        1)
            read -s -p "输入密码: " password_or_key; echo
            auth_method="password"
            ;;
        2)
            echo "粘贴密钥 (完成后按两次回车):"
            password_or_key=""
            while IFS= read -r line || [[ -n "$line" ]]; do
                [[ -z "$line" && "$password_or_key" == *"PRIVATE KEY"* ]] && break
                password_or_key+="$line"$'\n'
            done
            key_file="$KEY_DIR/${name}_sync.key"
            echo -n "$password_or_key" > "$key_file"
            chmod 600 "$key_file"
            password_or_key="$key_file"
            auth_method="key"
            ;;
        *)
            echo "无效选择"; return
            ;;
    esac

    echo "请选择同步模式:"
    echo "1) 标准模式 (-avz)"
    echo "2) 删除目标模式 (-avz --delete)"
    read -e -p "请选择 (1/2): " mode
    case $mode in
        1) options="-avz" ;;
        2) options="-avz --delete" ;;
        *) echo "无效选择，使用默认 -avz"; options="-avz" ;;
    esac

    echo "$name|$local_path|$remote|$remote_path|$port|$options|$auth_method|$password_or_key" >> "$CONFIG_FILE"
    install rsync
    echo -e "${GREEN}任务已保存!${RESET}"
}

# -------------------------
# 删除任务
# -------------------------
delete_task() {
    send_stats "删除同步任务"
    read -e -p "请输入任务编号: " num
    local task=$(sed -n "${num}p" "$CONFIG_FILE")
    [[ -z "$task" ]] && echo "任务不存在" && return
    IFS='|' read -r name local_path remote remote_path port options auth_method password_or_key <<< "$task"
    [[ "$auth_method" == "key" && "$password_or_key" == "$KEY_DIR"* ]] && rm -f "$password_or_key"
    sed -i "${num}d" "$CONFIG_FILE"
    echo -e "${GREEN}任务已删除!${RESET}"
}

# -------------------------
# 执行同步
# -------------------------
run_task() {
    read -e -p "请输入任务编号: " num
    local direction
    echo "同步方向: 1)推送 2)拉取"
    read -e -p "请选择: " dir_choice
    [[ "$dir_choice" == "2" ]] && direction="pull" || direction="push"

    local task=$(sed -n "${num}p" "$CONFIG_FILE")
    [[ -z "$task" ]] && { echo "任务不存在"; return; }
    IFS='|' read -r name local_path remote remote_path port options auth_method password_or_key <<< "$task"

    local source destination
    if [[ "$direction" == "pull" ]]; then
        source="$remote:$remote_path"
        destination="$local_path"
    else
        source="$local_path"
        destination="$remote:$remote_path"
    fi

    local ssh_options="-p $port -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    if [[ "$auth_method" == "password" ]]; then
        install sshpass
        sshpass -p "$password_or_key" rsync $options -e "ssh $ssh_options" "$source" "$destination"
    else
        [[ ! -f "$password_or_key" ]] && { echo -e "${RED}密钥不存在${RESET}"; return; }
        [[ "$(stat -c %a "$password_or_key")" != "600" ]] && chmod 600 "$password_or_key"
        rsync $options -e "ssh -i $password_or_key $ssh_options" "$source" "$destination"
    fi

    [[ $? -eq 0 ]] && echo -e "${GREEN}同步完成!${RESET}" || echo -e "${RED}同步失败!${RESET}"
}

# -------------------------
# 定时任务管理
# -------------------------
schedule_task() {
    read -e -p "请输入要定时同步的任务编号: " num
    [[ ! "$num" =~ ^[0-9]+$ ]] && { echo "无效任务编号"; return; }

    echo "请选择定时间隔: 1) 每小时 2) 每天 3) 每周"
    read -e -p "请选择: " interval
    local random_minute=$(shuf -i 0-59 -n1)
    local cron_time
    case "$interval" in
        1) cron_time="$random_minute * * * *" ;;
        2) cron_time="$random_minute 0 * * *" ;;
        3) cron_time="$random_minute 0 * * 1" ;;
        *) echo "无效选择"; return ;;
    esac

    local cron_job="$cron_time bash $BASE_DIR/run_task.sh $num"
    crontab -l 2>/dev/null | grep -v "$BASE_DIR/run_task.sh $num" | { cat; echo "$cron_job"; } | crontab -
    echo -e "${GREEN}定时任务已创建: $cron_job${RESET}"
}

delete_task_schedule() {
    read -e -p "请输入要删除的任务编号: " num
    [[ ! "$num" =~ ^[0-9]+$ ]] && { echo "无效任务编号"; return; }
    crontab -l 2>/dev/null | grep -v "$BASE_DIR/run_task.sh $num" | crontab -
    echo -e "${GREEN}已删除任务编号 $num 的定时任务${RESET}"
}

# -------------------------
# 菜单
# -------------------------
rsync_manager() {
    while true; do
        clear
        echo -e "${GREEN}===== Rsync 一键菜单工具 =====${RESET}"
        list_tasks
        echo
        echo -e "${GREEN}1) 创建任务    2) 删除任务${RESET}"
        echo -e "${GREEN}3) 推送同步    4) 拉取同步${RESET}"
        echo -e "${GREEN}5) 创建定时任务 6) 删除定时任务${RESET}"
        echo -e "${GREEN}0) 退出${RESET}"
        read -e -p "请选择: " choice
        case $choice in
            1) add_task ;;
            2) delete_task ;;
            3) run_task ;;
            4) run_task ;;
            5) schedule_task ;;
            6) delete_task_schedule ;;
            0) exit 0 ;;
            *) echo "无效选择" ;;
        esac
        read -e -p "按回车继续..."
    done
}

# 启动菜单
rsync_manager
