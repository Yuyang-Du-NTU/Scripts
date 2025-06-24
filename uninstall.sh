#!/bin/bash

# Git Scripts 卸载脚本
# 完全移除 git mysync 和 git mypush 命令

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印带颜色的消息
print_msg() {
    local color=$1
    shift
    local message="$@"
    echo -e "${color}${message}${NC}"
}

# 显示当前安装信息
show_installation_info() {
    print_msg $BLUE "[INFO] 检查当前安装状态..."
    echo
    
    # 检查 Git aliases
    local has_mysync=$(git config --get alias.mysync 2>/dev/null)
    local has_mypush=$(git config --get alias.mypush 2>/dev/null)
    
    if [[ -n "$has_mysync" ]] || [[ -n "$has_mypush" ]]; then
        print_msg $YELLOW "发现以下 Git aliases:"
        if [[ -n "$has_mysync" ]]; then
            echo "  - git mysync"
        fi
        if [[ -n "$has_mypush" ]]; then
            echo "  - git mypush"
        fi
        echo
        
        # 显示 Git alias 存储位置
        print_msg $BLUE "[INFO] Git aliases 存储在:"
        echo "  - 全局配置: ~/.gitconfig"
        echo "  - 或系统配置: $(git config --list --show-origin | grep -E "alias\.(mysync|mypush)" | cut -d: -f1 | sort -u)"
        echo
        
        return 0
    else
        print_msg $GREEN "[OK] 未发现 Git Scripts 安装"
        return 1
    fi
}

# 移除 Git aliases
remove_git_aliases() {
    print_msg $BLUE "[INFO] 移除 Git aliases..."
    
    # 移除 mysync
    if git config --get alias.mysync &> /dev/null; then
        git config --global --unset alias.mysync
        print_msg $GREEN "[OK] 已移除 git mysync"
    fi
    
    # 移除 mypush
    if git config --get alias.mypush &> /dev/null; then
        git config --global --unset alias.mypush
        print_msg $GREEN "[OK] 已移除 git mypush"
    fi
}

# 验证卸载
verify_uninstall() {
    print_msg $BLUE "[INFO] 验证卸载..."
    
    local has_mysync=$(git config --get alias.mysync 2>/dev/null)
    local has_mypush=$(git config --get alias.mypush 2>/dev/null)
    
    if [[ -z "$has_mysync" ]] && [[ -z "$has_mypush" ]]; then
        print_msg $GREEN "[OK] 卸载成功！"
        return 0
    else
        print_msg $RED "[ERROR] 卸载失败，仍然存在以下 aliases:"
        [[ -n "$has_mysync" ]] && echo "  - git mysync"
        [[ -n "$has_mypush" ]] && echo "  - git mypush"
        return 1
    fi
}

# 主函数
main() {
    print_msg $CYAN "=== Git Scripts 卸载程序 ==="
    echo
    
    # 显示当前安装信息
    if ! show_installation_info; then
        exit 0
    fi
    
    # 确认卸载
    print_msg $YELLOW "[CONFIRM] 确定要卸载 Git Scripts 吗？(y/N): "
    read -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_msg $YELLOW "[CANCEL] 卸载已取消"
        exit 0
    fi
    
    echo
    # 执行卸载
    remove_git_aliases
    
    echo
    # 验证卸载
    verify_uninstall
    
    echo
    print_msg $BLUE "[INFO] 感谢使用 Git Scripts！"
}

# 执行主函数
main "$@"
