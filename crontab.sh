#!/bin/bash
set -e

# 颜色
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

# 安装并启动 crontab 服务
install_crontab_if_missing() {
    if ! command -v crontab &>/dev/null; then
        echo -e "${YELLOW}未检测到 crontab，正在尝试安装...${RESET}"
        if [[ -f /etc/debian_version ]]; then
            apt update && apt install -y cron
            systemctl enable cron
            systemctl start cron
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y cronie
            systemctl enable crond
            systemctl start crond
        elif [[ -f /etc/alpine-release ]]; then
            apk add --no-cache dcron
            rc-update add crond
            rc-service crond start
        else
            echo -e "${RED}无法自动识别系统类型，请手动安装 crontab${RESET}"
            exit 1
        fi
        echo -e "${GREEN}crontab 安装完成并已启动服务！${RESET}"
    else
        # 已安装，确保服务启动
        if [[ -f /etc/debian_version ]]; then
            systemctl enable cron
            systemctl start cron
        elif [[ -f /etc/redhat-release ]]; then
            systemctl enable crond
            systemctl start crond
        elif [[ -f /etc/alpine-release ]]; then
            rc-update add crond
            rc-service crond start
        fi
    fi
}

# 发送统计（示例）
send_stats() {
    local action="$1"
    echo -e "${YELLOW}[统计] $action${RESET}"
}

# 校验数字范围
validate_number() {
    local value="$1"
    local min="$2"
    local max="$3"
    local name="$4"

    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
        echo -e "${RED}${name} 输入无效，应在 $min 到 $max 之间${RESET}"
        return 1
    fi
    return 0
}

# 添加任务
add_cron_task() {
    read -e -p "请输入新任务的执行命令: " newquest
    echo "------------------------"
    echo "1. 每月任务                 2. 每周任务"
    echo "3. 每天任务                 4. 每小时任务"
    echo "------------------------"
    read -e -p "请选择任务类型: " dingshi
    case $dingshi in
        1)
            read -e -p "每月的几号执行任务？ (1-30): " day
            validate_number "$day" 1 30 "日期" || return
            (crontab -l 2>/dev/null; echo "0 0 $day * * $newquest") | crontab -
            ;;
        2)
            read -e -p "周几执行任务？ (0-6, 0=周日): " weekday
            validate_number "$weekday" 0 6 "星期" || return
            (crontab -l 2>/dev/null; echo "0 0 * * $weekday $newquest") | crontab -
            ;;
        3)
            read -e -p "每天几点执行任务？（小时，0-23）: " hour
            validate_number "$hour" 0 23 "小时" || return
            (crontab -l 2>/dev/null; echo "0 $hour * * * $newquest") | crontab -
            ;;
        4)
            read -e -p "每小时第几分钟执行任务？（分钟，0-59）: " minute
            validate_number "$minute" 0 59 "分钟" || return
            (crontab -l 2>/dev/null; echo "$minute * * * * $newquest") | crontab -
            ;;
        *)
            echo -e "${RED}无效选择${RESET}"
            return
            ;;
    esac
    send_stats "添加定时任务"
    echo -e "${GREEN}任务添加成功！${RESET}"
}

# 删除任务
delete_cron_task() {
    read -e -p "请输入需要删除任务的关键字: " kquest
    echo "以下任务将被删除："
    crontab -l | grep "$kquest" || { echo "未找到匹配任务"; return; }
    read -p "确认删除吗? (y/n): " yn
    if [[ $yn == "y" ]]; then
        crontab -l | grep -v "$kquest" | crontab -
        send_stats "删除定时任务"
        echo -e "${GREEN}删除完成！${RESET}"
    fi
}

# 编辑任务
edit_cron_task() {
    crontab -e
    send_stats "编辑定时任务"
}

# 定时任务管理菜单
cron_menu() {
    send_stats "进入定时任务管理"
    install_crontab_if_missing
    while true; do
        clear
        echo -e "${GREEN}=== 定时任务管理 ===${RESET}"
        echo ""
        echo "当前定时任务列表:"
        crontab -l 2>/dev/null || echo "(无定时任务)"
        echo ""
        echo "操作:"
        echo "------------------------"
        echo "1. 添加定时任务"
        echo "2. 删除定时任务"
        echo "3. 编辑定时任务"
        echo "0. 退出脚本"
        echo "------------------------"
        read -e -p "请输入你的选择: " sub_choice

        case $sub_choice in
            1) add_cron_task ;;
            2) delete_cron_task ;;
            3) edit_cron_task ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选择，请重新输入${RESET}" ;;
        esac

        echo -e "${YELLOW}按回车继续...${RESET}"
        read
    done
}

# 启动直接进入定时任务管理
cron_menu
