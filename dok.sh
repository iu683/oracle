#!/bin/bash
# ========================================
# 🐳 一键 VPS Docker 管理工具（完整整合版）
# ========================================

# -----------------------------
# 颜色
# -----------------------------
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

# -----------------------------
# 检查 root
# -----------------------------
root_use() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}请使用 root 用户运行脚本${RESET}"
        exit 1
    fi
}
# -----------------------------
# 重启 Docker
# -----------------------------
restart_docker() {
    root_use
    echo -e "${YELLOW}正在重启 Docker...${RESET}"
    systemctl restart docker 2>/dev/null || {
        pkill dockerd 2>/dev/null
        nohup dockerd >/dev/null 2>&1 &
        sleep 5
    }
    if docker info &>/dev/null; then
        echo -e "${GREEN}✅ Docker 已成功重启${RESET}"
    else
        echo -e "${RED}❌ Docker 重启失败，请检查日志${RESET}"
    fi
}

# -----------------------------
# 检测 Docker 是否运行
# -----------------------------
check_docker_running() {
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}Docker 未安装${RESET}"
        return 1
    fi
    if ! docker info &>/dev/null; then
        echo -e "${YELLOW}Docker 未运行，尝试启动...${RESET}"
        if systemctl list-unit-files | grep -q "^docker.service"; then
            systemctl start docker
        else
            nohup dockerd >/dev/null 2>&1 &
            sleep 5
        fi
    fi
    if ! docker info &>/dev/null; then
        echo -e "${RED}Docker 启动失败，请检查日志${RESET}"
        return 1
    fi
    echo -e "${GREEN}Docker 已启动${RESET}"
    return 0
}

# -----------------------------
# 自动检测国内/国外
# -----------------------------
detect_country() {
    local country=$(curl -s --max-time 5 ipinfo.io/country)
    if [[ "$country" == "CN" ]]; then
        echo "CN"
    else
        echo "OTHER"
    fi
}

# -----------------------------
# 安装/更新 Docker
# -----------------------------
docker_install() {
    root_use
    local country=$(detect_country)
    echo -e "${CYAN}检测到国家: $country${RESET}"
    if [ "$country" = "CN" ]; then
        echo -e "${YELLOW}使用国内源安装 Docker...${RESET}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": [
    "https://docker.0.unsee.tech",
    "https://docker.1panel.live",
    "https://registry.dockermirror.com",
    "https://docker.m.daocloud.io"
  ]
}
EOF
    else
        echo -e "${YELLOW}使用官方源安装 Docker...${RESET}"
        curl -fsSL https://get.docker.com | sh
    fi
    systemctl enable docker
    systemctl start docker
    echo -e "${GREEN}Docker 安装完成并已启动（已设置开机自启）${RESET}"
    echo -e "${YELLOW}⚠️ 切换到 iptables-legacy 以避免端口映射失败${RESET}"
    update-alternatives --set iptables /usr/sbin/iptables-legacy
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
    restart_docker
}

docker_update() {
    root_use
    echo -e "${YELLOW}正在更新 Docker...${RESET}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl restart docker
    echo -e "${GREEN}Docker 更新完成并已启动（已设置开机自启）${RESET}"
}

docker_install_update() {
    root_use
    if command -v docker &>/dev/null; then
        docker_update
    else
        docker_install
    fi
}

# -----------------------------
# 卸载 Docker（含 Compose）
# -----------------------------
docker_uninstall() {
    root_use
    echo -e "${RED}正在卸载 Docker 和 Docker Compose...${RESET}"
    systemctl stop docker 2>/dev/null
    systemctl disable docker 2>/dev/null
    pkill dockerd 2>/dev/null

    if command -v apt &>/dev/null; then
        apt remove -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io docker-compose-plugin || true
        apt purge -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io docker-compose-plugin || true
        apt autoremove -y
    elif command -v yum &>/dev/null; then
        yum remove -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io docker-compose-plugin || true
    fi

    rm -rf /var/lib/docker /etc/docker /var/lib/containerd /var/run/docker.sock /usr/local/bin/docker-compose
    echo -e "${GREEN}Docker 和 Docker Compose 已卸载干净${RESET}"
}

# -----------------------------
# Docker Compose 安装/更新
# -----------------------------
docker_compose_install_update() {
    root_use
    echo -e "${CYAN}正在安装/更新 Docker Compose...${RESET}"
    if ! command -v jq &>/dev/null; then
        if command -v apt &>/dev/null; then
            apt update -y && apt install -y jq
        elif command -v yum &>/dev/null; then
            yum install -y jq
        fi
    fi
    local latest=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
    latest=${latest:-"v2.30.0"}
    curl -L "https://github.com/docker/compose/releases/download/$latest/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}Docker Compose 已安装/更新到版本 $latest${RESET}"
}

