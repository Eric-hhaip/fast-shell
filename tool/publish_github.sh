#!/usr/bin/env bash
#
# Fast Shell → GitHub 发布脚本（CNB 的镜像通道）
#
# 做四件事：
#   1. 确保 main 与 git 标签都在 GitHub 上（Release 的 tag 要对得上仓库里的标签）
#   2. 构建 release 产物，并把 Fast Shell.app 压成 zip
#   3. 在 GitHub 上创建（或更新）该版本的 Release
#   4. 上传安装包附件
#
# 两条同步通道（自动选）：
#   优先走 git 协议 `git push`；如果 github.com 的 git 协议被网络挡掉
#   （CONNECT 502 / HTTP2 framing error），自动退回 GitHub REST API 镜像
#   （tool/push_github_api.py，blob→tree→commit→ref，历史原样保留）。
#   两条路都只依赖 api.github.com / github.com，附件走 uploads.github.com。
#
# 用法：
#   GITHUB_TOKEN=<PAT> tool/publish_github.sh 1.0.0
#   GITHUB_TOKEN=<PAT> tool/publish_github.sh 1.1.0 --skip-build
#   GITHUB_TOKEN=<PAT> tool/publish_github.sh 1.1.0 --notes docs/releases/v1.1.0.md
#   GITHUB_TOKEN=<PAT> tool/publish_github.sh 1.0.0 --notes-only --notes docs/releases/v1.0.0.md
#
# 令牌从哪来（重要）：
#   https://github.com/settings/tokens
#     · Classic PAT：勾 repo（私有库）或 public_repo（公开库）
#     · 或 Fine-grained PAT：仓库选 fast-shell，权限 Contents = Read and write
#   令牌只在本次运行的进程环境里用，脚本不会把它写进 git 配置或磁盘。
#
# 可覆盖的环境变量：
#   GITHUB_TOKEN  必填，Personal Access Token
#   GITHUB_API    API 地址，默认 https://api.github.com
#   GITHUB_REPO   仓库路径，默认 Eric-hhaip/fast-shell
#   GITHUB_REMOTE 远端名，默认 github（不存在则自动添加）
#   FLUTTER_BIN   flutter 可执行文件路径
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

GITHUB_API="${GITHUB_API:-https://api.github.com}"
GITHUB_REPO="${GITHUB_REPO:-Eric-hhaip/fast-shell}"
GITHUB_REMOTE="${GITHUB_REMOTE:-github}"
APP="$ROOT/build/macos/Build/Products/Release/Fast Shell.app"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------- 参数

VERSION=""
SKIP_BUILD=0
NOTES=""
PRERELEASE=0
# 只更新版本说明：不动标签、不构建、不重传附件
NOTES_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1; shift ;;
    --notes-only) NOTES_ONLY=1; shift ;;
    --notes)      NOTES="${2:-}"; shift 2 ;;
    --prerelease) PRERELEASE=1; shift ;;
    -h|--help)    sed -n '2,28p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    -*)           echo "无法识别的参数：$1" >&2; exit 1 ;;
    *)
      if [[ -n "$VERSION" ]]; then echo "只能指定一个版本号" >&2; exit 1; fi
      VERSION="${1#v}"; shift ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "用法：GITHUB_TOKEN=<PAT> tool/publish_github.sh <版本号> [--skip-build] [--notes 文件]" >&2
  exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "版本号格式应为 1.0.0（可带 v 前缀）" >&2
  exit 1
fi
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "缺少 GITHUB_TOKEN。" >&2
  echo "请到 https://github.com/settings/tokens 创建 PAT（classic 勾 repo / public_repo；" >&2
  echo "fine-grained 给 fast-shell 仓库 Contents: Read and write），然后：" >&2
  echo "  GITHUB_TOKEN=xxx tool/publish_github.sh $VERSION" >&2
  exit 1
fi
if [[ "$NOTES_ONLY" == "1" && -z "$NOTES" ]]; then
  echo "--notes-only 需要同时用 --notes 指定说明文件（否则没有可更新的内容）" >&2
  exit 1
