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
        
        # ls-files a路径是相对于仓库根目录的
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

def run_command_with_progress(command):
    """执行命令并实时显示输出，同时捕获错误信息（使用 PTY）"""
    import pty
    import os
    import select

    # 创建一个伪终端
    master_fd, slave_fd = pty.openpty()

    try:
        # 在伪终端中启动子进程
        process = subprocess.Popen(
            command,
            shell=True,
            stdin=subprocess.DEVNULL,
            stdout=slave_fd,
            stderr=slave_fd,
            preexec_fn=os.setsid # 让子进程成为新的会话首进程
        )
        
        # 在父进程中关闭子进程端的fd
        os.close(slave_fd)
        slave_fd = -1 # 标记为已关闭

        output_bytes = []
        
        while process.poll() is None:
            # 使用 select 监控主fd，等待数据可读
            r, _, _ = select.select([master_fd], [], [], 0.1)
            if r:
                try:
                    # 读取伪终端的输出
                    data = os.read(master_fd, 1024)
                except OSError:
                    # 当子进程关闭其终端端时，会发生此错误
                    break

                if not data:  # EOF
                    break
                
                # 实时转发到标准输出并保存
                sys.stdout.buffer.write(data)
                sys.stdout.flush()
                output_bytes.append(data)

        # 确保子进程已完全终止
        process.wait()

        # 解码捕获的完整输出
        full_output = b"".join(output_bytes).decode('utf-8', 'replace')

        # 创建一个类似subprocess.CompletedProcess的对象
        class Result:
            def __init__(self, returncode, stdout, stderr):
                self.returncode = returncode
                self.stdout = stdout
                self.stderr = stderr # 对于PTY，stdout和stderr是合并的

        return Result(process.returncode, full_output, full_output)

    finally:
        # 确保文件描述符被关闭
        if slave_fd != -1:
            os.close(slave_fd)
        os.close(master_fd)

def check_git_repo():
    """检查当前目录是否为 Git 仓库"""
    result = run_command("git rev-parse --git-dir", capture_output=True)
    if result.returncode != 0:
        print_msg(Colors.RED, "[错误] 当前目录不是 Git 仓库")
        sys.exit(1)

def check_interrupted_push():
    """检查是否有中断的push操作需要继续"""
    # 检查是否有正在进行的rebase/merge/cherry-pick等操作
    git_dir = run_command("git rev-parse --git-dir", capture_output=True).stdout.strip()
    
    # 检查各种中断状态
    interrupted_operations = []
    
    if os.path.exists(os.path.join(git_dir, "MERGE_HEAD")):
        interrupted_operations.append("merge")
    if os.path.exists(os.path.join(git_dir, "CHERRY_PICK_HEAD")):
        interrupted_operations.append("cherry-pick")
    if os.path.exists(os.path.join(git_dir, "rebase-merge")) or os.path.exists(os.path.join(git_dir, "rebase-apply")):
        interrupted_operations.append("rebase")
    
    # 检查是否有未推送的提交（可能是之前中断的push）
    current_branch = get_current_branch()
    if current_branch:
        # 检查本地和远程的差异
        upstream_result = run_command(f"git rev-parse --abbrev-ref {current_branch}@{{upstream}}", capture_output=True)
        if upstream_result.returncode == 0:
            # 有上游分支，检查是否有未推送的提交
            unpushed_result = run_command(f"git log {current_branch}@{{upstream}}..{current_branch} --oneline", capture_output=True)
            if unpushed_result.stdout.strip():
                print_msg(Colors.YELLOW, f"[INFO] 检测到分支 {current_branch} 有未推送的提交")
                print_msg(Colors.CYAN, "未推送的提交:")
                print(unpushed_result.stdout)
                
                try:
                    choice = input(f"{Colors.YELLOW}是否要继续推送这些提交？(Y/n): {Colors.NC}")
                    if choice.lower().strip() != 'n':
                        return True
                except (EOFError, KeyboardInterrupt):
                    print_msg(Colors.RED, "\n[ABORT] 操作已取消")
                    return False
    
    if interrupted_operations:
        print_msg(Colors.RED, f"[WARN] 检测到未完成的Git操作: {', '.join(interrupted_operations)}")
        print_msg(Colors.RED, "[ABORT] 请先完成或中止这些操作后再运行推送")
        sys.exit(1)
    
    return False

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
    match = re.search(r"error: File (.*?) is .* MB", push_error)
    
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
    result = run_command_with_progress(f"git push origin {branch}")
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
    
    result = run_command_with_progress(push_command)
    
    if result.returncode == 0:
        print_msg(Colors.GREEN, f"[OK] 成功推送: {branch_name}")
        return True
    
    # 检查是否为大文件错误
    error_output = (result.stderr or "") + (result.stdout or "")
    if "GH001: Large files detected" in error_output:
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
    check_git_repo()
    check_lfs_files_status() # 在这里添加了LFS状态检查
    
    # 检查是否有中断的操作需要继续
    should_continue_push = check_interrupted_push()
    if args.force:
        # 强制推送逻辑
        current_branch = get_current_branch()
        print_msg(Colors.RED, f"[WARN] 强制推送当前分支: {current_branch}")
        if input("确定要强制推送吗？这可能会覆盖远程更改！(yes/N): ").lower() == 'yes':
            run_command_with_progress(f"git push origin {current_branch} --force-with-lease")
            print_msg(Colors.GREEN, "[OK] 强制推送完成")
        else:
            print_msg(Colors.YELLOW, "[CANCEL] 已取消强制推送")
        sys.exit(0)

    if args.tags:
        # 推送标签逻辑
        print_msg(Colors.BLUE, "[INFO] 推送所有标签...")
        run_command_with_progress("git push origin --tags")
        print_msg(Colors.GREEN, "[OK] 标签推送完成")
        sys.exit(0)

    # 如果不是继续推送，才检查未提交的更改
    if not should_continue_push:
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

    # 如果检测到需要继续推送，直接进行推送而不检查未提交的更改
    if should_continue_push:
        print_msg(Colors.CYAN, "[CONTINUE] 继续执行推送...")
        if args.current:
            current_branch = get_current_branch()
            push_branch(current_branch)
        else:
            push_all_branches()
    elif args.current:
        current_branch = get_current_branch()
        push_branch(current_branch)
    else:
        push_all_branches()

    print_msg(Colors.GREEN, "\n[DONE] 推送完成！")

if __name__ == "__main__":
    main()