# -----------------------------
# Docker IPv6
# -----------------------------
docker_ipv6_on() {
    root_use
    mkdir -p /etc/docker
    if [ -f /etc/docker/daemon.json ]; then
        jq '. + {ipv6:true,"fixed-cidr-v6":"fd00::/64"}' /etc/docker/daemon.json 2>/dev/null \
            >/etc/docker/daemon.json.tmp || echo '{"ipv6":true,"fixed-cidr-v6":"fd00::/64"}' > /etc/docker/daemon.json.tmp
    else
        echo '{"ipv6":true,"fixed-cidr-v6":"fd00::/64"}' > /etc/docker/daemon.json.tmp
    fi
    mv /etc/docker/daemon.json.tmp /etc/docker/daemon.json
    systemctl restart docker 2>/dev/null || nohup dockerd >/dev/null 2>&1 &
    echo -e "${GREEN}Docker IPv6 已开启${RESET}"
}

docker_ipv6_off() {
    root_use
    if [ -f /etc/docker/daemon.json ]; then
        jq 'del(.ipv6) | del(.["fixed-cidr-v6"])' /etc/docker/daemon.json > /etc/docker/daemon.json.tmp
        mv /etc/docker/daemon.json.tmp /etc/docker/daemon.json
        systemctl restart docker 2>/dev/null || nohup dockerd >/dev/null 2>&1 &
        echo -e "${GREEN}Docker IPv6 已关闭${RESET}"
    else
        echo -e "${YELLOW}Docker 配置文件不存在${RESET}"
    fi
}
# -----------------------------
# 开放所有端口（IPv4 + IPv6）
# -----------------------------
open_all_ports() {
    root_use
    read -p "⚠️ 确认要开放所有端口吗？这将允许所有入站/出站流量！(Y/N): " confirm
    [[ $confirm =~ [Yy] ]] || { echo -e "${YELLOW}操作已取消${RESET}"; return; }

    # IPv4
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -F

    # IPv6
    ip6tables -P INPUT ACCEPT
    ip6tables -P FORWARD ACCEPT
    ip6tables -P OUTPUT ACCEPT
    ip6tables -F

    echo -e "${GREEN}✅ 已开放所有端口（IPv4 + IPv6）${RESET}"
}


# -----------------------------
# iptables 切换
# -----------------------------
switch_iptables_legacy() {
    root_use
    if [ -x /usr/sbin/iptables-legacy ] && [ -x /usr/sbin/ip6tables-legacy ]; then
        update-alternatives --set iptables /usr/sbin/iptables-legacy
        update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
        echo -e "${GREEN}已切换到 iptables-legacy${RESET}"
        restart_docker
    else
        echo -e "${RED}系统未安装 iptables-legacy，无法切换${RESET}"
    fi
}

switch_iptables_nft() {
    root_use
    if [ -x /usr/sbin/iptables-nft ] && [ -x /usr/sbin/ip6tables-nft ]; then
        update-alternatives --set iptables /usr/sbin/iptables-nft
        update-alternatives --set ip6tables /usr/sbin/ip6tables-nft
        echo -e "${GREEN}已切换到 iptables-nft${RESET}"
        restart_docker
    else
        echo -e "${RED}系统未安装 iptables-nft，无法切换${RESET}"
    fi
}


# 当前 Docker 状态
docker_status() {
    if docker info &>/dev/null; then
        echo "运行中"
    else
        echo "未运行"
    fi
}

# 当前 iptables 模式
current_iptables() {
    ipt=$(update-alternatives --query iptables 2>/dev/null | grep 'Value:' | awk '{print $2}')
    if [[ $ipt == *legacy ]]; then
        echo "legacy"
    else
        echo "nft"
    fi
}

# 容器信息
docker_container_info() {
    total=$(docker ps -a -q | wc -l)
    running=$(docker ps -q | wc -l)
    echo "总容器: $total | 运行中: $running"
}


