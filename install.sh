#!/bin/bash

# Git Scripts 安装脚本 - 完整版
# 自动配置 git mysync 和 git mypush 命令

# 配置
REPO_BASE="https://raw.githubusercontent.com/Yuyang-Du-NTU/Scripts/main"
SYNC_SCRIPT_URL="${REPO_BASE}/git-mysync.sh"
PUSH_SCRIPT_URL="${REPO_BASE}/git-mypush.sh"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 打印带颜色的消息
print_msg() {
    local color=$1
    shift
    local message="$@"
    echo -e "${color}${message}${NC}"
}

# 显示横幅
show_banner() {
    echo
    print_msg $CYAN "╔══════════════════════════════════════════════╗"
    print_msg $CYAN "║         Git Scripts 安装程序 v2.0            ║"
    print_msg $CYAN "║                                              ║"
    print_msg $CYAN "║  - git mysync: 智能同步所有分支和标签       ║"
    print_msg $CYAN "║  - git mypush: 智能推送已提交的更改         ║"
    print_msg $CYAN "╚══════════════════════════════════════════════╝"
    echo
}

# 检查系统环境
check_system() {
    print_msg $BLUE "[SYSTEM] 检查系统环境..."
    
    # 检测操作系统
    local os="unknown"
    case "$OSTYPE" in
        linux*)   os="Linux" ;;
        darwin*)  os="macOS" ;;
        msys*)    os="Windows (Git Bash)" ;;
        cygwin*)  os="Windows (Cygwin)" ;;
        *)        os="Unknown ($OSTYPE)" ;;
    esac
    echo "  - 操作系统: $os"
    
    # 检查 Git 版本
    if command -v git &> /dev/null; then
        local git_version=$(git --version | cut -d' ' -f3)
        echo "  - Git 版本: $git_version"
    else
        print_msg $RED "[ERROR] Git 未安装！请先安装 Git"
        exit 1
    fi
    
    # 检查网络工具
    local downloader=""
    if command -v curl &> /dev/null; then
        downloader="curl"
        echo "  - 下载工具: curl"
    elif command -v wget &> /dev/null; then
        downloader="wget"
        echo "  - 下载工具: wget"
    else
        print_msg $RED "[ERROR] 需要 curl 或 wget！"
        exit 1
    fi
    
    # 检查 Git 用户配置
    local git_user=$(git config --global user.name || echo "未设置")
    local git_email=$(git config --global user.email || echo "未设置")
    echo "  - Git 用户: $git_user <$git_email>"
    
    if [[ "$git_user" == "未设置" ]]; then
        print_msg $YELLOW "[WARN] 建议设置 Git 用户名: git config --global user.name \"Your Name\""
    fi
    
    echo
    return 0
}

# 创建临时目录
create_temp_dir() {
    # 使用更兼容的方式创建临时目录
    if [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]]; then
        # Windows
        TEMP_DIR="${TEMP:-/tmp}/git-scripts-$$"
        mkdir -p "$TEMP_DIR"
    else
        # Unix-like
        TEMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'git-scripts')
    fi
    
    # 确保退出时清理
    trap "rm -rf \"$TEMP_DIR\" 2>/dev/null" EXIT INT TERM
    
    print_msg $BLUE "[INFO] 创建临时目录: $TEMP_DIR"
}

