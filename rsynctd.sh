#!/bin/bash
# ==========================================
# Rsync 一键菜单管理脚本（修正版）
# 支持 push/pull/all、定时任务、密码/密钥认证、日志管理
# ==========================================

set -e

GREEN="\033[32m"
RED="\033[31m"
RESET="\033[0m"

CONFIG_FILE="$HOME/.rsync_tasks"
KEY_DIR="$HOME/.rsync_keys"
LOG_DIR="$HOME/.rsync_logs"

mkdir -p "$KEY_DIR" "$LOG_DIR"
touch "$CONFIG_FILE"

send_stats() { :; }

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

cleanup_logs() { find "$LOG_DIR" -type f -mtime +7 -name "*.log" -exec rm -f {} \; }

# -------------------------
# 任务管理函数
# -------------------------
list_tasks() {
    echo -e "${GREEN}已保存的同步任务:${RESET}"
    echo "---------------------------------"
    [[ ! -s "$CONFIG_FILE" ]] && echo "暂无任务" && return
    awk -F'|' '{printf "%d - %s: %s -> %s:%s [%s]\n", NR, $1, $2, $3, $4, $6}' "$CONFIG_FILE"
    echo "---------------------------------"
}

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

    echo "同步模式: 1)标准(-avz) 2)删除目标(-avz --delete)"
    read -e -p "选择: " mode
    case $mode in
        1) options="-avz" ;;
        2) options="-avz --delete" ;;
        *) options="-avz" ;;
    esac

    echo "$name|$local_path|$remote|$remote_path|$port|$options|$auth_method|$password_or_key" >> "$CONFIG_FILE"
    install rsync
    echo -e "${GREEN}任务已保存!${RESET}"
}

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

run_single_task() {
    local direction="$1" num="$2"
    local task=$(sed -n "${num}p" "$CONFIG_FILE")
    [[ -z "$task" ]] && { echo "任务不存在"; return; }
    IFS='|' read -r name local_path remote remote_path port options auth_method password_or_key <<< "$task"
    local source destination
    if [[ "$direction" == "pull" ]]; then
        source="$remote:$remote_path"; destination="$local_path"
    else
        source="$local_path"; destination="$remote:$remote_path"
    fi
    cleanup_logs
    local ssh_options="-p $port -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    local log_file="$LOG_DIR/${name}_$(date +%Y%m%d%H%M%S).log"
    if [[ "$auth_method" == "password" ]]; then
        install sshpass
        sshpass -p "$password_or_key" rsync $options -e "ssh $ssh_options" "$source" "$destination" &> "$log_file"
    else
        [[ ! -f "$password_or_key" ]] && { echo "密钥不存在"; return; }
        [[ "$(stat -c %a "$password_or_key")" != "600" ]] && chmod 600 "$password_or_key"
        rsync $options -e "ssh -i $password_or_key $ssh_options" "$source" "$destination" &> "$log_file"
    fi
    [[ $? -eq 0 ]] && echo -e "${GREEN}同步完成! 日志: $log_file${RESET}" || echo -e "${RED}同步失败! 日志: $log_file${RESET}"
}

run_task() {
    local direction="$1" target="$2"
    [[ "$1" == "push" || "$1" == "pull" ]] && { direction="$1"; target="$2"; }
    [[ -z "$target" ]] && read -e -p "任务编号或 all: " target
    if [[ "$target" == "all" ]]; then
        local total=$(wc -l < "$CONFIG_FILE")
        for num in $(seq 1 $total); do run_single_task "$direction" "$num"; done
    else
        run_single_task "$direction" "$target"
    fi
}

schedule_task() {
    read -e -p "任务编号: " num
    [[ ! "$num" =~ ^[0-9]+$ ]] && echo "无效编号" && return
    echo "方向: 1)push 2)pull"
    read -e -p "选择: " dir_choice
    direction="push"
    [[ "$dir_choice" == "2" ]] && direction="pull"
    echo "间隔: 1)每小时 2)每天 3)每周"
    read -e -p "选择: " interval
    local minute=$(shuf -i 0-59 -n 1)
    local cron_time=""
    case "$interval" in
        1) cron_time="$minute * * * *" ;;
        2) cron_time="$minute 0 * * *" ;;
        3) cron_time="$minute 0 * * 1" ;;
        *) echo "无效"; return ;;
    esac
    local log_file="$LOG_DIR/cron_${num}_\$(date +\%Y\%m\%d\%H\%M\%S).log"
    local cron_job="$cron_time $HOME/$(basename $0) $direction $num >> $log_file 2>&1"
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    echo -e "${GREEN}定时任务创建: $cron_job${RESET}"
}

view_tasks() { crontab -l | grep "$(basename $0)" || echo "暂无定时任务"; }
delete_task_schedule() {
    read -e -p "任务编号: " num
    crontab -l | grep -v "$(basename $0).*${num}" | crontab -
    echo -e "${GREEN}定时任务删除完成${RESET}"
}

menu() {
    while true; do
        clear
        echo -e "${GREEN}===== Rsync 一键菜单工具 =====${RESET}"
        list_tasks
        echo
        view_tasks
        echo
        echo -e "${GREEN}1) 创建任务    2) 删除任务${RESET}"
        echo -e "${GREEN}3) 推送同步    4) 拉取同步${RESET}"
        echo -e "${GREEN}5) 创建定时    6) 删除定时${RESET}"
        echo -e "${GREEN}0) 退出${RESET}"
        read -e -p "选择: " choice
        case $choice in
            1) add_task ;;
            2) delete_task ;;
            3) run_task push ;;
            4) run_task pull ;;
            5) schedule_task ;;
            6) delete_task_schedule ;;
            0) exit 0 ;;
            *) echo "无效选择" ;;
        esac
        read -e -p "回车继续..."
    done
}

# -------------------------
# 启动逻辑
# -------------------------
if [[ "$1" == "push" || "$1" == "pull" ]]; then
    run_task "$1" "$2"
else
    menu
fi