# -----------------------------
# Docker 容器管理
# -----------------------------
docker_ps() {
    if ! check_docker_running; then return; fi
    while true; do
        clear
        echo -e "${BOLD}${CYAN}===== Docker 容器管理 =====${RESET}"
        docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo -e "${GREEN}01. 创建新容器${RESET}"
        echo -e "${GREEN}02. 启动容器${RESET}"
        echo -e "${GREEN}03. 停止容器${RESET}"
        echo -e "${GREEN}04. 删除容器${RESET}"
        echo -e "${GREEN}05. 重启容器${RESET}"
        echo -e "${GREEN}06. 启动所有容器${RESET}"
        echo -e "${GREEN}07. 停止所有容器${RESET}"
        echo -e "${GREEN}08. 删除所有容器${RESET}"
        echo -e "${GREEN}09. 重启所有容器${RESET}"
        echo -e "${GREEN}10. 进入容器${RESET}"
        echo -e "${GREEN}11. 查看日志${RESET}"
        echo -e "${GREEN}12. 查看网络信息${RESET}"
        echo -e "${GREEN}13. 查看占用资源${RESET}"
        echo -e "${GREEN}0. 返回主菜单${RESET}"
        read -p "请选择: " choice
        case $choice in
            01|1) read -p "请输入创建命令: " cmd; $cmd ;;
            02|2) read -p "请输入容器名: " name; docker start $name ;;
            03|3) read -p "请输入容器名: " name; docker stop $name ;;
            04|4) read -p "请输入容器名: " name; docker rm -f $name ;;
            05|5) read -p "请输入容器名: " name; docker restart $name ;;
            06|6) containers=$(docker ps -a -q); [ -n "$containers" ] && docker start $containers || echo "无容器可启动" ;;
            07|7) containers=$(docker ps -q); [ -n "$containers" ] && docker stop $containers || echo "无容器正在运行" ;;
            08|8) read -p "确定删除所有容器? (Y/N): " c; [[ $c =~ [Yy] ]] && docker rm -f $(docker ps -a -q) ;;
            09|9) containers=$(docker ps -q); [ -n "$containers" ] && docker restart $containers || echo "无容器正在运行" ;;
            10) read -p "请输入容器名: " name; docker exec -it $name /bin/bash ;;
            11) read -p "请输入容器名: " name; docker logs -f $name ;;
            12) read -p "请输入容器名: " name; docker inspect $name | jq '.' ;;
            13) read -p "请输入容器名: " name; docker stats $name ;;
            0) break ;;
            *) echo "无效选择" ;;
        esac
        read -p "按回车继续..."
    done
}


# -----------------------------
# Docker 镜像管理
# -----------------------------
docker_image() {
    if ! check_docker_running; then return; fi
    while true; do
        clear
        echo -e "${BOLD}${CYAN}===== Docker 镜像管理 =====${RESET}"
        docker image ls
        echo -e "${GREEN}01. 拉取镜像${RESET}"
        echo -e "${GREEN}02. 更新镜像${RESET}"
        echo -e "${GREEN}03. 删除镜像${RESET}"
        echo -e "${GREEN}04. 删除所有镜像${RESET}"
        echo -e "${GREEN}0. 返回主菜单${RESET}"
        read -p "请选择: " choice
        case $choice in
            01|1) read -p "请输入镜像名: " imgs; for img in $imgs; do docker pull $img; done ;;
            02|2) read -p "请输入镜像名: " imgs; for img in $imgs; do docker pull $img; done ;;
            03|3) read -p "请输入镜像名: " imgs; for img in $imgs; do docker rmi -f $img; done ;;
            04|4) read -p "确定删除所有镜像? (Y/N): " c; [[ $c =~ [Yy] ]] && docker rmi -f $(docker images -q) ;;
            0) break ;;
            *) echo "无效选择" ;;
        esac
        read -p "按回车继续..."
    done
}

# -----------------------------
# Docker 卷管理
# -----------------------------
docker_volume() {
    if ! check_docker_running; then return; fi
    while true; do
        clear
        echo -e "${BOLD}${CYAN}===== Docker 卷管理 =====${RESET}"
        docker volume ls
        echo -e "${GREEN}1. 创建卷${RESET}"
        echo -e "${GREEN}2. 删除卷${RESET}"
        echo -e "${GREEN}3. 删除所有无用卷${RESET}"
        echo -e "${GREEN}0. 返回上一级菜单${RESET}"
        read -p "请输入选择: " choice
        case $choice in
            1) read -p "请输入卷名: " v; docker volume create $v ;;
            2) read -p "请输入卷名: " v; docker volume rm $v ;;
            3) docker volume prune -f ;;
            0) break ;;
            *) echo "无效选择" ;;
        esac
        read -p "按回车继续..."
    done
}

# -----------------------------
# 清理所有未使用资源
# -----------------------------
docker_cleanup() {
    root_use
    echo -e "${YELLOW}清理所有未使用容器、镜像、卷...${RESET}"
    docker system prune -af --volumes
    echo -e "${GREEN}清理完成${RESET}"
}