# 下载脚本文件
download_scripts() {
    print_msg $BLUE "[DOWNLOAD] 正在下载脚本文件..."
    
    local success=true
    
    # 下载 mysync 脚本
    echo -n "  - 下载 git-mysync.sh... "
    if command -v curl &> /dev/null; then
        if curl -fsSL "${SYNC_SCRIPT_URL}" -o "${TEMP_DIR}/git-mysync.sh" 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            print_msg $RED "[ERROR] 无法下载 git-mysync.sh"
            success=false
        fi
    else
        if wget -q "${SYNC_SCRIPT_URL}" -O "${TEMP_DIR}/git-mysync.sh" 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            print_msg $RED "[ERROR] 无法下载 git-mysync.sh"
            success=false
        fi
    fi
    
    # 下载 mypush 脚本
    echo -n "  - 下载 git-mypush.sh... "
    if command -v curl &> /dev/null; then
        if curl -fsSL "${PUSH_SCRIPT_URL}" -o "${TEMP_DIR}/git-mypush.sh" 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            print_msg $RED "[ERROR] 无法下载 git-mypush.sh"
            success=false
        fi
    else
        if wget -q "${PUSH_SCRIPT_URL}" -O "${TEMP_DIR}/git-mypush.sh" 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            print_msg $RED "[ERROR] 无法下载 git-mypush.sh"
            success=false
        fi
    fi
    
    if $success; then
        print_msg $GREEN "[OK] 脚本下载完成"
        
        # 验证下载的文件
        local sync_size=$(wc -c < "${TEMP_DIR}/git-mysync.sh" 2>/dev/null || echo "0")
        local push_size=$(wc -c < "${TEMP_DIR}/git-mypush.sh" 2>/dev/null || echo "0")
        echo "  - git-mysync.sh: ${sync_size} 字节"
        echo "  - git-mypush.sh: ${push_size} 字节"
        
        if [[ "$sync_size" -lt 1000 ]] || [[ "$push_size" -lt 1000 ]]; then
            print_msg $RED "[ERROR] 下载的文件大小异常，可能下载失败"
            return 1
        fi
    else
        return 1
    fi
    
    echo
    return 0
}

# 处理脚本内容以适配不同平台
process_script_content() {
    local script_file="$1"
    local script_content=""
    
    # 读取脚本内容
    script_content=$(<"$script_file")
    
    # 使用更精确的转义策略
    # 1. 先转义反斜杠
    # 2. 转义双引号
    # 3. 转义美元符号（但保留 $@ 等特殊变量）
    script_content=$(printf '%s' "$script_content" | \
        sed 's/\\/\\\\/g' | \
        sed 's/"/\\"/g' | \
        sed 's/\$\([^@#*0-9{]\)/\\\$\1/g')
    
    echo "$script_content"
}

# 创建 Git aliases
create_git_aliases() {
    print_msg $BLUE "[INSTALL] 正在配置 Git aliases..."
    
    # 处理脚本内容
    local sync_script=$(process_script_content "${TEMP_DIR}/git-mysync.sh")
    local push_script=$(process_script_content "${TEMP_DIR}/git-mypush.sh")
    
    # 备份现有的 aliases（如果存在）
    local backup_needed=false
    if git config --global --get alias.mysync &>/dev/null; then
        print_msg $YELLOW "[WARN] 发现已存在的 git mysync，将进行备份"
        git config --global alias.mysync-backup "$(git config --global --get alias.mysync)"
        backup_needed=true
    fi
    if git config --global --get alias.mypush &>/dev/null; then
        print_msg $YELLOW "[WARN] 发现已存在的 git mypush，将进行备份"
        git config --global alias.mypush-backup "$(git config --global --get alias.mypush)"
        backup_needed=true
    fi
    
    if $backup_needed; then
        print_msg $YELLOW "[INFO] 原有命令已备份为 git mysync-backup 和 git mypush-backup"
    fi
    
    # 创建新的 aliases
    echo -n "  - 配置 git mysync... "
    if git config --global alias.mysync "!bash -c \"${sync_script}\" -- "; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        print_msg $RED "[ERROR] 配置 git mysync 失败"
        return 1
    fi
    
    echo -n "  - 配置 git mypush... "
    if git config --global alias.mypush "!bash -c \"${push_script}\" -- "; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        print_msg $RED "[ERROR] 配置 git mypush 失败"
        return 1
    fi
    
    print_msg $GREEN "[OK] Git aliases 配置完成"
    echo
    return 0
}

# 验证安装
verify_installation() {
    print_msg $BLUE "[VERIFY] 验证安装结果..."
    
    local all_good=true
    
    # 检查 mysync
    echo -n "  - 检查 git mysync... "
    if git config --global --get alias.mysync &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        # 获取 alias 大小以确保不是空的
        local mysync_size=$(git config --global --get alias.mysync | wc -c)
        if [[ "$mysync_size" -lt 100 ]]; then
            print_msg $YELLOW "    [WARN] git mysync 配置可能不完整"
            all_good=false
        fi
    else
        echo -e "${RED}✗${NC}"
        all_good=false
    fi
    
    # 检查 mypush
    echo -n "  - 检查 git mypush... "
    if git config --global --get alias.mypush &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        # 获取 alias 大小以确保不是空的
        local mypush_size=$(git config --global --get alias.mypush | wc -c)
        if [[ "$mypush_size" -lt 100 ]]; then
            print_msg $YELLOW "    [WARN] git mypush 配置可能不完整"
            all_good=false
        fi
    else
        echo -e "${RED}✗${NC}"
        all_good=false
    fi
    
    # 显示配置文件位置
    local config_file=$(git config --global --list --show-origin | grep "alias.mysync" | cut -d: -f1 | head -1)
    if [[ -n "$config_file" ]]; then
        echo "  - 配置文件: $config_file"
    fi
    
    echo
    
    if $all_good; then
        print_msg $GREEN "[OK] 安装验证通过"
        return 0
    else
        print_msg $RED "[ERROR] 安装验证失败"
        return 1
    fi
}

