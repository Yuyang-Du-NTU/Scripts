# 显示使用说明
show_usage() {
    print_msg $PURPLE "
====================================
Git Scripts 安装成功！
====================================

可用命令:

1. git mysync      - 同步所有远程分支和标签
   选项:
   -f, --force     跳过工作区检查
   -q, --quiet     静默模式
   -h, --help      显示帮助

2. git mypush      - 智能推送已提交的更改
   选项:
   -d, --default   自动提交并推送（默认提交信息）
   -c, --current   只推送当前分支
   -t, --tags      只推送标签
   -f, --force     强制推送当前分支
   -h, --help      显示帮助

使用示例:
   git mysync              # 同步所有分支
   git mypush              # 推送已提交的更改
   git mypush -d           # 自动提交所有更改并推送
   git mypush -c           # 只推送当前分支

卸载方法:
   git config --global --unset alias.mysync
   git config --global --unset alias.mypush
"
}#!/bin/bash

# Git Scripts 安装脚本 - 使用 Git Alias
# 自动配置 git mysync 和 git mypush 命令

# 配置
REPO_BASE="https://raw.githubusercontent.com/Yuyang-Du-NTU/Scripts/main"
SYNC_SCRIPT_URL="$REPO_BASE/git-mysync.sh"
PUSH_SCRIPT_URL="$REPO_BASE/git-mypush.sh"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印带颜色的消息
print_msg() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 检查 Git 是否安装
check_git() {
    if ! command -v git &> /dev/null; then
        print_msg $RED "[ERROR] Git 未安装"
        exit 1
    fi
}

# 创建临时目录
create_temp_dir() {
    TEMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'git-scripts')
    trap "rm -rf $TEMP_DIR" EXIT
}

# 下载脚本
download_scripts() {
    print_msg $BLUE "[INFO] 下载脚本..."
    
    # 下载 sync 脚本
    if command -v curl &> /dev/null; then
        curl -fsSL "$SYNC_SCRIPT_URL" -o "$TEMP_DIR/git-mysync.sh" || {
            print_msg $RED "[ERROR] 无法下载 git-mysync.sh"
            exit 1
        }
        curl -fsSL "$PUSH_SCRIPT_URL" -o "$TEMP_DIR/git-mypush.sh" || {
            print_msg $RED "[ERROR] 无法下载 git-mypush.sh"
            exit 1
        }
    elif command -v wget &> /dev/null; then
        wget -q "$SYNC_SCRIPT_URL" -O "$TEMP_DIR/git-mysync.sh" || {
            print_msg $RED "[ERROR] 无法下载 git-mysync.sh"
            exit 1
        }
        wget -q "$PUSH_SCRIPT_URL" -O "$TEMP_DIR/git-mypush.sh" || {
            print_msg $RED "[ERROR] 无法下载 git-mypush.sh"
            exit 1
        }
    else
        print_msg $RED "[ERROR] 需要 curl 或 wget"
        exit 1
    fi
    
    print_msg $GREEN "[OK] 脚本下载完成"
}

# 将脚本内容转换为 Git alias
create_git_aliases() {
    print_msg $BLUE "[INFO] 配置 Git aliases..."
    
    # 读取脚本内容并转义
    local sync_script=$(cat "$TEMP_DIR/git-mysync.sh" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed "s/'/\\\\'/g")
    local push_script=$(cat "$TEMP_DIR/git-mypush.sh" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed "s/'/\\\\'/g")
    
    # 创建 mysync alias
    git config --global alias.mysync '!'"bash -c '$sync_script' --"
    
    # 创建 mypush alias
    git config --global alias.mypush '!'"bash -c '$push_script' --"
    
    print_msg $GREEN "[OK] Git aliases 配置完成"
}