fi

TAG="v${VERSION}"
NAME="Fast Shell ${VERSION}"
ASSET="Fast-Shell-${VERSION}-macos.zip"
DIST="$ROOT/build/dist"
ZIP="$DIST/$ASSET"

echo "==> 仓库 $GITHUB_REPO   tag $TAG   附件 $ASSET"

# ---------------------------------------------------------------- 0. 远端

if ! git remote get-url "$GITHUB_REMOTE" > /dev/null 2>&1; then
  echo "==> 添加远端 $GITHUB_REMOTE"
  git remote add "$GITHUB_REMOTE" "https://github.com/${GITHUB_REPO}.git"
fi
echo "    远端 $GITHUB_REMOTE = $(git remote get-url "$GITHUB_REMOTE")"

# 用 token 的临时 askpass 推送：不落盘、不写 git 配置。
# git 会把提示语（"Username for ..." / "Password for ..."）作为 $1 传进来，
# 用户名固定用 x-access-token，密码才回显令牌 —— 别把令牌同时当成用户名，
# 免得它被写进 git 的错误信息里。脚本随 TMP_DIR 一起删掉。
ASKPASS="$TMP_DIR/askpass.sh"
cat > "$ASKPASS" <<'ASKPASS_EOF'
#!/bin/sh
case "$1" in
  *[Uu]sername*) printf '%s\n' 'x-access-token' ;;
  *)             printf '%s\n' "$GITHUB_TOKEN" ;;
esac
ASKPASS_EOF
chmod +x "$ASKPASS"

push_with_token() {
  # 参数：git push 的其余参数
  # GIT_TERMINAL_PROMPT=0：凭据不对就直接失败，不要卡在交互提示上
  GITHUB_TOKEN="$GITHUB_TOKEN" GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= push "$@"
}

# ---------------------------------------------------------------- 1. 分支与标签

# 有些网络里 github.com 的 git 协议被挡（CONNECT 502 / HTTP2 framing error），
# 但 api.github.com 是通的。先探一下能不能走 git 协议，不行就退回 API 镜像。
# 探针用 git-receive-pack 端点：连通时返回 401（要鉴权），不通时 curl 直接报错。
GIT_REACHABLE=0
if curl -sS --max-time 15 -o /dev/null \
     "https://github.com/${GITHUB_REPO}.git/info/refs?service=git-receive-pack" 2>/dev/null; then
  GIT_REACHABLE=1
fi

if [[ "$GIT_REACHABLE" == "1" ]]; then
  echo "==> 推送 main（git 协议）"
  if ! push_with_token "$GITHUB_REMOTE" main 2>"$TMP_DIR/push-main.err"; then
    cat "$TMP_DIR/push-main.err" >&2
    echo "推送 main 失败。常见原因：token 无 Contents 写权限，或远端有本地没有的提交。" >&2
    exit 1
  fi

  if git rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then
    echo "==> 标签 $TAG 已存在"
  else
    echo "==> 创建标签 $TAG"
    git tag -a "$TAG" -m "Fast Shell $VERSION"
  fi
  echo "==> 推送标签 $TAG"
  if ! push_with_token "$GITHUB_REMOTE" "$TAG" 2>"$TMP_DIR/push-tag.err"; then
    # 标签已存在于远端且指向别处时会失败，提示用户而不是强推
    cat "$TMP_DIR/push-tag.err" >&2
    echo "推送标签失败。若远端 $TAG 已指向其它提交，请确认后自行 git push -f。" >&2
    exit 1
  fi
else
  echo "==> github.com 的 git 协议不可达，改用 GitHub API 镜像历史"
  GITHUB_REPO="$GITHUB_REPO" GITHUB_TOKEN="$GITHUB_TOKEN" GITHUB_API="$GITHUB_API" \
    python3 "$ROOT/tool/push_github_api.py" --branch main
  # 标签不在这里单独推：下面创建 Release 时带 tag_name，GitHub 会自己把标签建在 main 上