# 显示使用说明
show_usage() {
    echo
    print_msg $GREEN "═══════════════════════════════════════════════"
    print_msg $GREEN "          安装成功！🎉"
    print_msg $GREEN "═══════════════════════════════════════════════"
    echo
    print_msg $PURPLE "可用命令："
    echo
    print_msg $CYAN "1. git mysync - 同步所有远程分支和标签"
    echo "   选项："
    echo "   -f, --force     跳过工作区检查"
    echo "   -q, --quiet     静默模式"
    echo "   -h, --help      显示帮助"
    echo
    print_msg $CYAN "2. git mypush - 智能推送已提交的更改"
    echo "   选项："
    echo "   -d, --default   自动提交并推送"
    echo "   -c, --current   只推送当前分支"
    echo "   -t, --tags      只推送标签"
    echo "   -f, --force     强制推送当前分支"
    echo "   -h, --help      显示帮助"
    echo
    print_msg $PURPLE "使用示例："
    echo "   git mysync              # 同步所有分支"
    echo "   git mypush              # 推送已提交的更改"
    echo "   git mypush -d           # 自动提交并推送"
    echo "   git mypush -c           # 只推送当前分支"
    echo "   git mypush -d -c        # 自动提交并只推送当前分支"
    echo
    print_msg $PURPLE "管理命令："
    echo "   查看配置: git config --get-regexp alias.my"
    echo "   卸载脚本: curl -fsSL ${REPO_BASE}/uninstall.sh | bash"
    echo
    print_msg $BLUE "提示：如遇到问题，请访问："
    print_msg $BLUE "https://github.com/Yuyang-Du-NTU/Scripts"
    echo
}

# 错误恢复
rollback_installation() {
    print_msg $YELLOW "[ROLLBACK] 正在回滚安装..."
    
    # 删除新创建的 aliases
    git config --global --unset alias.mysync 2>/dev/null
    git config --global --unset alias.mypush 2>/dev/null
    
    # 恢复备份（如果有）
    if git config --global --get alias.mysync-backup &>/dev/null; then
        git config --global alias.mysync "$(git config --global --get alias.mysync-backup)"
        git config --global --unset alias.mysync-backup
        print_msg $YELLOW "[INFO] 已恢复原有的 git mysync"
    fi
    if git config --global --get alias.mypush-backup &>/dev/null; then
        git config --global alias.mypush "$(git config --global --get alias.mypush-backup)"
        git config --global --unset alias.mypush-backup
        print_msg $YELLOW "[INFO] 已恢复原有的 git mypush"
    fi
}

# 主函数
main() {
    # 显示横幅
    show_banner
    
    # 检查系统环境
    check_system
    
    # 创建临时目录
    create_temp_dir
    
    # 下载脚本
    if ! download_scripts; then
        print_msg $RED "[FATAL] 脚本下载失败，安装中止"
        exit 1
    fi
    
    # 创建 Git aliases
    if ! create_git_aliases; then
        print_msg $RED "[FATAL] 配置 Git aliases 失败"
        rollback_installation
        exit 1
    fi
    
    # 验证安装
    if ! verify_installation; then
        print_msg $RED "[FATAL] 安装验证失败"
        rollback_installation
        exit 1
    fi
    
    # 显示使用说明
    show_usage
    
    # 清理临时文件（trap 会自动处理，这里只是确保）
    rm -rf "$TEMP_DIR" 2>/dev/null
    
    print_msg $GREEN "[COMPLETE] 安装过程完成！"
}

# 错误处理
trap 'echo -e "\n${RED}[INTERRUPT] 安装被中断${NC}"; rollback_installation; exit 130' INT TERM

# 执行主函数
main "$@"
