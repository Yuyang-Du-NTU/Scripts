#!/bin/bash

# Git Scripts 安装脚本 - v3.1 (智能 PATH 配置)
# 自动配置 git mysync (shell) 和 git mypush (python) 命令，并智能处理 PATH 环境变量。

# 配置
REPO_BASE="https://raw.githubusercontent.com/Yuyang-Du-NTU/Scripts/debug"
SYNC_SCRIPT_URL="${REPO_BASE}/git-mysync.sh"
PUSH_SCRIPT_URL="${REPO_BASE}/git_mypush.py"

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
    print_msg $CYAN "║     Git Scripts 安装程序 v3.1 (智能 PATH)      ║"
    print_msg $CYAN "║                                              ║"
    print_msg $CYAN "║  - git mysync: (Shell) 智能同步分支和标签    ║"
    print_msg $CYAN "║  - git mypush: (Python) 智能推送并处理大文件 ║"
    print_msg $CYAN "╚══════════════════════════════════════════════╝"
    echo
}

# 检查系统环境
check_system() {
    print_msg $BLUE "[SYSTEM] 检查系统环境..."
    
    # 检查 Python 3
    if ! command -v python3 &> /dev/null; then
        print_msg $RED "[ERROR] Python 3 未安装！mypush 命令需要 Python 3。"
        exit 1
    fi
    echo "  - Python 3: $(command -v python3)"

    # 检查 Git
    if ! command -v git &> /dev/null; then
        print_msg $RED "[ERROR] Git 未安装！请先安装 Git。"
        exit 1
    fi
    echo "  - Git: $(command -v git)"
    
    # 检查网络工具
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        print_msg $RED "[ERROR] 需要 curl 或 wget 来下载脚本！"
        exit 1
    fi
    echo "  - 下载工具: $(command -v curl || command -v wget)"
    echo
}

# 复制本地脚本文件
download_scripts() {
    local temp_dir=$1
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    print_msg $BLUE "[COPY] 复制本地脚本文件..."
    
    # 复制 mysync 脚本 (Shell)
    echo -n "  - 复制 git-mysync.sh... "
    if cp "${script_dir}/git-mysync.sh" "${temp_dir}/git-mysync"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"; return 1
    fi
    
    # 复制 mypush 脚本 (Python)
    echo -n "  - 复制 git_mypush.py... "
    if cp "${script_dir}/git_mypush.py" "${temp_dir}/git-mypush"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"; return 1
    fi
    
    print_msg $GREEN "[OK] 脚本复制完成"
    echo
    return 0
}

# 安装脚本文件
install_scripts() {
    local temp_dir=$1
    local install_dir=$2
    print_msg $BLUE "[INSTALL] 安装脚本到: $install_dir"
    
    mkdir -p "$install_dir"
    
    # 安装 git-mysync (shell)
    echo -n "  - 安装 git-mysync... "
    if mv "${temp_dir}/git-mysync" "$install_dir/git-mysync" && chmod +x "$install_dir/git-mysync"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"; return 1
    fi
    
    # 安装 git-mypush (python)
    echo -n "  - 安装 git-mypush... "
    if mv "${temp_dir}/git-mypush" "$install_dir/git-mypush" && chmod +x "$install_dir/git-mypush"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"; return 1
    fi
    
    print_msg $GREEN "[OK] 脚本安装完成"
    echo
    return 0
}

# 配置 Git aliases
create_git_aliases() {
    local install_dir=$1
    print_msg $BLUE "[CONFIG] 配置 Git aliases..."
    
    # 配置 git mysync (执行 shell 脚本)
    echo -n "  - 配置 git mysync... "
    if git config --global alias.mysync "!\"$install_dir/git-mysync\""; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"; return 1
    fi
    
    # 配置 git mypush (执行 python 脚本)
    echo -n "  - 配置 git mypush... "
    if git config --global alias.mypush "!\"$install_dir/git-mypush\""; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"; return 1
    fi
    
    print_msg $GREEN "[OK] Git aliases 配置完成"
    echo
    return 0
}

# 智能配置 PATH
configure_path() {
    local install_dir=$1
    
    # 检查 install_dir 是否已在 PATH 中
    case ":$PATH:" in
        *":$install_dir:"*) 
            print_msg $GREEN "[INFO] 安装目录已存在于 PATH 中，无需配置。"
            return
            ;;
    esac

    # 检测 Shell 配置文件
    local shell_profile=""
    if [ -n "$BASH_VERSION" ]; then
        shell_profile="$HOME/.bashrc"
    elif [ -n "$ZSH_VERSION" ]; then
        shell_profile="$HOME/.zshrc"
    elif [ -f "$HOME/.profile" ]; then
        shell_profile="$HOME/.profile"
    else
        print_msg $YELLOW "[WARN] 无法自动检测到 shell 配置文件 (.bashrc, .zshrc, .profile)。"
        print_msg $YELLOW "       请手动将以下行添加到您的 shell 配置文件中："
        print_msg $CYAN   "       export PATH=\"$install_dir:\$PATH\""
        return
    fi

    print_msg $YELLOW "[ACTION] 安装目录需要被添加到您的 PATH 环境变量中。"
    read -p "是否允许我自动将 PATH 配置添加到您的 '$shell_profile' 文件中？(Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_msg $YELLOW "[INFO] 已跳过自动配置。请手动将以下行添加到您的 shell 配置文件中："
        print_msg $CYAN   "      export PATH=\"$install_dir:\$PATH\""
        return
    fi

    # 将 PATH 添加到配置文件
    echo -e "\n# Added by Git Scripts installer\nexport PATH=\"$install_dir:\$PATH\"" >> "$shell_profile"
    print_msg $GREEN "[OK] 已成功将 PATH 配置添加到 '$shell_profile'。"
    print_msg $YELLOW "[IMPORTANT] 请重启您的终端，或运行 'source $shell_profile' 来使更改生效。"
}

# 主函数
main() {
    show_banner
    check_system
    
    local temp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t 'git-scripts')
    trap "rm -rf \"$temp_dir\" 2>/dev/null" EXIT INT TERM
    
    local install_dir="$HOME/.local/bin"

    if ! download_scripts "$temp_dir"; then exit 1; fi
    if ! install_scripts "$temp_dir" "$install_dir"; then exit 1; fi
    if ! create_git_aliases "$install_dir"; then exit 1; fi
    
    configure_path "$install_dir"
    
    echo
    print_msg $GREEN "═══════════════════════════════════════════════"
    print_msg $GREEN "          安装成功！🎉"
    print_msg $GREEN "═══════════════════════════════════════════════"
    echo
    print_msg $PURPLE "请记得根据提示重启终端或刷新 Shell 配置！"
}

# 执行主函数
main "$@"