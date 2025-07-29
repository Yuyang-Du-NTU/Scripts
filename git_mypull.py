#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Git 同步脚本 (mypull) 的 Python 重构版本。
功能：同步所有远程分支、标签，自动创建本地跟踪分支，支持 LFS 文件检查和清理。
"""

import subprocess
import sys
import argparse
import os
import tempfile
from typing import List, Optional, Tuple

# region 颜色定义
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    PURPLE = '\033[0;35m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color

def print_msg(color, message):
    """打印带颜色的消息"""
    print(f"{color}{message}{Colors.NC}")
# endregion

def run_command(command, capture_output=True, check=False):
    """执行一个 shell 命令"""
    text = True if capture_output else None
    return subprocess.run(command, capture_output=capture_output, text=text, check=check, shell=True)

def check_git_repo():
    """检查当前目录是否为 Git 仓库"""
    result = run_command("git rev-parse --git-dir", capture_output=True)
    if result.returncode != 0:
        print_msg(Colors.RED, "[错误] 当前目录不是 Git 仓库")
        sys.exit(1)

def get_current_branch() -> str:
    """获取当前分支名"""
    result = run_command("git branch --show-current", capture_output=True)
    return result.stdout.strip()

def check_working_tree(force=False) -> bool:
    """检查工作区是否干净"""
    if force:
        return True
        
    result = run_command("git diff-index --quiet HEAD --", capture_output=True)
    if result.returncode != 0:
        print_msg(Colors.YELLOW, "[WARN] 工作区有未提交的更改")
        try:
            choice = input("是否继续？(y/N): ")
            if choice.lower().strip() != 'y':
                print_msg(Colors.RED, "[CANCEL] 同步已取消")
                return False
        except (EOFError, KeyboardInterrupt):
            print_msg(Colors.RED, "\n[CANCEL] 同步已取消")
            return False
    return True

def check_lfs_files_status():
    """检查 LFS 跟踪的文件状态，并清理已不存在的文件。在 LFS 未使用时安全跳过。"""
    print_msg(Colors.BLUE, "[INFO] 检查 LFS 文件状态...")
    
    # 首先，检查 git-lfs 是否已安装并可用
    lfs_check_result = run_command("git lfs --version", capture_output=True)
    if lfs_check_result.returncode != 0:
        print_msg(Colors.YELLOW, "[WARN] Git LFS 未安装，跳过 LFS 文件检查。")
        return

    # 尝试列出LFS跟踪的文件。如果命令失败或没有输出，说明没有LFS文件或LFS未被使用。
    lfs_files_result = run_command("git lfs ls-files -n", capture_output=True)
    if lfs_files_result.returncode != 0 or not lfs_files_result.stdout.strip():
        print_msg(Colors.GREEN, "[OK] LFS 状态正常 (无文件被跟踪或LFS未使用)。")
        return

    tracked_files = lfs_files_result.stdout.strip().split('\n')
    
    git_root_result = run_command("git rev-parse --show-toplevel", capture_output=True)
    if git_root_result.returncode != 0:
        print_msg(Colors.RED, "[ERROR] 无法确定 git 仓库根目录，跳过 LFS 文件检查。")
        return
    git_root = git_root_result.stdout.strip()

    gitattributes_modified = False
    for file_path in tracked_files:
        if not file_path:
            continue
        
        # ls-files 路径是相对于仓库根目录的
        absolute_file_path = os.path.join(git_root, file_path)

        if not os.path.exists(absolute_file_path):
            print_msg(Colors.YELLOW, f"[LFS-CLEAN] 检测到已删除的 LFS 文件: {file_path}")
            print_msg(Colors.CYAN, f"           正在从 .gitattributes 取消跟踪...")
            run_command(f"git lfs untrack '{file_path}'")
            gitattributes_modified = True

    if gitattributes_modified:
        print_msg(Colors.CYAN, "[LFS-CLEAN] 正在暂存 .gitattributes 的更改...")
        run_command("git add .gitattributes")
        print_msg(Colors.GREEN, "[OK] LFS 清理完成。 .gitattributes 已更新并暂存。")
    else:
        print_msg(Colors.GREEN, "[OK] LFS 文件状态正常。")

def get_remote_branches() -> List[str]:
    """获取远程分支列表"""
    result = run_command("git ls-remote --heads origin", capture_output=True)
    if result.returncode != 0:
        return []
    
    branches = []
    for line in result.stdout.strip().split('\n'):
        if line and 'refs/heads/' in line:
            branch = line.split('refs/heads/')[1]
            branches.append(branch)
    return sorted(branches)

def get_local_branches() -> List[str]:
    """获取本地分支列表"""
    result = run_command("git branch --format='%(refname:short)'", capture_output=True)
    if result.returncode != 0:
        return []
    return sorted([b.strip() for b in result.stdout.strip().split('\n') if b.strip()])

def create_tracking_branches():
    """创建新的本地跟踪分支"""
    print_msg(Colors.BLUE, "[INFO] 检查远程分支...")
    
    remote_branches = get_remote_branches()
    local_branches = get_local_branches()
    
    new_branches = [b for b in remote_branches if b not in local_branches]
    
    if not new_branches:
        print_msg(Colors.GREEN, "[OK] 没有发现新的远程分支")
        return
    
    print_msg(Colors.YELLOW, f"[NEW] 发现 {len(new_branches)} 个新的远程分支：")
    for branch in new_branches:
        print(f"   - {branch}")
    
    print()
    try:
        choice = input("是否创建这些本地跟踪分支？(Y/n): ")
        if choice.lower().strip() != 'n':
            for branch in new_branches:
                print_msg(Colors.CYAN, f"[CREATE] 创建本地分支: {branch}")
                result = run_command(f"git branch --track '{branch}' 'origin/{branch}'", capture_output=True)
                if result.returncode != 0:
                    print_msg(Colors.RED, f"[ERROR] 无法创建分支 {branch}")
            print_msg(Colors.GREEN, "[OK] 所有新分支创建完成")
    except (EOFError, KeyboardInterrupt):
        print_msg(Colors.YELLOW, "\n[SKIP] 跳过创建新分支")

def sync_all_branches():
    """同步所有分支"""
    print_msg(Colors.BLUE, "[INFO] 同步所有分支...")
    
    current_branch = get_current_branch()
    local_branches = get_local_branches()
    updated_branches = []
    failed_branches = []
    
    for branch in local_branches:
        # 检查分支是否有远程跟踪
        remote_result = run_command(f"git config branch.{branch}.remote", capture_output=True)
        if remote_result.returncode != 0:
            continue
            
        remote = remote_result.stdout.strip()
        merge_result = run_command(f"git config branch.{branch}.merge", capture_output=True)
        if merge_result.returncode != 0:
            continue
            
        merge_ref = merge_result.stdout.strip()
        remote_branch = f"{remote}/{merge_ref.replace('refs/heads/', '')}"
        
        # 检查远程分支是否存在
        show_ref_result = run_command(f"git show-ref --verify --quiet refs/remotes/{remote_branch}", capture_output=True)
        if show_ref_result.returncode != 0:
            continue
        
        # 获取本地和远程的提交ID
        local_commit_result = run_command(f"git rev-parse {branch}", capture_output=True)
        remote_commit_result = run_command(f"git rev-parse {remote_branch}", capture_output=True)
        
        if local_commit_result.returncode != 0 or remote_commit_result.returncode != 0:
            continue
            
        local_commit = local_commit_result.stdout.strip()
        remote_commit = remote_commit_result.stdout.strip()
        
        if local_commit != remote_commit:
            if branch == current_branch:
                print_msg(Colors.CYAN, f"[UPDATE] 更新当前分支: {branch}")
                pull_result = run_command("git pull --ff-only", capture_output=True)
                if pull_result.returncode == 0:
                    updated_branches.append(branch)
                else:
                    print_msg(Colors.YELLOW, f"[WARN] 无法快进合并 {branch}，可能需要手动处理")
                    failed_branches.append(branch)
            else:
                print_msg(Colors.CYAN, f"[UPDATE] 更新分支: {branch}")
                # 检查是否可以快进
                merge_base_result = run_command(f"git merge-base --is-ancestor {branch} {remote_branch}", capture_output=True)
                if merge_base_result.returncode == 0:
                    update_result = run_command(f"git update-ref refs/heads/{branch} {remote_commit}", capture_output=True)
                    if update_result.returncode == 0:
                        updated_branches.append(branch)
                    else:
                        failed_branches.append(branch)
                else:
                    print_msg(Colors.YELLOW, f"[WARN] 分支 {branch} 有本地提交，跳过更新")
                    failed_branches.append(branch)
    
    if not updated_branches and not failed_branches:
        print_msg(Colors.GREEN, "[OK] 所有分支都是最新的")
    else:
        if updated_branches:
            print_msg(Colors.GREEN, f"[OK] 已更新 {len(updated_branches)} 个分支：")
            for branch in updated_branches:
                print(f"   - {branch}")
        if failed_branches:
            print_msg(Colors.YELLOW, "[WARN] 以下分支需要手动处理：")
            for branch in failed_branches:
                print(f"   - {branch}")

def sync_tags():
    """同步标签"""
    print_msg(Colors.BLUE, "[INFO] 同步标签...")
    
    # 获取同步前的标签数量
    before_result = run_command("git tag | wc -l", capture_output=True)
    before_tags = int(before_result.stdout.strip()) if before_result.returncode == 0 else 0
    
    # 同步标签
    fetch_result = run_command("git fetch origin --tags --prune-tags", capture_output=True)
    if fetch_result.returncode != 0:
        print_msg(Colors.RED, "[ERROR] 标签同步失败")
        return
    
    # 获取同步后的标签数量
    after_result = run_command("git tag | wc -l", capture_output=True)
    after_tags = int(after_result.stdout.strip()) if after_result.returncode == 0 else 0
    
    new_tags = after_tags - before_tags
    if new_tags > 0:
        print_msg(Colors.GREEN, f"[OK] 获取了 {new_tags} 个新标签")
        print_msg(Colors.PURPLE, "[LIST] 最新的标签：")
        latest_tags_result = run_command("git tag --sort=-creatordate | head -5", capture_output=True)
        if latest_tags_result.returncode == 0:
            for tag in latest_tags_result.stdout.strip().split('\n'):
                if tag.strip():
                    print(f"   - {tag.strip()}")
    else:
        print_msg(Colors.GREEN, "[OK] 标签已是最新")

def cleanup_remote_refs():
    """清理已删除的远程分支引用"""
    print_msg(Colors.BLUE, "[INFO] 清理远程引用...")
    
    # 检查有多少需要清理的引用
    dry_run_result = run_command("git remote prune origin --dry-run", capture_output=True)
    if dry_run_result.returncode != 0:
        print_msg(Colors.RED, "[ERROR] 无法检查远程引用")
        return
    
    deleted_count = dry_run_result.stdout.count("would prune")
    if deleted_count > 0:
        print_msg(Colors.YELLOW, f"[CLEAN] 发现 {deleted_count} 个已删除的远程分支引用")
        prune_result = run_command("git remote prune origin", capture_output=True)
        if prune_result.returncode == 0:
            print_msg(Colors.GREEN, "[OK] 清理完成")
        else:
            print_msg(Colors.RED, "[ERROR] 清理失败")
    else:
        print_msg(Colors.GREEN, "[OK] 没有需要清理的引用")

def show_summary():
    """显示同步摘要"""
    print_msg(Colors.PURPLE, "[SUMMARY] 同步摘要：")
    
    current_branch = get_current_branch()
    print(f"   - 当前分支: {current_branch}")
    
    local_branches_result = run_command("git branch | wc -l", capture_output=True)
    local_count = local_branches_result.stdout.strip() if local_branches_result.returncode == 0 else "未知"
    print(f"   - 本地分支数: {local_count}")
    
    remote_branches_result = run_command("git branch -r | grep -v HEAD | wc -l", capture_output=True)
    remote_count = remote_branches_result.stdout.strip() if remote_branches_result.returncode == 0 else "未知"
    print(f"   - 远程分支数: {remote_count}")
    
    tags_result = run_command("git tag | wc -l", capture_output=True)
    tags_count = tags_result.stdout.strip() if tags_result.returncode == 0 else "未知"
    print(f"   - 标签数: {tags_count}")
    
    latest_commit_result = run_command("git log -1 --pretty=format:'%h %s'", capture_output=True)
    latest_commit = latest_commit_result.stdout.strip() if latest_commit_result.returncode == 0 else "无提交"
    print(f"   - 最新提交: {latest_commit}")

def main():
    """主函数"""
    parser = argparse.ArgumentParser(description="Git 同步脚本 (mypull)")
    parser.add_argument("-q", "--quiet", action="store_true", help="静默模式（减少输出）")
    parser.add_argument("-f", "--force", action="store_true", help="强制同步（跳过工作区检查）")
    parser.add_argument("--no-lfs", action="store_true", help="跳过 LFS 文件检查")
    args = parser.parse_args()

    if args.quiet:
        # 重定向输出到 /dev/null 实现静默模式
        sys.stdout = open(os.devnull, 'w')

    print_msg(Colors.CYAN, "[START] Git 同步 (mypull)...")
    print()
    
    # 基础检查
    check_git_repo()
    if not check_working_tree(args.force):
        sys.exit(1)
    
    # LFS 文件检查
    if not args.no_lfs:
        check_lfs_files_status()
        print()
    
    # 记录开始时间
    import time
    start_time = time.time()
    
    # 执行同步步骤
    print_msg(Colors.BLUE, "[INFO] 获取远程更新...")
    fetch_result = run_command("git fetch origin --prune", capture_output=True)
    if fetch_result.returncode != 0:
        print_msg(Colors.RED, "[ERROR] 无法连接到远程仓库")
        sys.exit(1)
    
    create_tracking_branches()
    print()
    
    sync_tags()
    print()
    
    sync_all_branches()
    print()
    
    cleanup_remote_refs()
    print()
    
    show_summary()
    
    # 计算耗时
    end_time = time.time()
    duration = int(end_time - start_time)
    
    print()
    print_msg(Colors.GREEN, f"[DONE] 同步完成！耗时: {duration}秒")

def show_help():
    """显示帮助信息"""
    print("Git 同步脚本 (mypull)")
    print()
    print("用法: mypull [选项]")
    print()
    print("选项:")
    print("  -h, --help     显示此帮助信息")
    print("  -q, --quiet    静默模式（减少输出）")
    print("  -f, --force    强制同步（跳过工作区检查）")
    print("  --no-lfs       跳过 LFS 文件检查")
    print()
    print("功能:")
    print("  * 自动创建远程分支的本地跟踪分支")
    print("  * 同步所有本地分支到最新状态")
    print("  * 获取所有远程标签")
    print("  * 清理已删除的远程分支引用")
    print("  * 检查和清理 LFS 文件")
    print("  * 显示详细的同步摘要")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print_msg(Colors.RED, "\n[ABORT] 同步被用户中断")
        sys.exit(1)
    except Exception as e:
        print_msg(Colors.RED, f"[ERROR] 发生未预期的错误: {str(e)}")
        sys.exit(1)