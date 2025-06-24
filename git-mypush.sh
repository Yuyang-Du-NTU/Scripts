#!/bin/bash

# Git 推送脚本 (mypush)
# 功能：智能推送已提交的更改，支持自动提交未暂存的更改

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

# 检查工作区状态并显示详细信息
check_workspace_status() {
    local has_unstaged=false
    local has_staged=false
    local has_committed=false
    
    print_msg $BLUE "[INFO] 检查工作区状态..."
    echo
    
    # 检查未暂存的更改
    if ! git diff --quiet 2>/dev/null; then
        has_unstaged=true
        print_msg $YELLOW "[UNSTAGED] 未暂存的更改："
        git diff --name-status | sed 's/^/   /'
        echo
    fi
    
    # 检查已暂存但未提交的更改
    if ! git diff --cached --quiet 2>/dev/null; then
        has_staged=true
        print_msg $YELLOW "[STAGED] 已暂存但未提交的更改："
        git diff --cached --name-status | sed 's/^/   /'
        echo
    fi
    
    # 检查已提交但未推送的更改
    local current_branch=$(get_current_branch)
    if [[ -n "$current_branch" ]]; then
        local upstream=$(git rev-parse --abbrev-ref "$current_branch@{upstream}" 2>/dev/null || echo "")
        if [[ -n "$upstream" ]]; then
            local unpushed=$(git rev-list --count "$upstream..$current_branch" 2>/dev/null || echo "0")
            if [[ "$unpushed" -gt 0 ]]; then
                has_committed=true
                print_msg $GREEN "[COMMITTED] 已提交但未推送的更改 ($unpushed 个提交)："
                git log "$upstream..$current_branch" --oneline | sed 's/^/   /'
                echo
            fi
        else
            # 没有上游分支，检查是否有提交
            local commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
            if [[ "$commit_count" -gt 0 ]]; then
                has_committed=true
                print_msg $GREEN "[COMMITTED] 新分支的提交 ($commit_count 个提交)："
                git log --oneline -5 | sed 's/^/   /'
                echo
            fi
        fi
    fi
    
    # 返回状态
    if $has_unstaged; then
        echo "unstaged"
    elif $has_staged; then
        echo "staged"
    elif $has_committed; then
        echo "committed"
    else
        echo "clean"
    fi
}

# 自动提交功能（-d 选项）
auto_commit_changes() {
    local username=$(git config user.name || whoami)
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local commit_msg="[default commit from mypush] user: $username at $timestamp"
    
    print_msg $CYAN "[AUTO] 自动提交所有更改..."
    git add -A
    git commit -m "$commit_msg" || {
        print_msg $YELLOW "[WARN] 没有需要提交的更改"
        return 1
    }
    print_msg $GREEN "[OK] 已自动提交: $commit_msg"
    return 0
}

# 处理未提交的更改
handle_uncommitted_changes() {
    local default_mode=$1
    local status=$(check_workspace_status)
    
    case "$status" in
        "unstaged"|"staged")
            if $default_mode; then
                auto_commit_changes
            else
                print_msg $YELLOW "[WARN] 检测到未提交的更改"
                print_msg $YELLOW "请先提交这些更改，或使用 -d/--default 选项自动提交"
                print_msg $RED "[ABORT] 推送已取消"
                exit 1
            fi
            ;;
        "committed")
            print_msg $GREEN "[INFO] 只有已提交的更改，准备推送"
            ;;
        "clean")
            print_msg $GREEN "[INFO] 工作区干净，没有需要推送的更改"
            ;;
    esac
}

# 推送确认
confirm_push() {
    print_msg $YELLOW "[CONFIRM] 是否推送已提交的更改？(Y/n): "
    read -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_msg $RED "[CANCEL] 推送已取消"
        exit 0
    fi
}

# 获取需要推送的分支
get_branches_to_push() {
    local branches=()
    local current_branch=$(get_current_branch)
    
    # 获取所有有上游分支且有未推送提交的分支
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            local upstream=$(git rev-parse --abbrev-ref "$branch@{upstream}" 2>/dev/null || echo "")
            if [[ -n "$upstream" ]]; then
                local local_ref=$(git rev-parse "$branch" 2>/dev/null)
                local remote_ref=$(git rev-parse "$upstream" 2>/dev/null)
                if [[ "$local_ref" != "$remote_ref" ]]; then
                    branches+=("$branch")
                fi
            else
                # 没有上游分支的本地分支
                branches+=("$branch:new")
            fi
        fi
    done < <(git for-each-ref --format='%(refname:short)' refs/heads/)
    
    echo "${branches[@]}"
}