# 创建简化的 Git aliases（另一种方案）
create_simple_aliases() {
    print_msg $BLUE "[INFO] 配置简化版 Git aliases..."
    
    # mysync 的简化版本
    git config --global alias.mysync '!f() {
        echo -e "\033[0;36m[START] Git 同步所有分支...\033[0m";
        git fetch origin --prune;
        echo -e "\033[0;34m[INFO] 更新所有本地分支...\033[0m";
        for branch in $(git branch -r | grep -v HEAD | sed "s/origin\///"); do
            if ! git show-ref --verify --quiet refs/heads/$branch; then
                echo -e "\033[0;36m[CREATE] 创建本地分支: $branch\033[0m";
                git branch --track "$branch" "origin/$branch";
            fi;
        done;
        current=$(git branch --show-current);
        for branch in $(git branch --format="%(refname:short)"); do
            if [ "$branch" = "$current" ]; then
                echo -e "\033[0;36m[UPDATE] 更新当前分支: $branch\033[0m";
                git pull --ff-only;
            else
                if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
                    echo -e "\033[0;36m[UPDATE] 更新分支: $branch\033[0m";
                    git fetch origin "$branch:$branch";
                fi;
            fi;
        done;
        git fetch --tags --prune-tags;
        echo -e "\033[0;32m[DONE] 同步完成！\033[0m";
    }; f'
    
    # mypush 的简化版本
    git config --global alias.mypush '!f() {
        echo -e "\033[0;36m[START] Git 推送 (mypush)...\033[0m";
        
        # 检查参数
        default_mode=false;
        for arg in "$@"; do
            if [[ "$arg" == "-d" || "$arg" == "--default" ]]; then
                default_mode=true;
            fi;
        done;
        
        # 检查工作区状态
        has_changes=false;
        if ! git diff --quiet || ! git diff --cached --quiet; then
            has_changes=true;
            echo -e "\033[1;33m[WARN] 检测到未提交的更改:\033[0m";
            git status -s;
            
            if $default_mode; then
                echo -e "\033[0;36m[AUTO] 自动提交更改...\033[0m";
                time=$(date "+%Y-%m-%d %H:%M:%S");
                user=$(git config user.name || whoami);
                git add -A;
                git commit -m "[default mypush] $time by $user";
                echo -e "\033[0;32m[OK] 已自动提交\033[0m";
            else
                echo -e "\033[0;31m[ABORT] 请先提交更改或使用 -d 选项\033[0m";
                return 1;
            fi;
        fi;
        
        # 显示已提交的更改
        branch=$(git branch --show-current);
        if [ -n "$branch" ]; then
            upstream=$(git rev-parse --abbrev-ref "$branch@{upstream}" 2>/dev/null || echo "");
            if [ -n "$upstream" ]; then
                commits=$(git rev-list --count "$upstream..$branch" 2>/dev/null || echo "0");
                if [ "$commits" -gt 0 ]; then
                    echo -e "\033[0;32m[COMMITTED] 已提交但未推送的更改 ($commits 个提交):\033[0m";
                    git log "$upstream..$branch" --oneline | sed "s/^/   /";
                fi;
            fi;
        fi;
        
        # 确认推送
        echo -e "\033[1;33m[CONFIRM] 是否推送已提交的更改？(Y/n): \033[0m";
        read -n 1 -r;
        echo;
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo -e "\033[0;31m[CANCEL] 推送已取消\033[0m";
            return 0;
        fi;
        
        # 推送
        echo -e "\033[0;34m[INFO] 推送所有分支...\033[0m";
        for branch in $(git branch --format="%(refname:short)"); do
            if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
                ahead=$(git rev-list --count "origin/$branch..$branch" 2>/dev/null || echo 0);
                if [ "$ahead" -gt 0 ]; then
                    echo -e "\033[0;36m[PUSH] 推送分支: $branch ($ahead 个提交)\033[0m";
                    git push origin "$branch";
                fi;
            else
                echo -e "\033[0;36m[PUSH] 推送新分支: $branch\033[0m";
                git push -u origin "$branch";
            fi;
        done;
        echo -e "\033[0;34m[INFO] 推送标签...\033[0m";
        git push --tags;
        echo -e "\033[0;32m[DONE] 推送完成！\033[0m";
    }; f'
    
    print_msg $GREEN "[OK] 简化版 aliases 配置完成"
}

# 验证安装
verify_installation() {
    print_msg $BLUE "[INFO] 验证安装..."
    
    # 检查 aliases 是否存在
    if git config --get alias.mysync &> /dev/null && git config --get alias.mypush &> /dev/null; then
        print_msg $GREEN "[OK] 验证成功"
        return 0
    else
        print_msg $RED "[ERROR] 验证失败"
        return 1
    fi
}

# 显示使用说明
show_usage() {
    print_msg $PURPLE "
====================================
Git Scripts 安装成功！
====================================

可用命令:

1. git sync-all    - 同步所有远程分支和标签
   选项:
   -f, --force     跳过工作区检查
   -q, --quiet     静默模式
   -h, --help      显示帮助

2. git push-all    - 推送所有本地更改
   选项:
   -c, --current   只推送当前分支
   -t, --tags      只推送标签
   -f, --force     强制推送当前分支
   -h, --help      显示帮助

使用示例:
   git sync-all              # 同步所有分支
   git push-all              # 推送所有更改
   git push-all -c           # 只推送当前分支

卸载方法:
   git config --global --unset alias.sync-all
   git config --global --unset alias.push-all
"
}

# 主函数
main() {
    print_msg $CYAN "=== Git Scripts 安装程序 (Git Alias 版本) ==="
    echo
    
    # 检查环境
    check_git
    
    # 询问安装方式
    print_msg $YELLOW "[CHOICE] 请选择安装方式:"
    echo "1. 完整版 (功能齐全，包含所有选项)"
    echo "2. 简化版 (基本功能，体积更小)"
    read -p "请选择 (1/2, 默认为 2): " -n 1 -r choice
    echo
    
    if [[ "$choice" == "1" ]]; then
        # 完整版安装
        create_temp_dir
        download_scripts
        create_git_aliases
    else
        # 简化版安装
        create_simple_aliases
    fi
    
    # 验证安装
    if verify_installation; then
        show_usage
    else
        print_msg $RED "[ERROR] 安装失败，请检查错误信息"
        exit 1
    fi
}

# 运行主函数
main