fi

# ---------------------------------------------------------------- 2. 构建与打包

if [[ "$NOTES_ONLY" == "1" ]]; then
  echo "==> 仅更新版本说明（--notes-only：不动构建与附件）"
else
  if [[ "$SKIP_BUILD" == "0" ]]; then
    FLUTTER_BIN="${FLUTTER_BIN:-$(command -v flutter || echo "$HOME/Work/develop/flutter/bin/flutter")}"
    if [[ ! -x "$FLUTTER_BIN" ]]; then
      echo "找不到 flutter，请设置 FLUTTER_BIN=/path/to/flutter" >&2
      exit 1
    fi
    echo "==> 构建 release"
    "$FLUTTER_BIN" build macos --release
  else
    echo "==> 跳过构建（--skip-build）"
  fi

  if [[ ! -d "$APP" ]]; then
    echo "产物不存在：$APP" >&2
    exit 1
  fi

  echo "==> 打包 zip"
  mkdir -p "$DIST"
  rm -f "$ZIP"
  # --keepParent 保证解压后拿到的是完整的 Fast Shell.app；
  # 不加 --sequesterRsrc，避免塞进没用的 __MACOSX 目录
  ditto -c -k --keepParent "$APP" "$ZIP"

  SIZE="$(stat -f%z "$ZIP")"
  SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
  echo "    $ASSET  $((SIZE / 1024 / 1024)) MB"
  echo "    sha256 $SHA"
fi

# ---------------------------------------------------------------- API 小工具

BODY=""
HTTP_CODE=""

# api_try <method> <path> [json-body]：结果放 BODY / HTTP_CODE，非 2xx 不中断
api_try() {
  local method="$1" path="$2" body="${3:-}"
  local out="$TMP_DIR/resp.json"
  local args=(-sS -o "$out" -w '%{http_code}' -X "$method" "${GITHUB_API}${path}"
    -H "Authorization: Bearer ${GITHUB_TOKEN}"
    -H 'Accept: application/vnd.github+json'
    -H 'X-GitHub-Api-Version: 2022-11-28'
    -H 'User-Agent: fast-shell-publish')
  if [[ -n "$body" ]]; then
    args+=(-H 'Content-Type: application/json' --data-binary "$body")
  fi
  HTTP_CODE="$(curl "${args[@]}")"
  BODY="$(cat "$out")"
}

api_ok() {
  api_try "$@"
  if [[ "$HTTP_CODE" != 2* ]]; then
    echo "接口失败：${1} ${2}（HTTP ${HTTP_CODE}）" >&2
    echo "$BODY" >&2
    if [[ "$HTTP_CODE" == "401" ]]; then
      echo "提示：401 说明令牌无效或已过期。" >&2
    elif [[ "$HTTP_CODE" == "403" || "$HTTP_CODE" == "404" ]]; then
      echo "提示：403/404 通常是令牌权限不足（需要 Contents: Read and write），" >&2
      echo "      或令牌没有被授权访问 $GITHUB_REPO。" >&2
    fi
    exit 1
  fi
}

# 取 JSON 字段，支持 a.b 与数组下标 a.0.b
json_get() {
  python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw) if raw.strip() else None
except Exception:
    d = None
for key in sys.argv[1].split("."):
    if isinstance(d, list):
        d = d[int(key)] if key.isdigit() and int(key) < len(d) else None
    elif isinstance(d, dict):
        d = d.get(key)
    else:
        d = None
print("" if d is None else d)
' "$1"
}

# ---------------------------------------------------------------- 3. 创建或更新 Release

if [[ -n "$NOTES" ]]; then
  if [[ ! -f "$NOTES" ]]; then echo "说明文件不存在：$NOTES" >&2; exit 1; fi
  BODY_TEXT="$(cat "$NOTES")"
else
  BODY_TEXT="$(printf '版本 %s\n\n安装包：%s\nsha256：%s\n' "$VERSION" "$ASSET" "$SHA")"
