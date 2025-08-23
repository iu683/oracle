#!/bin/bash
# PVE NAT VPS 管理脚本

# ============ 颜色定义 ============
GREEN="\033[32m"
RESET="\033[0m"

# ============ 函数定义 ============
function install_base() {
    echo "开始进行环境检测..."
    apt-get update -y && apt-get install -y wget curl

    output=$(bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/check_kernal.sh))
    echo "$output"

    if echo "$output" | grep -q "CPU不支持硬件虚拟化"; then
        echo "你的服务器不支持开设KVM小鸡，建议选择LXC模式"
        sleep 2
        return

    elif echo "$output" | grep -q "本机符合要求"; then
        echo "本机符合开设kvm小鸡的要求"
        read -p "确定要继续安装PVE吗？[y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            # 添加虚拟内存
            bash <(wget -qO- https://raw.githubusercontent.com/spiritLHLS/addswap/main/addswap.sh)
            # 安装 PVE
            bash <(wget -qO- https://raw.githubusercontent.com/spiritLHLS/pve/main/scripts/install_pve.sh)
            echo "请等待20秒后重启，再运行菜单第2步"
            read -p "是否立即重启？[y/N]: " reboot_c
            [[ "$reboot_c" =~ ^[Yy]$ ]] && reboot
        fi

    elif echo "$output" | grep -q "无apt包管理器命令"; then
        echo "你的系统不支持，请更换 Debian12 或 Ubuntu22.04"
        sleep 2
    else
        echo "暂不能判定你的服务器状态，请考虑LXC模式"
        sleep 2
    fi
}

function config_env() {
    if ! command -v pveversion >/dev/null 2>&1; then
        echo "检测到 PVE 未安装，请先执行第 1 步"
        sleep 2
        return
    fi

    read -p "确认你已执行完第1步，是否继续？[y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        bash <(wget -qO- https://raw.githubusercontent.com/spiritLHLS/pve/main/scripts/install_pve.sh)
        echo "开始配置环境..."
        bash <(wget -qO- https://raw.githubusercontent.com/spiritLHLS/pve/main/scripts/build_backend.sh)
        echo "开始自动配置宿主机的网关..."
        bash <(wget -qO- https://raw.githubusercontent.com/spiritLHLS/pve/main/scripts/build_nat_network.sh)

        while true; do
            echo "请选择开设模式："
            echo "1. 手动开设KVM小鸡"
            echo "2. 批量自动开设KVM小鸡"
            read -p "请输入选项 [1/2]: " choose

            case $choose in
                1)
                    wget -qO buildvm.sh https://raw.githubusercontent.com/spiritLHLS/pve/main/scripts/buildvm.sh && chmod +x buildvm.sh
                    echo "手动开设请执行以下命令："
                    echo "./buildvm.sh VMID 用户名 密码 CPU 内存 硬盘 SSH端口 80端口 443端口 外网起 外网止 系统 存储盘 IPv6"
                    echo "./buildvm.sh 102 test1 oneclick123 1 512 10 40001 40002 40003 50000 50025 debian11 local N"
                    break
                    ;;
                2)
                    echo "注意: 默认用户不是 root，部分 root 密码是 password，需要 sudo -i 切换"
                    wget -qO create_vm.sh https://raw.githubusercontent.com/spiritLHLS/pve/main/scripts/create_vm.sh && chmod +x create_vm.sh && bash create_vm.sh
                    break
                    ;;
                *)
                    echo "输入错误，请输入 1 或 2"
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
        echo "已清理完毕"
        sleep 2
    else
        echo "已取消操作"
    fi
}

# ============ 菜单主循环 ============
while true; do
    clear
    echo -e "${GREEN}========= PVE NAT VPS 管理菜单 =========${RESET}"
    echo -e "${GREEN}1. 环境检测 & 安装 PVE${RESET}"
    echo -e "${GREEN}2. 配置环境 & 开设 KVM 小鸡${RESET}"
    echo -e "${GREEN}3. 删除所有虚拟机 & 清理网络${RESET}"
    echo -e "${GREEN}0. 退出${RESET}"
    echo "========================================="
    read -p "请选择操作 [0-3]: " choice

    case $choice in
        1) install_base ;;
        2) config_env ;;
        3) clean_all ;;
        0) echo "退出脚本"; exit 0 ;;
        *) echo "输入错误，请重新选择" ;;
    esac

    echo ""
    read -rsp "按任意键返回菜单..." -n1
done
