#!/bin/bash

# ================== 颜色定义 ==================
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# ================== 检查 root ==================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行此脚本！${RESET}"
    exit 1
fi

# ================== 安装目录 ==================
INSTALL_DIR="/www/wwwroot/mcy-shop"

# ================== 检查服务状态 ==================
check_status() {
    cd "$INSTALL_DIR"
    # 尝试重启不会真正执行，只是用来检测状态
    STATUS=$(mcy service.restart 2>&1)
    if echo "$STATUS" | grep -qi "successfully"; then
        echo -e "${GREEN}服务状态: 运行中${RESET}"
    else
        echo -e "${RED}服务状态: 未启动${RESET}"
    fi
}

# ================== 菜单函数 ==================
show_menu() {
    echo -e "${CYAN}"
    echo "=================== MCY 全功能管理菜单 ==================="
    check_status
    echo "1. 启动服务"
    echo "2. 停止服务"
    echo "3. 重启服务"
    echo "4. 卸载服务"
    echo "5. 安装服务"
    echo "6. 更新系统"
    echo "7. 生成数据库模型"
    echo "8. 创建语言包"
    echo "9. 删除语言包"
    echo "10. 批量删除语言包"
    echo "11. 查看语言代码"
    echo "12. 压缩 JS"
    echo "13. 压缩 CSS"
    echo "14. 压缩 JS+CSS"
    echo "15. 停止插件"
    echo "16. 查看运行插件"
    echo "17. 重置超级管理员密码"
    echo "18. 添加 Composer 依赖"
    echo "19. 删除 Composer 依赖"
    echo "20. 导入异次元 V3 用户数据"
    echo "21. 退出"
    echo "=========================================================="
    echo -ne "${RESET}请选择操作 [1-21]: "
}

# ================== 主循环 ==================
while true; do
    show_menu
    read choice
    case $choice in
        1)
            cd "$INSTALL_DIR" && mcy service.start
            ;;
        2)
            cd "$INSTALL_DIR" && mcy service.stop
            ;;
        3)
            cd "$INSTALL_DIR" && mcy service.restart
            ;;
        4)
            cd "$INSTALL_DIR" && mcy service.uninstall
            ;;
        5)
            cd "$INSTALL_DIR" && mcy service.install
            ;;
        6)
            cd "$INSTALL_DIR" && mcy kit.update
            ;;
        7)
            echo -ne "请输入表名（空格隔开）: "
            read tables
            cd "$INSTALL_DIR" && mcy database.model.create $tables
            ;;
        8)
            echo -ne "请输入原文: "
            read original
            echo -ne "请输入译文: "
            read translation
            echo -ne "请输入语言代码: "
            read lang
            cd "$INSTALL_DIR" && mcy language.create "$original" "$translation" "$lang"
            ;;
        9)
            echo -ne "请输入原文: "
            read original
            echo -ne "请输入语言代码: "
            read lang
            cd "$INSTALL_DIR" && mcy language.del "$original" "$lang"
            ;;
        10)
            echo -ne "请输入要删除的原文（空格隔开，如有空格请用双引号包裹）: "
            read originals
            cd "$INSTALL_DIR" && mcy language.all.del $originals
            ;;
        11)
            cd "$INSTALL_DIR" && mcy language.code
            ;;
        12)
            cd "$INSTALL_DIR" && mcy compress.js.merge
            ;;
        13)
            cd "$INSTALL_DIR" && mcy compress.css.merge
            ;;
        14)
            cd "$INSTALL_DIR" && mcy compress.all
            ;;
        15)
            echo -ne "请输入插件标识: "
            read plugin
            echo -ne "请输入用户ID（可留空代表主站插件）: "
            read userid
            cd "$INSTALL_DIR" && mcy plugin.stop "$plugin" "$userid"
            ;;
        16)
            echo -ne "请输入用户ID（可留空代表主站插件）: "
            read userid
            cd "$INSTALL_DIR" && mcy plugin.startups "$userid"
            ;;
        17)
            echo -ne "请输入新密码: "
            read newpass
            cd "$INSTALL_DIR" && mcy kit.reset "$newpass"
            ;;
        18)
            echo -ne "请输入 Composer 包名: "
            read package
            cd "$INSTALL_DIR" && mcy composer.require "$package"
            ;;
        19)
            echo -ne "请输入要删除的 Composer 包名: "
            read package
            cd "$INSTALL_DIR" && mcy composer.remove "$package"
            ;;
        20)
            echo -ne "请输入 .sql 文件名（放在根目录下）: "
            read sqlfile
            cd "$INSTALL_DIR" && mcy migration.v3.user "$sqlfile"
            ;;
        21)
            echo -e "${YELLOW}退出管理菜单${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请输入 1-21${RESET}"
            ;;
    esac
    echo -e "\n${CYAN}操作完成，按 Enter 返回菜单...${RESET}"
    read
done
