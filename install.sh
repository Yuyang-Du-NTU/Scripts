#!/bin/bash

# Git Scripts 安装脚本 - 使用 Git Alias
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
NC='\033[0m'

# 打印带颜色的消息
print_msg() {
    local color=$1
    shift
    local message="$@"
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
    trap "rm -rf ${TEMP_DIR}" EXIT
}

# 下载脚本
download_scripts() {
    print_msg $BLUE "[INFO] 下载脚本..."
    
    if command -v curl &> /dev/null; then
        curl -fsSL "${SYNC_SCRIPT_URL}" -o "${TEMP_DIR}/git-mysync.sh" || {
            print_msg $RED "[ERROR] 无法下载 git-mysync.sh"
            exit 1
        }
        curl -fsSL "${PUSH_SCRIPT_URL}" -o "${TEMP_DIR}/git-mypush.sh" || {
            print_msg $RED "[ERROR] 无法下载 git-mypush.sh"
            exit 1
        }
    elif command -v wget &> /dev/null; then
        wget -q "${SYNC_SCRIPT_URL}" -O "${TEMP_DIR}/git-mysync.sh" || {
            print_msg $RED "[ERROR] 无法下载 git-mysync.sh"
            exit 1
        }
        wget -q "${PUSH_SCRIPT_URL}" -O "${TEMP_DIR}/git-mypush.sh" || {
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
    
    # 读取脚本内容
    local sync_script=$(<"${TEMP_DIR}/git-mysync.sh")
    local push_script=$(<"${TEMP_DIR}/git-mypush.sh")
    
    # 转义特殊字符
    sync_script=$(printf '%s' "$sync_script" | sed 's/\\/\\\\/g; s/"/\\"/g')
    push_script=$(printf '%s' "$push_script" | sed 's/\\/\\\\/g; s/"/\\"/g')
    
    # 创建 aliases
    git config --global alias.mysync "!bash -c \"${sync_script}\" --"
    git config --global alias.mypush "!bash -c \"${push_script}\" --"
    
    print_msg $GREEN "[OK] Git aliases 配置完成"
}

# 创建简化的 Git aliases
create_simple_aliases() {
    print_msg $BLUE "[INFO] 配置简化版 Git aliases..."
    
    # mysync 简化版本
    git config --global alias.mysync '!f() {
        echo -e "\033[0;36m[START] Git 同步所有分支...\033[0m"
        git fetch origin --prune || { echo -e "\033[0;31m[ERROR] 无法连接远程仓库\033[0m"; return 1; }
        
        echo -e "\033[0;34m[INFO] 检查远程分支...\033[0m"
        for branch in $(git branch -r | grep -v HEAD | sed "s/.*origin\///"); do
            if ! git show-ref --verify --quiet refs/heads/"$branch"; then
                echo -e "\033[0;36m[CREATE] 创建本地分支: $branch\033[0m"
                git branch --track "$branch" "origin/$branch"
            fi
        done
        
        current=$(git branch --show-current)
        echo -e "\033[0;34m[INFO] 更新本地分支...\033[0m"
        for branch in $(git branch --format="%(refname:short)"); do
            if [ "$branch" = "$current" ]; then
                echo -e "\033[0;36m[UPDATE] 更新当前分支: $branch\033[0m"
                git pull --ff-only || echo -e "\033[1;33m[WARN] 无法快进合并 $branch\033[0m"
            else
                if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
                    echo -e "\033[0;36m[UPDATE] 更新分支: $branch\033[0m"
                    git fetch origin "$branch:$branch" 2>/dev/null || echo -e "\033[1;33m[WARN] 跳过 $branch (有本地修改)\033[0m"
                fi
            fi
        done
        
        echo -e "\033[0;34m[INFO] 同步标签...\033[0m"
        git fetch --tags --prune-tags
        
        echo -e "\033[0;32m[DONE] 同步完成！\033[0m"
    }; f'
    
    # mypush 简化版本
    git config --global alias.mypush '!f() {
        echo -e "\033[0;36m[START] Git 推送 (mypush)...\033[0m"
        
        # 检查参数
        default_mode=false
        current_only=false
        for arg in "$@"; do
            case "$arg" in
                -d|--default) default_mode=true ;;
                -c|--current) current_only=true ;;
            esac
        done
        
        # 检查未提交的更改
        if ! git diff --quiet || ! git diff --cached --quiet; then
            echo -e "\033[1;33m[WARN] 检测到未提交的更改:\033[0m"
            git status -s
            
            if $default_mode; then
                echo -e "\033[0;36m[AUTO] 自动提交更改...\033[0m"
                timestamp=$(date "+%Y-%m-%d %H:%M:%S")
                username=$(git config user.name || whoami)
                git add -A
                git commit -m "[default mypush] $timestamp by $username"
                echo -e "\033[0;32m[OK] 已自动提交\033[0m"
            else
                echo -e "\033[0;31m[ABORT] 请先提交更改或使用 -d 选项\033[0m"
                return 1
            fi
        fi
        
        # 显示待推送的提交
        branch=$(git branch --show-current)
        if [ -n "$branch" ]; then
            upstream=$(git rev-parse --abbrev-ref "$branch@{upstream}" 2>/dev/null || echo "")
            if [ -n "$upstream" ]; then
                commits=$(git rev-list --count "$upstream..$branch" 2>/dev/null || echo "0")
                if [ "$commits" -gt 0 ]; then
                    echo -e "\033[0;32m[COMMITTED] 待推送的提交 ($commits 个):\033[0m"
                    git log "$upstream..$branch" --oneline | sed "s/^/   /"
                fi
            fi
        fi
        
        # 确认推送
        echo -en "\033[1;33m[CONFIRM] 是否推送？(Y/n): \033[0m"
        read -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo -e "\033[0;31m[CANCEL] 推送已取消\033[0m"
            return 0
        fi
        
        # 执行推送
        if $current_only; then
            echo -e "\033[0;34m[INFO] 推送当前分支: $branch\033[0m"
            git push origin "$branch" || echo -e "\033[0;31m[ERROR] 推送失败\033[0m"
        else
            echo -e "\033[0;34m[INFO] 推送所有分支...\033[0m"
            for b in $(git branch --format="%(refname:short)"); do
                if git show-ref --verify --quiet "refs/remotes/origin/$b"; then
                    ahead=$(git rev-list --count "origin/$b..$b" 2>/dev/null || echo 0)
                    if [ "$ahead" -gt 0 ]; then
                        echo -e "\033[0;36m[PUSH] 推送分支: $b ($ahead 个提交)\033[0m"
                        git push origin "$b"
                    fi
                else
                    echo -e "\033[0;36m[PUSH] 推送新分支: $b\033[0m"
                    git push -u origin "$b"
                fi
            done
            
            echo -e "\033[0;34m[INFO] 推送标签...\033[0m"
            git push --tags
        fi
        
        echo -e "\033[0;32m[DONE] 推送完成！\033[0m"
    }; f'
    
    print_msg $GREEN "[OK] 简化版 aliases 配置完成"
}

# 验证安装
verify_installation() {
    print_msg $BLUE "[INFO] 验证安装..."
    
    if git config --get alias.mysync &> /dev/null && \
       git config --get alias.mypush &> /dev/null; then
        print_msg $GREEN "[OK] 验证成功"
        return 0
    else
        print_msg $RED "[ERROR] 验证失败"
        return 1
    fi
}

# 显示使用说明
show_usage() {
    cat << 'EOF'

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
   git mypush -d -c        # 自动提交并只推送当前分支

卸载方法:
   git config --global --unset alias.mysync
   git config --global --unset alias.mypush

EOF
}

# 主函数
main() {
    print_msg $CYAN "=== Git Scripts 安装程序 ==="
    echo
    
    # 检查环境
    check_git
    
    # 直接安装完整版
    print_msg $BLUE "[INFO] 安装完整版 Git Scripts..."
    create_temp_dir
    download_scripts
    create_git_aliases
    
    # 验证安装
    if verify_installation; then
        show_usage
    else
        print_msg $RED "[ERROR] 安装失败，请检查错误信息"
        exit 1
    fi
}

# 执行主函数
main "$@"
