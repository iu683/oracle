#!/bin/bash
set -e

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

install_fail2ban() {
    echo -e "${YELLOW}正在安装 Fail2Ban...${RESET}"
    if [ -f /etc/debian_version ]; then
        apt update
        apt install -y fail2ban curl wget
    elif [ -f /etc/redhat-release ]; then
        yum install -y epel-release
        yum install -y fail2ban curl wget
    else
        echo "不支持的操作系统"
        exit 1
    fi
    systemctl enable --now fail2ban
    sleep 1
}

configure_ssh() {
    read -p "请输入 SSH 端口（默认22）: " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}

    read -p "请输入最大失败尝试次数 maxretry（默认5）: " MAX_RETRY
    MAX_RETRY=${MAX_RETRY:-5}

    read -p "请输入封禁时间 bantime(秒，默认600) : " BAN_TIME
    BAN_TIME=${BAN_TIME:-600}

    mkdir -p /etc/fail2ban/jail.d
    cat >/etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = $MAX_RETRY
bantime  = $BAN_TIME
EOF

    systemctl restart fail2ban
    sleep 1
    echo -e "${GREEN}SSH 防暴力破解配置完成${RESET}"
}

uninstall_fail2ban() {
    echo -e "${RED}正在卸载 Fail2Ban...${RESET}"
    systemctl stop fail2ban || true
    if [ -f /etc/debian_version ]; then
        apt remove -y fail2ban
    elif [ -f /etc/redhat-release ]; then
        yum remove -y fail2ban
    fi
    echo -e "${GREEN}Fail2Ban 已卸载${RESET}"
}

fail2ban_menu() {
    while true; do
        clear
        echo "SSH 防暴力破解管理菜单"
        echo "------------------------"
        echo "1. 安装并开启SSH防暴力破解"
        echo "2. 关闭SSH防暴力破解"
        echo "3. 配置SSH防护参数"
        echo "4. 查看SSH拦截记录"
        echo "5. 查看防御规则列表"
        echo "6. 查看日志实时监控"
        echo "7. 卸载防御程序"
        echo "0. 退出"
        echo "------------------------"

        read -p $'\033[1;91m请输入你的选择: \033[0m' sub_choice

        case $sub_choice in
            1)
                # 安装 Fail2Ban（如果没安装）
                if ! command -v fail2ban-client >/dev/null 2>&1; then
                    install_fail2ban
                else
                    systemctl enable --now fail2ban
                fi
                # 配置 SSH 防护
                configure_ssh
                ;;
            2)
                if [ -f /etc/fail2ban/jail.d/sshd.local ]; then
                    sed -i '/enabled/s/true/false/' /etc/fail2ban/jail.d/sshd.local
                    systemctl restart fail2ban
                    sleep 1
                    echo -e "${YELLOW}SSH 防暴力破解已关闭${RESET}"
                    fail2ban-client status sshd
                else
                    echo -e "${RED}SSH 配置文件不存在，请先安装并开启 SSH 防护${RESET}"
                fi
                ;;
            3)
                if [ -f /etc/fail2ban/jail.d/sshd.local ]; then
                    configure_ssh
                else
                    echo -e "${RED}SSH 配置文件不存在，请先安装并开启 SSH 防护${RESET}"
                fi
                ;;
            4)
                check_fail2ban_running && fail2ban-client status sshd
                ;;
            5)
                check_fail2ban_running && fail2ban-client status
                ;;
            6)
                check_fail2ban_running && tail -f /var/log/fail2ban.log
                ;;
            7)
                uninstall_fail2ban
                break
                ;;
            0)
                break
                ;;
            *)
                echo "无效的选择，请重新输入"
                sleep 1
                ;;
        esac
    done
}

check_fail2ban_running() {
    if ! systemctl is-active --quiet fail2ban; then
        echo -e "${YELLOW}Fail2Ban 未运行，请先安装或启动${RESET}"
        return 1
    fi
    return 0
}

# 主逻辑
fail2ban_menu