# -----------------------------
# Docker 网络管理
# -----------------------------
docker_network() {
    if ! check_docker_running; then return; fi
    while true; do
        clear
        echo -e "${BOLD}${CYAN}===== Docker 网络管理 =====${RESET}"
        docker network ls
        echo -e "${GREEN}1. 创建网络${RESET}"
        echo -e "${GREEN}2. 加入网络${RESET}"
        echo -e "${GREEN}3. 退出网络${RESET}"
        echo -e "${GREEN}4. 删除网络${RESET}"
        echo -e "${GREEN}0. 返回上一级菜单${RESET}"
        read -p "请输入你的选择: " sub_choice
        case $sub_choice in
            1) read -p "设置新网络名: " dockernetwork; docker network create $dockernetwork ;;
            2) read -p "加入网络名: " dockernetwork; read -p "容器名: " dockername; docker network connect $dockernetwork $dockername ;;
            3) read -p "退出网络名: " dockernetwork; read -p "容器名: " dockername; docker network disconnect $dockernetwork $dockername ;;
            4) read -p "请输入要删除的网络名: " dockernetwork; docker network rm $dockernetwork || echo -e "${RED}删除失败，网络可能被容器占用${RESET}" ;;
            0) break ;;
            *) echo "无效选择" ;;
        esac
        read -p "按回车继续..."
    done
}

# -----------------------------
# Docker 备份/恢复菜单
# -----------------------------
docker_backup_menu() {
    root_use
    while true; do
        clear
        echo -e "${BOLD}${CYAN}===== Docker 备份与恢复 =====${RESET}"
        echo -e "${GREEN}1. 备份 Docker${RESET}"
        echo -e "${GREEN}2. 恢复 Docker${RESET}"
        echo -e "${GREEN}3. 删除备份文件${RESET}"
        echo -e "${GREEN}0. 返回上一级菜单${RESET}"
        read -p "请选择: " choice
        case $choice in
            1)
                echo -e "${YELLOW}选择备份类型:${RESET}"
                echo "1. 容器"
                echo "2. 镜像"
                echo "3. 卷"
                echo "4. 全量"
                read -p "请输入选择: " btype
                read -p "请输入备份文件名（默认 docker_backup_$(date +%F).tar.gz）: " backup_name
                backup_name=${backup_name:-docker_backup_$(date +%F).tar.gz}
                mkdir -p /tmp/docker_backup

                [[ "$btype" == "1" || "$btype" == "4" ]] && {
                    docker ps -a -q | while read cid; do
                        cname=$(docker inspect --format '{{.Name}}' $cid | sed 's/\///g')
                        docker inspect $cid > /tmp/docker_backup/container_"$cname".json
                        docker export "$cid" -o /tmp/docker_backup/container_"$cname".tar
                    done
                }

                [[ "$btype" == "2" || "$btype" == "4" ]] && {
                    docker images -q | while read img; do
                        iname=$(docker image inspect --format '{{.RepoTags}}' $img | tr -d '[]/:')
                        docker save "$img" -o /tmp/docker_backup/image_"$iname".tar
                    done
                }

                [[ "$btype" == "3" || "$btype" == "4" ]] && {
                    docker volume ls -q | while read vol; do
                        tar -czf /tmp/docker_backup/volume_"$vol".tar.gz -C /var/lib/docker/volumes/"$vol"/_data .
                    done
                }

                tar -czf "$backup_name" -C /tmp docker_backup
                rm -rf /tmp/docker_backup
                echo -e "${GREEN}备份完成: $backup_name${RESET}"
                read -p "按回车继续..."
                ;;
            2)
                echo -e "${YELLOW}选择恢复类型:${RESET}"
                echo "1. 容器"
                echo "2. 镜像"
                echo "3. 卷"
                echo "4. 全量"
                read -p "请输入选择: " rtype
                read -p "请输入备份文件路径: " backup_file
                [[ ! -f "$backup_file" ]] && echo -e "${RED}备份文件不存在${RESET}" && read -p "按回车继续..." && continue
                mkdir -p /tmp/docker_restore
                tar -xzf "$backup_file" -C /tmp/docker_restore

                [[ "$rtype" == "1" || "$rtype" == "4" ]] && {
                    for cjson in /tmp/docker_restore/docker_backup/container_*.json; do
                        [[ -f "$cjson" ]] || continue
                        cname=$(basename "$cjson" | sed 's/container_\(.*\).json/\1/')
                        image=$(jq -r '.[0].Config.Image' "$cjson")
                        envs=$(jq -r '.[0].Config.Env | join(" -e ")' "$cjson")
                        ports=$(jq -r '.[0].HostConfig.PortBindings | to_entries | map("\(.value[0].HostPort):\(.key | split("/")[0])") | join(" -p ")' "$cjson")
                        mounts=$(jq -r '.[0].Mounts | map("-v \(.Source):\(.Destination)") | join(" ")' "$cjson")
                        network=$(jq -r '.[0].HostConfig.NetworkMode' "$cjson")
                        cmd="docker run -d --name $cname -e $envs -p $ports $mounts --network $network $image"
                        echo "正在创建容器: $cname"
                        eval $cmd
                    done
                }

                [[ "$rtype" == "2" || "$rtype" == "4" ]] && {
                    for img in /tmp/docker_restore/docker_backup/image_*.tar; do
                        [[ -f "$img" ]] || continue
                        docker load -i "$img"
                    done
                }

                [[ "$rtype" == "3" || "$rtype" == "4" ]] && {
                    for vol in /tmp/docker_restore/docker_backup/volume_*.tar.gz; do
                        [[ -f "$vol" ]] || continue
                        vol_name=$(basename "$vol" | sed 's/volume_\(.*\).tar.gz/\1/')
                        docker volume create "$vol_name"
                        tar -xzf "$vol" -C /var/lib/docker/volumes/"$vol_name"/_data
                    done
                }

                rm -rf /tmp/docker_restore
                echo -e "${GREEN}恢复完成${RESET}"
                read -p "按回车继续..."
                ;;
            3)
                read -p "请输入要删除的备份文件路径: " del_file
                [[ -f "$del_file" ]] && rm -f "$del_file" && echo -e "${GREEN}备份文件已删除${RESET}" || echo -e "${RED}备份文件不存在${RESET}"
                read -p "按回车继续..."
                ;;
            0) break ;;
            *) echo "无效选择"; read -p "按回车继续..." ;;
        esac
    done
}


