#!/usr/bin/env python3
"""把本地 git 历史镜像到 GitHub —— 全程走 GitHub REST API，不用 git push。

为什么要这个脚本：
  在某些网络环境里 github.com 的 git 协议端口被挡（CONNECT 502 / HTTP2 framing
  error），`git push` 直接失败；但 api.github.com 和 uploads.github.com 是通的。
  这个脚本就绕开 git 协议，用「blob → tree → commit → ref」四步把历史原样搬过去，
  提交信息、作者、时间、树结构都保留。

它做的事：
  1. 读远端 refs/heads/<branch>：不存在就全量灌入；已存在且是本地历史的祖先，就只补新提交
  2. 逐个提交：为改动文件建 blob，用 base_tree 增量建 tree，建 commit 串成父子链
  3. 最后把 refs/heads/<branch> 指到最新 commit（已存在则 PATCH 前移）

  因为 GitHub 对相同 tree/parents/作者/说明算出的 commit sha 与本地 git 完全一致，
  增量推送只比对 sha 即可，不会产生重复历史。

  安全性：远端历史一旦与本地分叉，脚本直接报错退出，不会覆盖远端。

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
import datetime as dt
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


def list_commits(base: str | None = None) -> list[str]:
    """按时间正序返回要推送的提交。

    base 为 None 时是整条历史；否则只返回 base 之后的新提交。
    要求是单链（合并提交会让父指针不唯一）。
    """
    rev = f"{base}..HEAD" if base else "HEAD"
    out = git_text("rev-list", "--reverse", rev).split()
    return out


def is_ancestor(sha: str, descendant: str) -> bool:
    """sha 是否是 descendant 的祖先（用来判断远端是不是本地历史的一段）。"""
    r = subprocess.run(
        ["git", "merge-base", "--is-ancestor", sha, descendant],
        cwd=ROOT, capture_output=True,
    )
    return r.returncode == 0


def find_local_commit_by_tree(remote_sha: str) -> str | None:
    """远端提交的哈希在本地不存在时，按 tree 找出对应的本地提交。

    什么时候会走到这：别处用 API 推过同一个提交、但消息末尾多了个空行，
    内容一样、哈希不一样。这时远端 tip 不是本地祖先，直接判分叉会误伤。
    按 tree 对齐（取最新的匹配）就能接着往下推。
    """
    code, body = api("GET", f"/repos/{REPO}/git/commits/{remote_sha}")
    if code != 200:
        return None
    want = body["tree"]["sha"]
    for line in git_text("log", "--format=%H %T", "HEAD").splitlines():
        sha, _, tree = line.partition(" ")
        if tree.strip() == want:
            return sha
    return None


def parse_ident(text: str) -> dict:
    """把 'Name <email> 1791556981 +0800' 拆成 API 要的 {name, email, date}。"""
    lt = text.rfind("<")
    gt = text.rfind(">")
    name = text[:lt].strip()
    email = text[lt + 1:gt]
    parts = text[gt + 1:].split()
    epoch = int(parts[0])
    tz = parts[1] if len(parts) > 1 else "+0000"
    sign = -1 if tz.startswith("-") else 1
    offset = dt.timedelta(hours=int(tz[1:3]), minutes=int(tz[3:5])) * sign
    when = dt.datetime.fromtimestamp(epoch, dt.timezone(offset))
    return {"name": name, "email": email, "date": when.isoformat()}


def commit_meta(sha: str) -> dict:
    """取提交的说明、作者与提交者（含时间）。

    这里直接读 commit 对象的原文并切开 header / message。
    别偷懒用 `git log --format=%B`：git 会在每条输出后补一个换行，
    说明末尾就多出一个空行，算出来的 commit SHA 和本地对不上
    （GitHub 是原样保存 message 的，多一个字符就是另一个提交）。
    """
    raw = git_text("cat-file", "commit", sha)
    headers, _, message = raw.partition("\n\n")
    found: dict = {}
    for line in headers.splitlines():
        if line.startswith("author "):
            found["author"] = parse_ident(line[len("author "):])
        elif line.startswith("committer "):
            found["committer"] = parse_ident(line[len("committer "):])
    if "author" not in found or "committer" not in found:
        raise RuntimeError(f"提交 {sha[:7]} 的对象缺少作者信息")
    return {"message": message, "author": found["author"], "committer": found["committer"]}


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

    if not TOKEN:
        print("缺少 GITHUB_TOKEN。", file=sys.stderr)
        print("请到 https://github.com/settings/tokens 创建 PAT（需要 Contents: Read and write），然后：", file=sys.stderr)
        print(f"  GITHUB_TOKEN=xxx tool/push_github_api.py", file=sys.stderr)
        return 1

    local_head = git_text("rev-parse", "HEAD").strip()

    # 远端分支已存在时做增量：只要远端 tip 是本地历史的祖先，就把之后的提交补上去。
    # （GitHub 对相同 tree/parents/作者/说明算出的 commit sha 与 git 一致，所以能直接比对。）
    remote_sha: str | None = None
    push_base: str | None = None
    if args.dry_run:
        print("==> --dry-run：不查远端，按全量历史展示")
    else:
        code, body = api("GET", f"/repos/{REPO}/git/ref/heads/{args.branch}")
        if code == 200:
            remote_sha = body["object"]["sha"]
            push_base = remote_sha
            print(f"==> 分支 {args.branch} 已存在（{remote_sha[:7]}）")
            if remote_sha == local_head:
                print("    远端已经是最新，无需推送")
                return 0
            if not is_ancestor(remote_sha, local_head):
                # 哈希对不上但内容可能一致（例如别处用 API 推过、说明末尾多个空行）
                aligned = find_local_commit_by_tree(remote_sha)
                if aligned is None:
                    print(f"远端 {args.branch} 指向 {remote_sha[:7]}，在本地找不到对应提交。", file=sys.stderr)
                    print("两边历史已经分叉，请先人工处理（本脚本不会覆盖远端历史）。", file=sys.stderr)
                    return 1
                push_base = aligned
                print(f"    远端 tip 哈希与本地不一致（内容相同），按 tree 对齐到本地 {aligned[:7]}")
        else:
            print(f"==> 分支 {args.branch} 尚不存在，全量灌入")

    commits = list_commits(push_base)
    if not commits:
        print("==> 没有需要推送的提交")
        return 0
    print(f"==> 待推送 {len(commits)} 个提交")

    # 先读一遍本地历史，顺带校验是单链（合并提交会让父指针不唯一）
    specs = []
    for sha in commits:
        parents = git_text("rev-list", "--parents", "-n", "1", sha).split()[1:]
        if len(parents) > 1:
            raise RuntimeError(f"{sha[:7]} 是合并提交，本脚本只支持单链历史")
        meta = commit_meta(sha)
        files = changed_files(sha)
        specs.append({"sha": sha, "parents": parents, "meta": meta, "files": files})
        first_line = meta["message"].strip().splitlines()[0] if meta["message"].strip() else ""
        print(f"    {sha[:7]}  {len(files):3d} 个文件改动  {first_line}")

    if args.dry_run:
        print("\n==> --dry-run：到此为止，未调用任何 API")
        return 0

    prev_commit_sha: str | None = remote_sha

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

    if remote_sha is None:
        print(f"==> 创建分支 {args.branch}")
        api_ok("POST", f"/repos/{REPO}/git/refs", {
            "ref": f"refs/heads/{args.branch}",
            "sha": prev_commit_sha,
        })
    else:
        print(f"==> 移动分支 {args.branch}：{remote_sha[:7]} → {prev_commit_sha[:7]}")
        # force=false：万一远端在我们操作期间又动了，让 API 报错而不是悄悄覆盖
        api_ok("PATCH", f"/repos/{REPO}/git/refs/heads/{args.branch}", {
            "sha": prev_commit_sha,
            "force": False,
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