fi

RELEASE_ID=""
api_try GET "/repos/${GITHUB_REPO}/releases/tags/${TAG}"
if [[ "$HTTP_CODE" == 2* ]]; then
  RELEASE_ID="$(printf '%s' "$BODY" | json_get id)"
  echo "==> 版本 $TAG 已存在（id=${RELEASE_ID}），更新说明"
  PAYLOAD="$(python3 -c '
import json, sys
print(json.dumps({"name": sys.argv[1], "body": sys.stdin.read()},
                 ensure_ascii=False))
' "$NAME" <<<"$BODY_TEXT")"
  api_ok PATCH "/repos/${GITHUB_REPO}/releases/${RELEASE_ID}" "$PAYLOAD"
else
  echo "==> 创建版本 $TAG"
  PAYLOAD="$(python3 -c '
import json, sys
tag, name, target, pre = sys.argv[1:5]
print(json.dumps({
    "tag_name": tag,
    "name": name,
    "body": sys.stdin.read(),
    "target_commitish": target,
    "draft": False,
    "prerelease": pre == "1",
    "make_latest": "false" if pre == "1" else "true",
}, ensure_ascii=False))
' "$TAG" "$NAME" "main" "$PRERELEASE" <<<"$BODY_TEXT")"
  api_ok POST "/repos/${GITHUB_REPO}/releases" "$PAYLOAD"
  RELEASE_ID="$(printf '%s' "$BODY" | json_get id)"
  if [[ -z "$RELEASE_ID" ]]; then
    echo "创建成功但没解析出 release id，服务端返回：" >&2
    echo "$BODY" >&2
    exit 1
  fi
fi

if [[ "$NOTES_ONLY" == "1" ]]; then
  echo
  echo "==> 完成（附件未改动）"
  echo "版本页：  https://github.com/${GITHUB_REPO}/releases/tag/${TAG}"
  exit 0
fi

# ---------------------------------------------------------------- 4. 上传附件

# GitHub 同名附件不会覆盖，会留下两个 entry —— 先删掉旧的
api_try GET "/repos/${GITHUB_REPO}/releases/${RELEASE_ID}/assets?per_page=100"
OLD_ASSET_ID="$(printf '%s' "$BODY" | python3 -c '
import json, sys
name = sys.argv[1]
try:
    arr = json.loads(sys.stdin.read() or "[]")
except Exception:
    arr = []
for a in arr:
    if a.get("name") == name:
        print(a.get("id")); break
' "$ASSET")"
if [[ -n "$OLD_ASSET_ID" ]]; then
  echo "==> 删除同名旧附件（id=${OLD_ASSET_ID}）"
  api_ok DELETE "/repos/${GITHUB_REPO}/releases/assets/${OLD_ASSET_ID}"
fi

echo "==> 上传附件（$((SIZE / 1024 / 1024)) MB）"
UP_OUT="$TMP_DIR/upload-resp.json"
UP_CODE="$(curl -sS -o "$UP_OUT" -w '%{http_code}' -X POST \
  --data-binary "@${ZIP}" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  -H 'Content-Type: application/octet-stream' \
  -H 'User-Agent: fast-shell-publish' \
  "https://uploads.github.com/repos/${GITHUB_REPO}/releases/${RELEASE_ID}/assets?name=${ASSET}")"
if [[ "$UP_CODE" != "201" && "$UP_CODE" != "200" ]]; then
  echo "上传失败（HTTP ${UP_CODE}）：" >&2
  cat "$UP_OUT" >&2
  exit 1
fi

BROWSER_URL="$(cat "$UP_OUT" | json_get browser_download_url)"
echo "    附件已落库：${BROWSER_URL:-（未返回下载地址）}"

echo
echo "==> 完成"
echo "版本页：  https://github.com/${GITHUB_REPO}/releases/tag/${TAG}"
echo "下载地址：https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${ASSET}"
echo "sha256：  $SHA"
