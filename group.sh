#!/bin/bash
set -e

# 颜色
GREEN="\033[32m"
RED="\033[31m"
RESET="\033[0m"
YELLOW="\033[33m"

# 检查并安装 python3
if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${GREEN}检测到未安装 python3，正在安装...${RESET}"
    apt-get update && apt-get install -y python3 python3-pip
fi

# 检查并安装 sshpass
if ! command -v sshpass >/dev/null 2>&1; then
    echo -e "${GREEN}检测到未安装 sshpass，正在安装...${RESET}"
    apt-get update && apt-get install -y sshpass
fi

send_stats() { echo -e ">>> [$1]"; }

# 临时内存服务器列表
# 每台服务器是 "name:host:port:user:pwd"
SERVERS=()

# 显示服务器列表
list_servers() {
    if [ ${#SERVERS[@]} -eq 0 ]; then
        echo "⚠️ 当前暂无服务器"
    else
        for i in "${!SERVERS[@]}"; do
            IFS=":" read -r name host port user pwd <<< "${SERVERS[$i]}"
            echo "$((i+1)). $name - $host:$port ($user)"
        done
    fi
}

# 批量执行命令（异步执行 + 日志 + 最终状态）
run_commands_on_servers() {
    cmd="$1"
    if [ ${#SERVERS[@]} -eq 0 ]; then
        echo "⚠️ 当前没有服务器"
        read -n1 -s -r -p "按任意键返回..."
        return
    fi

    declare -A STATUS
    pids=()

    for srv in "${SERVERS[@]}"; do
        IFS=":" read -r name host port user pwd <<< "$srv"
        logfile="/tmp/${name}-$(date +%Y%m%d%H%M%S).log"
        STATUS["$name"]="执行中"

        (
            if sshpass -p "$pwd" ssh -o StrictHostKeyChecking=no -p "$port" "$user@$host" "$cmd" &> "$logfile"; then
                STATUS["$name"]="✅ 成功"
            else
                STATUS["$name"]="❌ 失败"
            fi
        ) &
        pids+=($!)
    done

    # 等待所有任务完成
    for pid in "${pids[@]}"; do
        wait $pid
    done

    # 显示最终状态
    echo "===== 批量执行最终状态 ====="
    for n in "${!STATUS[@]}"; do
        echo -e "$n: ${STATUS[$n]}"
    done
    echo "============================"
    read -n1 -s -r -p "按任意键返回菜单..."
}

# 一级菜单
while true; do
    clear
    send_stats "集群控制中心"
    echo -e "${GREEN}===== 一级菜单 =====${RESET}"
    echo -e "${GREEN}1. 服务器列表管理${RESET}"
    echo -e "${GREEN}2. 批量执行任务${RESET}"
    echo -e "${GREEN}0. 退出${RESET}"
    echo -e "${GREEN}=================${RESET}"
    read -e -p "请选择一级菜单: " main_choice

    case $main_choice in
        1)
            while true; do
                clear
                send_stats "服务器列表管理"
                echo -e "${GREEN}===== 当前服务器列表 =====${RESET}"
                list_servers
                echo -e "${GREEN}=========================${RESET}"
                echo -e "${GREEN}1. 添加服务器${RESET}"
                echo -e "${GREEN}2. 删除服务器${RESET}"
                echo -e "${GREEN}3. 编辑服务器（删除后重新添加）${RESET}"
                echo -e "${GREEN}0. 返回上级菜单${RESET}"
                read -e -p "请选择操作: " server_choice

                case $server_choice in
                    1)
                        read -e -p "服务器名称: " name
                        read -e -p "服务器IP: " host
                        read -e -p "服务器端口(默认22): " port
                        port=${port:-22}
                        read -e -p "用户名(默认root): " user
                        user=${user:-root}
                        read -e -p "密码: " pwd
                        SERVERS+=("$name:$host:$port:$user:$pwd")
                        echo "✅ 已添加服务器: $name"
                        read -n1 -s -r -p "按任意键返回菜单..."
                        ;;
                    2)
                        read -e -p "请输入关键字删除: " keyword
                        new_servers=()
                        for srv in "${SERVERS[@]}"; do
                            [[ $srv == *"$keyword"* ]] || new_servers+=("$srv")
                        done
                        SERVERS=("${new_servers[@]}")
                        echo "✅ 删除完成"
                        read -n1 -s -r -p "按任意键返回菜单..."
                        ;;
                    3)
                        echo "⚠️ 编辑服务器请直接删除后重新添加"
                        read -n1 -s -r -p "按任意键返回菜单..."
                        ;;
                    0) break ;;
                    *) echo "❌ 无效选项" ; sleep 1 ;;
                esac
            done
            ;;
        2)
            while true; do
                clear
                send_stats "批量执行任务"
                echo -e "${GREEN}===== 批量执行任务 =====${RESET}"
                echo -e "${GREEN}11. 安装IU工具箱${RESET}"
                echo -e "${GREEN}12. 更新系统${RESET}"
                echo -e "${GREEN}13. 清理系统${RESET}"
                echo -e "${GREEN}14. 安装docker${RESET}"
                echo -e "${GREEN}15. 安装BBR${RESET}"
                echo -e "${GREEN}16. 安装WAP${RESET}"
                echo -e "${GREEN}17. 设置上海时区${RESET}"
                echo -e "${GREEN}18. 开放所有端口${RESET}"
                echo -e "${GREEN}51. 自定义指令${RESET}"
                echo -e "${GREEN}0. 返回上级菜单${RESET}"
                read -e -p "请选择操作: " task_choice

                case $task_choice in
                    11) run_commands_on_servers "bash <(curl -fsSL https://raw.githubusercontent.com/Polarisiu/vps-toolbox/main/install.sh)" ;;
                    12) run_commands_on_servers "bash <(curl -sL https://raw.githubusercontent.com/Polarisiu/tool/main/update.sh)" ;;
                    13) run_commands_on_servers "bash <(curl -sL https://raw.githubusercontent.com/Polarisiu/tool/main/clear.sh)" ;;
                    14) run_commands_on_servers "bash <(curl -sL https://raw.githubusercontent.com/Polarisiu/app-store/main/Docker.sh)" ;;
                    15) run_commands_on_servers "wget --no-check-certificate -O tcpx.sh https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh && chmod +x tcpx.sh && ./tcpx.sh" ;;
                    16) run_commands_on_servers "wget https://www.moerats.com/usr/shell/swap.sh && bash swap.sh" ;;
                    17) run_commands_on_servers "timedatectl set-timezone Asia/Shanghai" ;;
                    18) run_commands_on_servers "bash <(curl -sL https://raw.githubusercontent.com/Polarisiu/tool/main/open_all_ports.sh)" ;;
                    51)
                        read -e -p "请输入自定义命令: " cmd
                        run_commands_on_servers "$cmd"
                        ;;
                    0) break ;;
                    *) echo "❌ 无效选项" ; sleep 1 ;;
                esac
            done
            ;;
        0)
            echo "👋 已退出管理菜单"
            break
            ;;
        *)
            echo "❌ 无效选项，请重新输入"
            sleep 1
            ;;
    esac
done
