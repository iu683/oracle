#!/bin/bash
set -e

# 颜色
gl_kjlan="\033[36m"
gl_bai="\033[0m"
gl_huang="\033[33m"

# 目录
CLUSTER_DIR="/root/cluster"
SERVERS_FILE="$CLUSTER_DIR/servers.py"

mkdir -p "$CLUSTER_DIR"
touch "$SERVERS_FILE"

# 统计函数（如果没有可直接删掉或写个空函数）
send_stats() {
    echo -e ">>> [$1]"
}

# 远程批量执行（这里仅做占位，需你自己实现）
run_commands_on_servers() {
    echo "批量执行命令: $1"
    # TODO: 实现你的批量执行逻辑，比如用 paramiko 或 sshpass
}

# python任务占位
cluster_python3() {
    echo "执行Python任务: $py_task"
}

# 主循环
while true; do
    clear
    send_stats "集群控制中心"
    echo "服务器集群控制"
    cat "$SERVERS_FILE"
    echo
    echo -e "${gl_kjlan}------------------------${gl_bai}"
    echo -e "${gl_kjlan}服务器列表管理${gl_bai}"
    echo -e "${gl_kjlan}1.  ${gl_bai}添加服务器               ${gl_kjlan}2.  ${gl_bai}删除服务器            ${gl_kjlan}3.  ${gl_bai}编辑服务器"
    echo -e "${gl_kjlan}4.  ${gl_bai}备份集群                 ${gl_kjlan}5.  ${gl_bai}还原集群"
    echo -e "${gl_kjlan}------------------------${gl_bai}"
    echo -e "${gl_kjlan}批量执行任务${gl_bai}"
    echo -e "${gl_kjlan}11. ${gl_bai}安装科技lion脚本         ${gl_kjlan}12. ${gl_bai}更新系统              ${gl_kjlan}13. ${gl_bai}清理系统"
    echo -e "${gl_kjlan}14. ${gl_bai}安装docker               ${gl_kjlan}15. ${gl_bai}安装BBR3              ${gl_kjlan}16. ${gl_bai}设置1G虚拟内存"
    echo -e "${gl_kjlan}17. ${gl_bai}设置时区到上海           ${gl_kjlan}18. ${gl_bai}开放所有端口	       ${gl_kjlan}51. ${gl_bai}自定义指令"
    echo -e "${gl_kjlan}------------------------${gl_bai}"
    echo -e "${gl_kjlan}0.  ${gl_bai}返回主菜单/退出"
    echo -e "${gl_kjlan}------------------------${gl_bai}"
    read -e -p "请输入你的选择: " sub_choice

    case $sub_choice in
        1)
            send_stats "添加集群服务器"
            read -e -p "服务器名称: " server_name
            read -e -p "服务器IP: " server_ip
            read -e -p "服务器端口(默认22): " server_port
            server_port=${server_port:-22}
            read -e -p "服务器用户名(默认root): " server_username
            server_username=${server_username:-root}
            read -e -p "服务器用户密码: " server_password

            sed -i "/servers = \[/a\    {\"name\": \"$server_name\", \"hostname\": \"$server_ip\", \"port\": $server_port, \"username\": \"$server_username\", \"password\": \"$server_password\", \"remote_path\": \"/home/\"}," "$SERVERS_FILE"
            echo "✅ 已添加服务器: $server_name ($server_ip)"
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;

        2)
            send_stats "删除集群服务器"
            read -e -p "请输入需要删除的关键字: " rmserver
            sed -i "/$rmserver/d" "$SERVERS_FILE"
            echo "✅ 已删除包含关键字 [$rmserver] 的服务器配置"
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;

        3)
            send_stats "编辑集群服务器"
            command -v nano >/dev/null 2>&1 || apt-get install -y nano
            nano "$SERVERS_FILE"
            ;;

        4)
            clear
            send_stats "备份集群"
            echo -e "请下载 ${gl_huang}$SERVERS_FILE${gl_bai} 完成备份！"
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;

        5)
            clear
            send_stats "还原集群"
            echo "请上传新的 servers.py 到 $CLUSTER_DIR/"
            read -n 1 -s -r -p "上传完成后，按任意键返回菜单..."
            ;;

        11) py_task="install_kejilion.py"; cluster_python3 ;;
        12) run_commands_on_servers "k update" ;;
        13) run_commands_on_servers "k clean" ;;
        14) run_commands_on_servers "k docker install" ;;
        15) run_commands_on_servers "k bbr3" ;;
        16) run_commands_on_servers "k swap 1024" ;;
        17) run_commands_on_servers "k time Asia/Shanghai" ;;
        18) run_commands_on_servers "k iptables_open" ;;
        51)
            send_stats "自定义执行命令"
            read -e -p "请输入批量执行的命令: " mingling
            run_commands_on_servers "$mingling"
            ;;

        0)
            echo "👋 已退出管理菜单"
            break
            ;;
        *)
            echo "❌ 无效的选项，请重新输入！"
            sleep 1
            ;;
    esac
done
