#!/usr/bin/env python3
"""把本地 git 历史镜像到 GitHub —— 全程走 GitHub REST API，不用 git push。

为什么要这个脚本：
  在某些网络环境里 github.com 的 git 协议端口被挡（CONNECT 502 / HTTP2 framing
  error），`git push` 直接失败；但 api.github.com 和 uploads.github.com 是通的。
  这个脚本就绕开 git 协议，用「blob → tree → commit → ref」四步把历史原样搬过去，
  提交信息、作者、时间、树结构都保留。

它做的事：
  1. 从本地 git 读出一条线性的提交历史（必须是非合并的单链）
  2. 逐个提交：为改动文件建 blob，用 base_tree 增量建 tree，建 commit 串成父子链
  3. 最后把 refs/heads/<branch> 指到最新 commit

用法：
  GITHUB_TOKEN=<PAT> tool/push_github_api.py
  GITHUB_TOKEN=<PAT> tool/push_github_api.py --branch main
  GITHUB_TOKEN=<PAT> tool/push_github_api.py --dry-run      # 只看本地解析结果，不调 API

可覆盖的环境变量：
  GITHUB_TOKEN  必填（--dry-run 时可不填），Personal Access Token
  GITHUB_API    API 地址，默认 https://api.github.com
  GITHUB_REPO   仓库路径，默认 Eric-hhaip/fast-shell
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

API = os.environ.get("GITHUB_API", "https://api.github.com").rstrip("/")
REPO = os.environ.get("GITHUB_REPO", "Eric-hhaip/fast-shell")
TOKEN = os.environ.get("GITHUB_TOKEN", "")

UA = "fast-shell-push-api"


# ------------------------------------------------------------------ git 读取

def git(*args: str) -> bytes:
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(args)} 失败：{r.stderr.decode('utf-8', 'replace').strip()}"
        )
    return r.stdout


def git_text(*args: str) -> str:
    return git(*args).decode("utf-8", "replace")


def list_commits() -> list[str]:
    """按时间正序返回所有提交（不含合并提交的父，必须是单链）。"""
    out = git_text("rev-list", "--reverse", "HEAD").split()
    if not out:
        raise RuntimeError("当前分支没有任何提交")
    return out


def commit_meta(sha: str) -> dict:
    """取提交的说明、作者与提交者（含时间）。"""
    fmt = "%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI%x00%B"
    raw = git_text("log", "-1", f"--format={fmt}", sha)
    an, ae, ad, cn, ce, cd, msg = raw.split("\x00", 6)
    return {
        "message": msg,
        "author": {"name": an, "email": ae, "date": ad},
        "committer": {"name": cn, "email": ce, "date": cd},
    }


def changed_files(sha: str) -> list[tuple[str, str]]:
    """返回 [(状态, 路径)]，状态为 A/M/D。根提交用 --root 一并列出。"""
    out = git_text("diff-tree", "-r", "--root", "--no-commit-id", "--name-status", sha)
    result = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        status = parts[0][0]
        path = parts[-1]
        result.append((status, path))
    return result


def file_mode(sha: str, path: str) -> str:
    """取文件在指定提交里的权限位（100644 / 100755）。"""
    out = git_text("ls-tree", sha, "--", path).strip()
    if not out:
        return "100644"
    return out.split()[0]


def blob_bytes(sha: str, path: str) -> bytes:
    return git("cat-file", "blob", f"{sha}:{path}")


# ------------------------------------------------------------------ GitHub API

def api(method: str, path: str, payload: dict | None = None) -> tuple[int, dict]:
    url = f"{API}{path}"
    data = None
    headers = {
        "Authorization": f"Bearer {TOKEN}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": UA,
    }
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            body = resp.read().decode("utf-8", "replace")
            return resp.status, (json.loads(body) if body.strip() else {})
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(body)
        except Exception:
            return e.code, {"raw": body}
    except urllib.error.URLError as e:
        raise RuntimeError(f"连不上 {url}：{e.reason}") from e


def api_ok(method: str, path: str, payload: dict | None = None) -> dict:
    code, body = api(method, path, payload)
    if not (200 <= code < 300):
        hint = ""
        if code == 401:
            hint = "\n提示：401 说明令牌无效或已过期。"
        elif code in (403, 404):
            hint = (
                "\n提示：403/404 通常是令牌权限不足（需要 Contents: Read and write），"
                f"\n      或令牌没有被授权访问 {REPO}。"
            )
        raise RuntimeError(f"{method} {path} → HTTP {code}\n{json.dumps(body, ensure_ascii=False, indent=2)}{hint}")
    return body


# ------------------------------------------------------------------ 主流程

def main() -> int:
    ap = argparse.ArgumentParser(description="走 GitHub API 把本地 git 历史镜像上去")
    ap.add_argument("--branch", default="main", help="目标分支，默认 main")
    ap.add_argument("--dry-run", action="store_true", help="只解析本地历史，不调用 API")
    args = ap.parse_args()

    commits = list_commits()
    print(f"==> 本地 {len(commits)} 个提交，仓库 {REPO}，分支 {args.branch}")

    # 先读一遍本地历史，顺带校验是单链（合并提交会让父指针不唯一）
    specs = []
    for sha in commits:
        parents = git_text("rev-list", "--parents", "-n", "1", sha).split()[1:]
        meta = commit_meta(sha)
        files = changed_files(sha)
        specs.append({"sha": sha, "parents": parents, "meta": meta, "files": files})
        short = sha[:7]
        first_line = meta["message"].strip().splitlines()[0] if meta["message"].strip() else ""
        print(f"    {short}  {len(files):3d} 个文件改动  {first_line}")

    if args.dry_run:
        print("\n==> --dry-run：到此为止，未调用任何 API")
        return 0

    if not TOKEN:
        print("缺少 GITHUB_TOKEN。", file=sys.stderr)
        print("请到 https://github.com/settings/tokens 创建 PAT（需要 Contents: Read and write），然后：", file=sys.stderr)
        print(f"  GITHUB_TOKEN=xxx tool/push_github_api.py", file=sys.stderr)
        return 1

    # 目标分支已存在时不动它 —— 覆盖远端历史是危险动作，交给用户用 git push 处理
    code, body = api("GET", f"/repos/{REPO}/git/ref/heads/{args.branch}")
    if code == 200:
        current = body.get("object", {}).get("sha", "?")
        print(f"==> 分支 {args.branch} 已存在（{current[:7]}）")
        print("    本脚本只用于灌入空仓库。已有分支请改用 git push，或先确认可以覆盖。", file=sys.stderr)
        return 1
    print(f"==> 分支 {args.branch} 尚不存在，开始灌入")

    prev_commit_sha: str | None = None

    for i, spec in enumerate(specs, 1):
        short = spec["sha"][:7]
        print(f"==> [{i}/{len(specs)}] {short}")

        entries = []
        for status, path in spec["files"]:
            if status == "D":
                # sha: null 表示删除该路径
                entries.append({"path": path, "mode": "100644", "type": "blob", "sha": None})
                continue
            content = blob_bytes(spec["sha"], path)
            b64 = base64.b64encode(content).decode("ascii")
            blob = api_ok("POST", f"/repos/{REPO}/git/blobs", {"content": b64, "encoding": "base64"})
            entries.append({
                "path": path,
                "mode": file_mode(spec["sha"], path),
                "type": "blob",
                "sha": blob["sha"],
            })

        tree_payload: dict = {"tree": entries}
        if spec["parents"]:
            # 非根提交：以「上一个 GitHub 提交」的树为基底做增量
            # （parent_sha 一定是我们刚建出来的 commit，它的 tree 就是基底）
            code, parent_commit = api("GET", f"/repos/{REPO}/git/commits/{prev_commit_sha}")
            if code != 200:
                raise RuntimeError(f"取不到父提交 {prev_commit_sha} 的树结构（HTTP {code}）")
            tree_payload["base_tree"] = parent_commit["tree"]["sha"]

        tree = api_ok("POST", f"/repos/{REPO}/git/trees", tree_payload)

        commit_payload = {
            "message": spec["meta"]["message"],
            "tree": tree["sha"],
            "parents": [prev_commit_sha] if prev_commit_sha else [],
            "author": spec["meta"]["author"],
            "committer": spec["meta"]["committer"],
        }
        new_commit = api_ok("POST", f"/repos/{REPO}/git/commits", commit_payload)
        prev_commit_sha = new_commit["sha"]
        print(f"    → {prev_commit_sha[:7]}  {len(entries)} 个树节点")

    print(f"==> 创建分支 {args.branch}")
    api_ok("POST", f"/repos/{REPO}/git/refs", {
        "ref": f"refs/heads/{args.branch}",
        "sha": prev_commit_sha,
    })

    print()
    print("==> 完成")
    print(f"仓库地址：https://github.com/{REPO}")
    print(f"最新提交：{prev_commit_sha}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as e:
        print(f"失败：{e}", file=sys.stderr)
        sys.exit(1)
