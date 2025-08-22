#!/bin/bash
# PVE NAT VPS 管理脚本

# ============ 颜色定义 ============
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# ============ 函数定义 ============
function install_base() {
    echo -e "${YELLOW}开始进行环境检测...${RESET}"
    apt-get update -y && apt-get install -y wget curl

    output=$(bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/check_kernal.sh))
    echo "$output"

    if echo "$output" | grep -q "CPU不支持硬件虚拟化"; then
        echo -e "${RED}你的服务器不支持开设KVM小鸡，建议选择LXC模式${RESET}"
        sleep 2
        return

    elif echo "$output" | grep -q "本机符合要求"; then
        echo -e "${GREEN}本机符合开设kvm小鸡的要求${RESET}"
        read -p "确定要继续安装PVE吗？[y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            # 添加虚拟内存
            bash <(wget -qO- https://raw.githubusercontent.com/spiritLHLS/addswap/main/addswap.sh)
            # 安装 PVE
            bash <(wget -qO- https://raw.githubusercontent.com/spiritLHLS/pve/main/scripts/install_pve.sh)
            echo -e "${YELLOW}请等待20秒后重启，再运行菜单第2步${RESET}"
            read -p "是否立即重启？[y/N]: " reboot_c
            [[ "$reboot_c" =~ ^[Yy]$ ]] && reboot
        fi

    elif echo "$output" | grep -q "无apt包管理器命令"; then
        echo -e "${RED}你的系统不支持，请更换 Debian12 或 Ubuntu22.04${RESET}"
        sleep 2
    else
        echo -e "${RED}暂不能判定你的服务器状态，请考虑LXC模式${RESET}"
        sleep 2
    fi
}

function config_env() {
    if ! command -v pveversion >/dev/null 2>&1; then
        echo -e "${RED}检测到 PVE 未安装，请先执行第 1 步${RESET}"
        sleep 2
        return
    fi

    read -p "确认你已执行完第1步，是否继续？[y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        bash <(wget -qO- https://raw.githubusercontent.com/spiritLHLS/pve/main/scripts/install_pve.sh)
        echo -e "${YELLOW}开始配置环境...${RESET}"
        bash <(wget -qO- https://raw.githubusercontent.com/spiritLHLS/pve/main/scripts/build_backend.sh)
        echo -e "${YELLOW}开始自动配置宿主机的网关...${RESET}"
        bash <(wget -qO- https://raw.githubusercontent.com/spiritLHLS/pve/main/scripts/build_nat_network.sh)

        while true; do
            echo -e "${CYAN}请选择开设模式：${RESET}"
            echo "1. 手动开设KVM小鸡"
            echo "2. 批量自动开设KVM小鸡"
            read -p "请输入选项 [1/2]: " choose

            case $choose in
                1)
                    wget -qO buildvm.sh https://raw.githubusercontent.com/spiritLHLS/pve/main/scripts/buildvm.sh && chmod +x buildvm.sh
                    echo -e "${GREEN}手动开设请执行以下命令：${RESET}"
                    echo "./buildvm.sh VMID 用户名 密码 CPU 内存 硬盘 SSH端口 80端口 443端口 外网起 外网止 系统 存储盘 IPv6"
                    echo "./buildvm.sh 102 test1 oneclick123 1 512 10 40001 40002 40003 50000 50025 debian11 local N"
                    break
                    ;;
                2)
                    echo -e "${RED}注意: 默认用户不是 root，部分 root 密码是 ${GREEN}password${RED}，需要 sudo -i 切换${RESET}"
                    wget -qO create_vm.sh https://raw.githubusercontent.com/spiritLHLS/pve/main/scripts/create_vm.sh && chmod +x create_vm.sh && bash create_vm.sh
                    break
                    ;;
                *)
                    echo -e "${RED}输入错误，请输入 1 或 2${RESET}"
                    ;;
            esac
        done
    fi
}

function clean_all() {
    read -p "⚠️ 确认要删除所有虚拟机和网络配置吗？[y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        for vmid in $(qm list | awk 'NR>1 {print $1}'); do
            qm stop $vmid
            qm destroy $vmid
            rm -rf /var/lib/vz/images/$vmid*
        done
        iptables -t nat -F
        iptables -t filter -F
        systemctl restart networking.service
        systemctl restart ndpresponder.service 2>/dev/null || true
        iptables-save > /etc/iptables/rules.v4
        rm -rf vmlog vm*
        echo -e "${GREEN}已清理完毕${RESET}"
        sleep 2
    else
        echo "已取消操作"
    fi
}

# ============ 菜单主循环 ============
while true; do
    clear
    echo -e "${CYAN}========= PVE NAT VPS 管理菜单 =========${RESET}"
    echo "${GREEN}1. 环境检测 & 安装 PVE${RESET}"
    echo "${GREEN}2. 配置环境 & 开设 KVM 小鸡${RESET}"
    echo "${GREEN}3. 删除所有虚拟机 & 清理网络${RESET}"
    echo "${GREEN}0. 退出"
    echo "========================================="
    read -p "${GREEN}请选择操作 [0-3]: ${RESET}" choice

    case $choice in
        1) install_base ;;
        2) config_env ;;
        3) clean_all ;;
        0) echo "退出脚本"; exit 0 ;;
        *) echo -e "${RED}输入错误，请重新选择${RESET}" ;;
    esac
    echo -e "\n按任意键返回菜单..."
    read -n 1 -s
done
