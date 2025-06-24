#!/bin/bash

# Git 同步脚本 (mysync)
# 功能：同步所有远程分支、标签，自动创建本地跟踪分支

set -e  # 遇到错误时退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_msg() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 检查是否在 Git 仓库中
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_msg $RED "[ERROR] 当前目录不是 Git 仓库"
        exit 1
    fi
}

# 获取当前分支名
get_current_branch() {
    git branch --show-current
}

# 检查工作区是否干净
check_working_tree() {
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        print_msg $YELLOW "[WARN] 工作区有未提交的更改"
        read -p "是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_msg $RED "[CANCEL] 同步已取消"
            exit 1
        fi
    fi
}

# 获取远程分支列表
get_remote_branches() {
    git ls-remote --heads origin 2>/dev/null | sed 's|.*refs/heads/||' | sort
}

# 获取本地分支列表
get_local_branches() {
    git branch --format='%(refname:short)' | sort
}

# 创建新的本地跟踪分支
create_tracking_branches() {
    print_msg $BLUE "[INFO] 检查远程分支..."
    
    local remote_branches=($(get_remote_branches))
    local local_branches=($(get_local_branches))
    local new_branches=()
    
    # 找出远程有但本地没有的分支
    for remote_branch in "${remote_branches[@]}"; do
        if [[ ! " ${local_branches[*]} " =~ " ${remote_branch} " ]]; then
            new_branches+=("$remote_branch")
        fi
    done
    
    if [ ${#new_branches[@]} -eq 0 ]; then
        print_msg $GREEN "[OK] 没有发现新的远程分支"
    else
        print_msg $YELLOW "[NEW] 发现 ${#new_branches[@]} 个新的远程分支："
        for branch in "${new_branches[@]}"; do
            echo "   - $branch"
        done
        
        echo
        read -p "是否创建这些本地跟踪分支？(Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            for branch in "${new_branches[@]}"; do
                print_msg $CYAN "[CREATE] 创建本地分支: $branch"
                git branch --track "$branch" "origin/$branch" 2>/dev/null || {
                    print_msg $RED "[ERROR] 无法创建分支 $branch"
                }
            done
            print_msg $GREEN "[OK] 所有新分支创建完成"
        fi
    fi
}

# 同步所有分支
sync_all_branches() {
    print_msg $BLUE "[INFO] 同步所有分支..."
    
    local current_branch=$(get_current_branch)
    local local_branches=($(get_local_branches))
    local updated_branches=()
    local failed_branches=()
    
    for branch in "${local_branches[@]}"; do
        # 检查分支是否有远程跟踪
        if git config "branch.$branch.remote" > /dev/null 2>&1; then
            local remote=$(git config "branch.$branch.remote")
            local merge_ref=$(git config "branch.$branch.merge")
            local remote_branch="$remote/${merge_ref#refs/heads/}"
            
            # 检查远程分支是否存在
            if git show-ref --verify --quiet "refs/remotes/$remote_branch" 2>/dev/null; then
                local local_commit=$(git rev-parse "$branch" 2>/dev/null || echo "")
                local remote_commit=$(git rev-parse "$remote_branch" 2>/dev/null || echo "")
                
                if [[ -n "$local_commit" && -n "$remote_commit" && "$local_commit" != "$remote_commit" ]]; then
                    if [[ "$branch" == "$current_branch" ]]; then
                        print_msg $CYAN "[UPDATE] 更新当前分支: $branch"
                        if git pull --ff-only 2>/dev/null; then
                            updated_branches+=("$branch")
                        else
                            print_msg $YELLOW "[WARN] 无法快进合并 $branch，可能需要手动处理"
                            failed_branches+=("$branch")
                        fi
                    else
                        print_msg $CYAN "[UPDATE] 更新分支: $branch"
                        # 使用更安全的方式更新非当前分支
                        if git fetch origin "$branch" 2>/dev/null; then
                            # 检查是否可以快进
                            if git merge-base --is-ancestor "$branch" "$remote_branch" 2>/dev/null; then
                                git update-ref "refs/heads/$branch" "$remote_branch" 2>/dev/null && \
                                updated_branches+=("$branch") || \
                                failed_branches+=("$branch")
                            else
                                print_msg $YELLOW "[WARN] 分支 $branch 有本地提交，跳过更新"
                                failed_branches+=("$branch")
                            fi
                        fi
                    fi
                fi
            fi
        fi
    done
    
    if [ ${#updated_branches[@]} -eq 0 ] && [ ${#failed_branches[@]} -eq 0 ]; then
        print_msg $GREEN "[OK] 所有分支都是最新的"
    else
        if [ ${#updated_branches[@]} -gt 0 ]; then
            print_msg $GREEN "[OK] 已更新 ${#updated_branches[@]} 个分支："
            for branch in "${updated_branches[@]}"; do
                echo "   - $branch"
            done
        fi
        if [ ${#failed_branches[@]} -gt 0 ]; then
            print_msg $YELLOW "[WARN] 以下分支需要手动处理："
            for branch in "${failed_branches[@]}"; do
                echo "   - $branch"
            done
        fi
    fi
}

# 同步标签
sync_tags() {
    print_msg $BLUE "[INFO] 同步标签..."
    
    local before_tags=$(git tag | wc -l)
    git fetch origin --tags --prune-tags 2>/dev/null
    local after_tags=$(git tag | wc -l)
    
    local new_tags=$((after_tags - before_tags))
    if [ $new_tags -gt 0 ]; then
        print_msg $GREEN "[OK] 获取了 $new_tags 个新标签"
        print_msg $PURPLE "[LIST] 最新的标签："
        git tag --sort=-creatordate 2>/dev/null | head -5 | sed 's/^/   - /'
    else
        print_msg $GREEN "[OK] 标签已是最新"
    fi
}

# 清理已删除的远程分支引用
cleanup_remote_refs() {
    print_msg $BLUE "[INFO] 清理远程引用..."
    
    local deleted_refs=$(git remote prune origin --dry-run 2>/dev/null | grep -c "would prune" || echo "0")
    if [ "$deleted_refs" -gt 0 ]; then
        print_msg $YELLOW "[CLEAN] 发现 $deleted_refs 个已删除的远程分支引用"
        git remote prune origin
        print_msg $GREEN "[OK] 清理完成"
    else
        print_msg $GREEN "[OK] 没有需要清理的引用"
    fi
}

# 显示同步摘要
show_summary() {
    print_msg $PURPLE "[SUMMARY] 同步摘要："
    echo "   - 当前分支: $(get_current_branch)"
    echo "   - 本地分支数: $(git branch | wc -l)"
    echo "   - 远程分支数: $(git branch -r | grep -v "HEAD" | wc -l)"
    echo "   - 标签数: $(git tag | wc -l)"
    echo "   - 最新提交: $(git log -1 --pretty=format:'%h %s' 2>/dev/null || echo '无提交')"
}

# 主函数
main() {
    print_msg $CYAN "[START] Git 同步 (mysync)..."
    echo
    
    # 基础检查
    check_git_repo
    check_working_tree
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 执行同步步骤
    print_msg $BLUE "[INFO] 获取远程更新..."
    git fetch origin --prune 2>/dev/null || {
        print_msg $RED "[ERROR] 无法连接到远程仓库"
        exit 1
    }
    
    create_tracking_branches
    echo
    
    sync_tags
    echo
    
    sync_all_branches
    echo
    
    cleanup_remote_refs
    echo
    
    show_summary
    
    # 计算耗时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    print_msg $GREEN "[DONE] 同步完成！耗时: ${duration}秒"
}

# 帮助信息
show_help() {
    echo "Git 同步脚本 (mysync)"
    echo
    echo "用法: mysync [选项]"
    echo
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -q, --quiet    静默模式（减少输出）"
    echo "  -f, --force    强制同步（跳过工作区检查）"
    echo
    echo "功能:"
    echo "  * 自动创建远程分支的本地跟踪分支"
    echo "  * 同步所有本地分支到最新状态"
    echo "  * 获取所有远程标签"
    echo "  * 清理已删除的远程分支引用"
    echo "  * 显示详细的同步摘要"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -q|--quiet)
            # 静默模式的实现可以通过重定向输出
            exec > /dev/null
            shift
            ;;
        -f|--force)
            # 跳过工作区检查
            check_working_tree() { return 0; }
            shift
            ;;
        *)
            print_msg $RED "[ERROR] 未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 运行主函数
main
