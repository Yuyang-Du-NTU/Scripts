#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Git 推送脚本 (mypush) 的 Python 重构版本。
功能：智能推送已提交的更改，支持自动提交未暂存的更改，并能自动处理因文件过大导致的推送失败。
"""

import subprocess
import sys
import argparse
import os
import re
import tempfile

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

def get_current_branch():
    """获取当前分支名"""
    result = run_command("git branch --show-current", capture_output=True)
    return result.stdout.strip()

def auto_commit_changes():
    """自动提交所有更改"""
    print_msg(Colors.CYAN, "with python in auto_commit_changes ")

    username = run_command("git config user.name").stdout.strip() or os.getlogin()
    timestamp = run_command("date '+%Y-%m-%d %H:%M:%S'").stdout.strip()
    commit_msg = f"[default commit from mypush] user: {username} at {timestamp}"
    
    print_msg(Colors.CYAN, "[AUTO] 自动提交所有更改...")
    run_command("git add -A")
    result = run_command(f'git commit -m "{commit_msg}"', capture_output=True)
    if "nothing to commit" in result.stdout or "no changes added to commit" in result.stdout:
        print_msg(Colors.YELLOW, "[WARN] 没有需要提交的更改")
        return False
    print_msg(Colors.GREEN, f"[OK] 已自动提交: {commit_msg}")
    return True

def handle_large_file_error(branch, push_error):
    """处理因文件过大导致的推送失败"""
    print_msg(Colors.YELLOW, "[LFS] 检测到大文件推送失败")
    print(f"\n{Colors.RED}错误详情：\n{push_error}{Colors.NC}\n")
    
    try:
        input_text = input(f"{Colors.YELLOW}脚本可以尝试使用 Git LFS 自动处理并重试。是否允许？(Y/n): {Colors.NC}")
        if input_text.lower().strip() == 'n':
            print_msg(Colors.RED, "[ABORT] 已取消 LFS 处理")
            return False
    except (EOFError, KeyboardInterrupt):
        print_msg(Colors.RED, "\n[ABORT] 已取消 LFS 处理")
        return False

    # 自动识别大文件
    match = re.search(r"File is too large: (.*?);", push_error) or \
            re.search(r"remote: error: File (.*?) is", push_error)
    
    large_file = ""
    if match:
        large_file = match.group(1).strip()
        print_msg(Colors.GREEN, f"[LFS] 自动识别出大文件：{large_file}")
        try:
            confirm = input(f"{Colors.YELLOW}是否使用此路径？(Y/n): {Colors.NC}")
            if confirm.lower().strip() == 'n':
                large_file = ""
        except (EOFError, KeyboardInterrupt):
            print_msg(Colors.RED, "\n[ABORT] 操作已取消")
            return False

    if not large_file:
        try:
            large_file = input(f"{Colors.YELLOW}[LFS] 请手动输入大文件路径：{Colors.NC}").strip()
        except (EOFError, KeyboardInterrupt):
            print_msg(Colors.RED, "\n[ABORT] 操作已取消")
            return False

    if not large_file:
        print_msg(Colors.RED, "[ERROR] 未提供大文件路径，操作中止")
        return False

    # 保存原始提交信息
    original_commit_msg = run_command("git log -1 --pretty=%B").stdout.strip()

    # 软重置
    print_msg(Colors.CYAN, "[LFS] 正在撤销上一次提交以处理大文件...")
    run_command("git reset --soft HEAD~1")

    # 安装并追踪 LFS 文件
    print_msg(Colors.CYAN, "[LFS] 正在安装并追踪 LFS 文件...")
    run_command("git lfs install")
    run_command(f"git lfs track '{large_file}'")
    run_command(f"git add .gitattributes '{large_file}'")

    # 重新提交
    print_msg(Colors.CYAN, "[LFS] 正在重新提交...")
    with tempfile.NamedTemporaryFile(mode='w+', delete=False) as tmp:
        tmp.write(original_commit_msg)
        tmp.write("\n\n[LFS Added]")
        tmp_name = tmp.name
    run_command(f"git commit -F {tmp_name}")
    os.remove(tmp_name)

    # 再次推送
    print_msg(Colors.CYAN, "[LFS] 正在重试推送...")
    result = run_command(f"git push origin {branch}", capture_output=True)
    if result.returncode == 0:
        print_msg(Colors.GREEN, "[OK] LFS 处理后推送成功")
        return True
    else:
        print_msg(Colors.RED, "[ERROR] LFS 处理后推送仍然失败")
        print(result.stderr)
        return False

def push_branch(branch):
    """推送单个分支"""
    is_new = branch.endswith(":new")
    branch_name = branch.removesuffix(":new")
    
    push_command = f"git push -u origin {branch_name}" if is_new else f"git push origin {branch_name}"
    action_msg = "推送新分支" if is_new else "推送分支"
    
    print_msg(Colors.CYAN, f"[PUSH] {action_msg}: {branch_name}")
    
    result = run_command(push_command, capture_output=True)
    
    if result.returncode == 0:
        print_msg(Colors.GREEN, f"[OK] 成功推送: {branch_name}")
        return True
    
    # 检查是否为大文件错误
    error_output = result.stderr
    if "File is too large" in error_output or "size exceeds" in error_output:
        return handle_large_file_error(branch_name, error_output)
    else:
        print_msg(Colors.RED, f"[ERROR] 推送失败: {branch_name}")
        print(error_output)
        return False

def get_branches_to_push():
    """获取所有需要推送的分支"""
    branches = []
    ref_result = run_command("git for-each-ref --format='%(refname:short)' refs/heads/")
    
    for branch in ref_result.stdout.strip().split('\n'):
        if not branch:
            continue
        
        upstream_result = run_command(f"git rev-parse --abbrev-ref {branch}@{{upstream}}", capture_output=True)
        if upstream_result.returncode != 0:
            branches.append(f"{branch}:new")
            continue

        local_ref = run_command(f"git rev-parse {branch}").stdout.strip()
        remote_ref = run_command(f"git rev-parse {branch}@{{upstream}}").stdout.strip()

        if local_ref != remote_ref:
            branches.append(branch)
            
    return branches

def push_all_branches():
    """推送所有需要推送的分支"""
    print_msg(Colors.BLUE, "[INFO] 检查需要推送的分支...")
    branches = get_branches_to_push()
    
    if not branches:
        print_msg(Colors.GREEN, "[OK] 没有需要推送的分支")
        return

    print_msg(Colors.YELLOW, f"[INFO] 发现 {len(branches)} 个需要推送的分支")
    success_count = 0
    failed_branches = []

    for branch in branches:
        if push_branch(branch):
            success_count += 1
        else:
            failed_branches.append(branch.removesuffix(":new"))
    
    print("")
    if failed_branches:
        print_msg(Colors.RED, "[WARN] 以下分支推送失败：")
        for b in failed_branches:
            print(f"   - {b}")
            
    print_msg(Colors.GREEN, f"[SUMMARY] 成功推送 {success_count}/{len(branches)} 个分支")

def main():
    """主函数"""
    parser = argparse.ArgumentParser(description="Git 推送脚本 (mypush)")
    parser.add_argument("-d", "--default", action="store_true", help="自动提交未暂存的更改（使用默认提交信息）")
    parser.add_argument("-c", "--current", action="store_true", help="仅推送当前分支")
    parser.add_argument("-f", "--force", action="store_true", help="强制推送当前分支（使用 --force-with-lease）")
    parser.add_argument("-t", "--tags", action="store_true", help="仅推送标签")
    args = parser.parse_args()

    print_msg(Colors.CYAN, "[START] Git 推送 (mypush)...")
    print_msg(Colors.CYAN, "with python")

    check_git_repo()
    print_msg(Colors.CYAN, "with python")

    if args.force:
        # 强制推送逻辑
        current_branch = get_current_branch()
        print_msg(Colors.RED, f"[WARN] 强制推送当前分支: {current_branch}")
        if input("确定要强制推送吗？这可能会覆盖远程更改！(yes/N): ").lower() == 'yes':
            run_command(f"git push origin {current_branch} --force-with-lease")
            print_msg(Colors.GREEN, "[OK] 强制推送完成")
        else:
            print_msg(Colors.YELLOW, "[CANCEL] 已取消强制推送")
        sys.exit(0)

    if args.tags:
        # 推送标签逻辑
        print_msg(Colors.BLUE, "[INFO] 推送所有标签...")
        run_command("git push origin --tags")
        print_msg(Colors.GREEN, "[OK] 标签推送完成")
        sys.exit(0)

    if args.default:
        print_msg(Colors.CYAN, "with python in default")

        status_result = run_command("git status --porcelain")
        if status_result.stdout.strip():
            auto_commit_changes()
            print("")
    else:
        status_result = run_command("git status --porcelain")
        if status_result.stdout.strip():
            print_msg(Colors.YELLOW, "[WARN] 检测到未提交的更改：")
            print(run_command("git status -s").stdout)
            print_msg(Colors.RED, "[ABORT] 请先提交更改或使用 -d 选项自动提交")
            sys.exit(1)

    if args.current:
        current_branch = get_current_branch()
        push_branch(current_branch)
    else:
        push_all_branches()

    print_msg(Colors.GREEN, "\n[DONE] 推送完成！")

if __name__ == "__main__":
    main()