# 推送单个分支
push_branch() {
    local branch=$1
    local is_new=false
    
    # 检查是否是新分支
    if [[ "$branch" == *":new" ]]; then
        branch=${branch%:new}
        is_new=true
    fi
    
    if $is_new; then
        print_msg $CYAN "[PUSH] 推送新分支: $branch"
        if git push -u origin "$branch" 2>&1; then
            print_msg $GREEN "[OK] 成功推送新分支: $branch"
            return 0
        else
            print_msg $RED "[ERROR] 推送失败: $branch"
            return 1
        fi
    else
        # 获取未推送的提交数
        local unpushed=$(git rev-list --count "$branch@{upstream}..$branch" 2>/dev/null || echo "0")
        if [[ "$unpushed" -gt 0 ]]; then
            print_msg $CYAN "[PUSH] 推送分支: $branch (${unpushed} 个新提交)"
            if git push origin "$branch" 2>&1; then
                print_msg $GREEN "[OK] 成功推送: $branch"
                return 0
            else
                print_msg $RED "[ERROR] 推送失败: $branch"
                return 1
            fi
        fi
    fi
}

# 推送所有分支
push_all_branches() {
    print_msg $BLUE "[INFO] 检查需要推送的分支..."
    
    local branches=($(get_branches_to_push))
    local success_count=0
    local failed_branches=()
    
    if [ ${#branches[@]} -eq 0 ]; then
        print_msg $GREEN "[OK] 没有需要推送的分支"
        return
    fi
    
    print_msg $YELLOW "[INFO] 发现 ${#branches[@]} 个需要推送的分支"
    
    for branch in "${branches[@]}"; do
        if push_branch "$branch"; then
            ((success_count++))
        else
            failed_branches+=("${branch%:new}")
        fi
    done
    
    echo
    if [ ${#failed_branches[@]} -gt 0 ]; then
        print_msg $RED "[WARN] 以下分支推送失败："
        for branch in "${failed_branches[@]}"; do
            echo "   - $branch"
        done
    fi
    
    print_msg $GREEN "[SUMMARY] 成功推送 $success_count/${#branches[@]} 个分支"
}

# 获取需要推送的标签
get_tags_to_push() {
    local tags=()
    
    # 获取所有本地标签
    while IFS= read -r tag; do
        if [[ -n "$tag" ]]; then
            # 检查远程是否有这个标签
            if ! git ls-remote --tags origin | grep -q "refs/tags/$tag$"; then
                tags+=("$tag")
            fi
        fi
    done < <(git tag)
    
    echo "${tags[@]}"
}

# 推送所有标签
push_all_tags() {
    print_msg $BLUE "[INFO] 检查需要推送的标签..."
    
    local tags=($(get_tags_to_push))
    
    if [ ${#tags[@]} -eq 0 ]; then
        print_msg $GREEN "[OK] 没有需要推送的标签"
        return
    fi
    
    print_msg $YELLOW "[INFO] 发现 ${#tags[@]} 个需要推送的标签："
    for tag in "${tags[@]}"; do
        echo "   - $tag"
    done
    
    echo
    read -p "是否推送所有标签？(Y/n): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        print_msg $CYAN "[PUSH] 推送所有标签..."
        if git push origin --tags 2>&1; then
            print_msg $GREEN "[OK] 成功推送所有标签"
        else
            print_msg $RED "[ERROR] 推送标签失败"
        fi
    fi
}

# 显示待推送的提交详情
show_pending_commits() {
    print_msg $PURPLE "[COMMITS] 待推送的提交详情："
    
    local has_commits=false
    local total_commits=0
    
    # 遍历所有分支
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            local upstream=$(git rev-parse --abbrev-ref "$branch@{upstream}" 2>/dev/null || echo "")
            if [[ -n "$upstream" ]]; then
                local commits=$(git rev-list --count "$upstream..$branch" 2>/dev/null || echo "0")
                if [[ "$commits" -gt 0 ]]; then
                    has_commits=true
                    total_commits=$((total_commits + commits))
                    echo
                    print_msg $CYAN "  分支: $branch ($commits 个提交)"
                    git log "$upstream..$branch" --oneline --format="    %h %s" | head -10
                    if [[ "$commits" -gt 10 ]]; then
                        echo "    ... 还有 $((commits - 10)) 个提交"
                    fi
                fi
            else
                # 新分支，没有上游
                local commits=$(git rev-list --count HEAD 2>/dev/null || echo "0")
                if [[ "$commits" -gt 0 ]]; then
                    has_commits=true
                    total_commits=$((total_commits + commits))
                    echo
                    print_msg $CYAN "  新分支: $branch ($commits 个提交)"
                    git log --oneline --format="    %h %s" -10
                    if [[ "$commits" -gt 10 ]]; then
                        echo "    ... 还有 $((commits - 10)) 个提交"
                    fi
                fi
            fi
        fi
    done < <(git for-each-ref --format='%(refname:short)' refs/heads/)
    
    if ! $has_commits; then
        echo "    无待推送的提交"
    else
        echo
        print_msg $GREEN "  总计: $total_commits 个提交待推送"
    fi
}

# 强制推送模式
force_push_current() {
    local current_branch=$(get_current_branch)
    print_msg $RED "[WARN] 强制推送当前分支: $current_branch"
    read -p "确定要强制推送吗？这可能会覆盖远程更改！(yes/N): " -r
    if [[ $REPLY == "yes" ]]; then
        git push origin "$current_branch" --force-with-lease
        print_msg $GREEN "[OK] 强制推送完成"
    else
        print_msg $YELLOW "[CANCEL] 已取消强制推送"
    fi
}

# 主函数
main() {
    local force_mode=false
    local tags_only=false
    local current_only=false
    local default_mode=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force_mode=true
                shift
                ;;
            -t|--tags)
                tags_only=true
                shift
                ;;
            -c|--current)
                current_only=true
                shift
                ;;
            -d|--default)
                default_mode=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_msg $RED "[ERROR] 未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    print_msg $CYAN "[START] Git 推送 (mypush)..."
    echo
    
    # 基础检查
    check_git_repo
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 强制推送模式
    if $force_mode; then
        force_push_current
        exit 0
    fi
    
    # 只推送标签
    if $tags_only; then
        push_all_tags
        exit 0
    fi
    
    # 如果指定了 -d 选项，先自动提交
    if $default_mode; then
        if ! git diff --quiet || ! git diff --cached --quiet; then
            auto_commit_changes
            echo
        fi
    else
        # 检查是否有未提交的更改
        if ! git diff --quiet || ! git diff --cached --quiet; then
            print_msg $YELLOW "[WARN] 检测到未提交的更改："
            git status -s
            print_msg $RED "[ABORT] 请先提交更改或使用 -d 选项自动提交"
            exit 1
        fi
    fi
    
    # 显示推送前摘要
    print_msg $PURPLE "[SUMMARY] 推送前检查："
    local current_branch=$(get_current_branch)
    echo "   - 当前分支: $current_branch"
    local branches_to_push=($(get_branches_to_push))
    echo "   - 待推送分支: ${#branches_to_push[@]} 个"
    local tags_to_push=($(get_tags_to_push))
    echo "   - 待推送标签: ${#tags_to_push[@]} 个"
    local remote_url=$(git config --get remote.origin.url || echo "未设置")
    echo "   - 远程仓库: $remote_url"
    echo
    
    # 显示待推送的提交详情
    show_pending_commits
    echo
    
    # 确认推送
    confirm_push
    
    # 只推送当前分支
    if $current_only; then
        push_branch "$current_branch"
    else
        # 推送所有分支
        push_all_branches
        echo
        
        # 推送所有标签
        push_all_tags
    fi
    
    # 计算耗时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    print_msg $GREEN "[DONE] 推送完成！耗时: ${duration}秒"
}

# 帮助信息
show_help() {
    echo "Git 推送脚本 (mypush)"
    echo
    echo "用法: mypush [选项]"
    echo
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -d, --default  自动提交未暂存的更改（使用默认提交信息）"
    echo "  -f, --force    强制推送当前分支（使用 --force-with-lease）"
    echo "  -t, --tags     仅推送标签"
    echo "  -c, --current  仅推送当前分支"
    echo
    echo "功能:"
    echo "  * 显示工作区的详细状态（未暂存、已暂存、已提交）"
    echo "  * 只推送已提交的更改，未提交的更改会被提示"
    echo "  * 使用 -d 选项可自动提交所有更改"
    echo "  * 推送前需要确认"
    echo
    echo "示例:"
    echo "  mypush          # 检查状态并推送已提交的更改"
    echo "  mypush -d       # 自动提交所有更改并推送"
    echo "  mypush -c       # 只推送当前分支"
    echo "  mypush -t       # 只推送标签"
}

# 运行主函数
main "$@"
