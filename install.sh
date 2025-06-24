#!/bin/bash

# Git Sync 安装脚本

# 配置
REPO_URL="https://raw.githubusercontent.com/yourusername/my-scripts/main/git-sync.sh"
SCRIPT_NAME="git-sync"

# 检测操作系统
detect_os() {
    case "$OSTYPE" in
        linux*)   echo "linux" ;;
        darwin*)  echo "macos" ;;
        msys*)    echo "windows" ;;
        cygwin*)  echo "windows" ;;
        *)        echo "unknown" ;;
    esac
}

# 选择安装目录
select_install_dir() {
    local os=$(detect_os)
    
    # 检查是否有 sudo 权限（非 Windows）
    if [[ "$os" != "windows" ]] && command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
        echo "/usr/local/bin"
    else
        # 使用用户目录
        local user_bin="$HOME/bin"
        mkdir -p "$user_bin"
        
        # 检查 PATH
        if [[ ":$PATH:" != *":$user_bin:"* ]]; then
            echo "[WARN] $user_bin 不在 PATH 中"
            echo "请将以下行添加到你的 shell 配置文件（~/.bashrc, ~/.zshrc 等）："
            echo "export PATH=\"\$HOME/bin:\$PATH\""
            echo
        fi
        
        echo "$user_bin"
    fi
}

# 下载脚本
download_script() {
    local install_dir="$1"
    local script_path="$install_dir/$SCRIPT_NAME"
    
    echo "[INFO] 下载脚本到: $script_path"
    
    # 使用 curl 或 wget
    if command -v curl &> /dev/null; then
        curl -fsSL "$REPO_URL" -o "$script_path"
    elif command -v wget &> /dev/null; then
        wget -q "$REPO_URL" -O "$script_path"
    else
        echo "[ERROR] 需要 curl 或 wget"
        exit 1
    fi
    
    # 添加执行权限
    chmod +x "$script_path"
    
    echo "[OK] 安装完成！"
    echo "[INFO] 使用方法: 在任意 Git 仓库中运行 '$SCRIPT_NAME'"
}

# 主函数
main() {
    echo "=== Git Sync 安装脚本 ==="
    echo
    
    # 确定安装目录
    install_dir=$(select_install_dir)
    
    # 确认安装
    echo "[INFO] 将安装到: $install_dir"
    read -p "继续安装？(Y/n): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        download_script "$install_dir"
    else
        echo "[CANCEL] 安装已取消"
        exit 0
    fi
}

# 运行
main