# -----------------------------
# 主菜单
# -----------------------------
main_menu() {
    root_use
    while true; do
        clear
        echo -e "\033[36m"
        echo "  ____             _             "
        echo " |  _ \  ___   ___| | _____ _ __ "
        echo " | | | |/ _ \ / __| |/ / _ \ '__|"
        echo " | |_| | (_) | (__|   <  __/ |   "
        echo " |____/ \___/ \___|_|\_\___|_|   "
        echo -e "\033[33m🐳 一键 VPS Docker 管理工具${RESET}"

        echo -e "${YELLOW}当前 iptables 模式: $(current_iptables) | Docker 状态: $(docker_status)${RESET}"
        echo ""
        
        echo -e "${GREEN}01. 安装/更新 Docker（自动检测国内/国外源）${RESET}"
        echo -e "${GREEN}02. 安装/更新 Docker Compose${RESET}"
        echo -e "${GREEN}03. 卸载 Docker & Compose${RESET}"
        echo -e "${GREEN}04. 容器管理${RESET}"
        echo -e "${GREEN}05. 镜像管理${RESET}"
        echo -e "${GREEN}06. 开启 IPv6${RESET}"
        echo -e "${GREEN}07. 关闭 IPv6${RESET}"
        echo -e "${GREEN}08. 开放所有端口${RESET}"
        echo -e "${GREEN}09. 网络管理${RESET}"
        echo -e "${GREEN}10. 切换 iptables-legacy${RESET}"
        echo -e "${GREEN}11. 切换 iptables-nft${RESET}"
        echo -e "${GREEN}12. Docker 备份/恢复${RESET}"
        echo -e "${GREEN}13. 卷管理 ${RESET}"
        echo -e "${GREEN}14. 一键清理所有未使用容器/镜像/卷${RESET}"
        echo -e "${YELLOW}15. 重启 Docker${RESET}"
        echo -e "${GREEN}0.  退出${RESET}"

        read -p "请选择: " choice
        case $choice in
            01|1) docker_install_update ;;
            02|2) docker_compose_install_update ;;
            03|3) docker_uninstall ;;
            04|4) docker_ps ;;
            05|5) docker_image ;;
            06|6) docker_ipv6_on ;;
            07|7) docker_ipv6_off ;;
            08|8) open_all_ports ;;
            09|9) docker_network ;;
            10) switch_iptables_legacy ;;
            11) switch_iptables_nft ;;
            12) docker_backup_menu ;;
            13) docker_volume ;;
            14) docker_cleanup ;;
            15) restart_docker ;;
            0) exit 0 ;;
            *) echo "无效选择" ;;
        esac
        read -p "按回车继续..."
    done
}


# 启动脚本
main_menu
