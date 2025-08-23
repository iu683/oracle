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

# 目录与文件
CLUSTER_DIR="/root/cluster"
SERVERS_FILE="$CLUSTER_DIR/servers.json"
LOG_DIR="$CLUSTER_DIR/logs"

mkdir -p "$CLUSTER_DIR"
mkdir -p "$LOG_DIR"

if [ ! -f "$SERVERS_FILE" ] || [ ! -s "$SERVERS_FILE" ]; then
    echo "[]" > "$SERVERS_FILE"
fi

send_stats() { echo -e ">>> [$1]"; }

# Python管理JSON函数
manage_servers() {
python3 - <<'EOF'
import json
import sys
import os

file_path = os.environ["SERVERS_FILE"]
op = sys.argv[1]

with open(file_path, "r") as f:
    servers = json.load(f)

if op == "list":
    if not servers:
        print("⚠️ 当前暂无服务器")
    else:
        for i, s in enumerate(servers):
            print(f"{i+1}. {s['name']} - {s['hostname']}:{s['port']} ({s['username']})")
elif op == "add":
    name, host, port, user, pwd = sys.argv[2:7]
    port = int(port)
    servers.append({"name": name, "hostname": host, "port": port, "username": user, "password": pwd, "remote_path": "/home/"})
    with open(file_path, "w") as f:
        json.dump(servers, f, indent=4)
    print(f"✅ 已添加服务器: {name} ({host})")
elif op == "delete":
    keyword = sys.argv[2]
    servers = [s for s in servers if keyword not in s["name"] and keyword not in s["hostname"]]
    with open(file_path, "w") as f:
        json.dump(servers, f, indent=4)
    print(f"✅ 已删除包含关键字 [{keyword}] 的服务器")
elif op == "edit":
    print("请手动编辑 JSON 文件:", file_path)
EOF
}

# 批量执行命令（并行 + 日志 + 自动重试 + 实时状态）
run_commands_on_servers() {
    cmd="$1"
    MAX_RETRIES=2
    servers=$(python3 - <<EOF
import json, os
with open(os.environ["SERVERS_FILE"], "r") as f:
    servers = json.load(f)
for s in servers:
    print(f"{s['username']}@{s['hostname']}:{s['port']}:{s['password']}:{s['name']}")
EOF
)

    declare -A STATUS
    pids=()

    for srv in $servers; do
        user=$(echo $srv | cut -d: -f1)
        host=$(echo $srv | cut -d: -f2)
        port=$(echo $srv | cut -d: -f3)
        pwd=$(echo $srv | cut -d: -f4)
        name=$(echo $srv | cut -d: -f5)
        logfile="$LOG_DIR/$name-$(date +%Y%m%d%H%M%S).log"
        STATUS["$name"]="等待执行"

        (
            retries=0
            while [ $retries -le $MAX_RETRIES ]; do
                STATUS["$name"]="执行中（尝试 $(($retries+1))/${MAX_RETRIES+1}）"
                # 清屏显示所有状态
                clear
                echo "===== 批量执行状态 ====="
                for n in "${!STATUS[@]}"; do
                    echo -e "$n: ${STATUS[$n]}"
                done
                echo "======================="
                if sshpass -p "$pwd" ssh -o StrictHostKeyChecking=no -p "$port" "$user@$host" "$cmd" &> "$logfile"; then
                    STATUS["$name"]="✅ 成功"
                    break
                else
                    STATUS["$name"]="❌ 失败，重试中（$(($retries+1))）"
                    retries=$((retries+1))
                    sleep 2
                fi
            done
            if [ $retries -gt $MAX_RETRIES ]; then
                STATUS["$name"]="❌ 最终失败"
            fi
        ) &
        pids+=($!)
    done

    # 等待所有任务完成
    for pid in "${pids[@]}"; do
        wait $pid
    done

    # 最终状态显示
    clear
    echo "===== 批量执行最终状态 ====="
    for n in "${!STATUS[@]}"; do
        echo -e "$n: ${STATUS[$n]}"
    done
    echo "============================"
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
                manage_servers list
                echo -e "${GREEN}=========================${RESET}"
                echo -e "${GREEN}1. 添加服务器${RESET}"
                echo -e "${GREEN}2. 删除服务器${RESET}"
                echo -e "${GREEN}3. 编辑服务器${RESET}"
                echo -e "${GREEN}4. 备份集群${RESET}"
                echo -e "${GREEN}5. 还原集群${RESET}"
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
                        manage_servers add "$name" "$host" "$port" "$user" "$pwd"
                        read -n1 -s -r -p "按任意键返回菜单..."
                        ;;
                    2)
                        read -e -p "请输入关键字删除: " keyword
                        manage_servers delete "$keyword"
                        read -n1 -s -r -p "按任意键返回菜单..."
                        ;;
                    3)
                        manage_servers edit
                        read -n1 -s -r -p "按任意键返回菜单..."
                        ;;
                    4)
                        cp "$SERVERS_FILE" "${SERVERS_FILE}.bak"
                        echo "✅ 已备份到 ${SERVERS_FILE}.bak"
                        read -n1 -s -r -p "按任意键返回菜单..."
                        ;;
                    5)
                        read -e -p "请输入要还原的备份文件路径: " backup_file
                        cp "$backup_file" "$SERVERS_FILE"
                        echo "✅ 已还原"
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
