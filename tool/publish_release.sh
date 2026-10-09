#!/usr/bin/env bash
#
# Fast Shell → CNB Release 发布脚本
#
# 做五件事：
#   1. 确保 git 标签已推送（Release 的 tag 要对得上仓库里的标签）
#   2. 构建 release 产物，并把 Fast Shell.app 压成 zip
#   3. 在 CNB 上创建（或更新）该版本的 Release
#   4. 取 COS 预签名上传地址，直传安装包
#   5. 回调 verify_url 确认 —— 少这一步附件就是「传上去了但看不到」
#
# 附件上传是标准三步（顺序不能省）：
#   POST /{repo}/-/releases/{id}/asset-upload-url   → { upload_url, verify_url }
#   PUT  <upload_url>                               → 直传对象存储（200/201 为成功）
#   POST <verify_url>                               → 确认，附件落库
#
# 用法：
#   CNB_TOKEN=<访问令牌> tool/publish_release.sh 1.0.0
#   CNB_TOKEN=<访问令牌> tool/publish_release.sh 1.1.0 --skip-build
#   CNB_TOKEN=<访问令牌> tool/publish_release.sh 1.1.0 --notes docs/releases/v1.1.0.md
#
# 令牌从哪来（重要）：
#   https://cnb.cool/profile/token/create
#     · 使用范围：选择 fast-shell 仓库（或「全部仓库」）
#     · 授权范围：必须包含 repo-release:rw
#   注意：`cnb login` 拿到的 OAuth 令牌不带 repo-release:rw，只能用访问令牌。
#
# 可覆盖的环境变量：
#   CNB_TOKEN    必填，访问令牌
#   CNB_API      API 地址，默认 https://api.cnb.cool
#   CNB_REPO     仓库路径，默认 hhaip.com/opensource/fast-shell
#   FLUTTER_BIN  flutter 可执行文件路径
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

CNB_API="${CNB_API:-https://api.cnb.cool}"
CNB_REPO="${CNB_REPO:-hhaip.com/opensource/fast-shell}"
APP="$ROOT/build/macos/Build/Products/Release/Fast Shell.app"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------- 参数

VERSION=""
SKIP_BUILD=0
NOTES=""
PRERELEASE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1; shift ;;
    --notes)      NOTES="${2:-}"; shift 2 ;;
    --prerelease) PRERELEASE=1; shift ;;
    -h|--help)    sed -n '2,30p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    -*)           echo "无法识别的参数：$1" >&2; exit 1 ;;
    *)
      if [[ -n "$VERSION" ]]; then echo "只能指定一个版本号" >&2; exit 1; fi
      VERSION="${1#v}"; shift ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "用法：CNB_TOKEN=<访问令牌> tool/publish_release.sh <版本号> [--skip-build] [--notes 文件]" >&2
  exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "版本号格式应为 1.0.0（可带 v 前缀）" >&2
  exit 1
fi
if [[ -z "${CNB_TOKEN:-}" ]]; then
  echo "缺少 CNB_TOKEN。" >&2
  echo "请到 https://cnb.cool/profile/token/create 创建访问令牌（授权范围需含 repo-release:rw），然后：" >&2
  echo "  CNB_TOKEN=xxx tool/publish_release.sh $VERSION" >&2
  exit 1
fi

TAG="v${VERSION}"
NAME="Fast Shell ${VERSION}"
ASSET="Fast-Shell-${VERSION}-macos.zip"
DIST="$ROOT/build/dist"
ZIP="$DIST/$ASSET"

echo "==> 仓库 $CNB_REPO   tag $TAG   附件 $ASSET"

# ---------------------------------------------------------------- 1. 标签

if git rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then
  echo "==> 标签 $TAG 已存在"
else
  echo "==> 创建标签 $TAG"
  git tag -a "$TAG" -m "Fast Shell $VERSION"
fi
if git ls-remote --tags origin "$TAG" 2>/dev/null | grep -q "$TAG"; then
  echo "    标签已在远端"
else
  echo "==> 推送标签 $TAG"
  git push origin "$TAG"
fi

# ---------------------------------------------------------------- 2. 构建与打包

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

# ---------------------------------------------------------------- API 小工具

BODY=""
HTTP_CODE=""

# api_try <method> <path> [json-body]：结果放 BODY / HTTP_CODE，非 2xx 不中断
api_try() {
  local method="$1" path="$2" body="${3:-}"
  local out="$TMP_DIR/resp.json"
  local args=(-sS -o "$out" -w '%{http_code}' -X "$method" "${CNB_API}${path}"
    -H "Authorization: Bearer ${CNB_TOKEN}"
    -H 'Accept: application/vnd.cnb.api+json')
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
    if [[ "$HTTP_CODE" == "403" ]]; then
      echo "提示：403 通常是访问令牌缺少 repo-release:rw 权限。" >&2
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
api_try GET "/${CNB_REPO}/-/releases/tags/${TAG}"
if [[ "$HTTP_CODE" == 2* ]]; then
  RELEASE_ID="$(printf '%s' "$BODY" | json_get id)"
  echo "==> 版本 $TAG 已存在（id=${RELEASE_ID}），更新说明"
  PAYLOAD="$(python3 -c '
import json, sys
print(json.dumps({"name": sys.argv[1], "body": sys.stdin.read()}, ensure_ascii=False))
' "$NAME" <<<"$BODY_TEXT")"
  api_ok PATCH "/${CNB_REPO}/-/releases/${RELEASE_ID}" "$PAYLOAD"
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
    "make_latest": "false" if pre == "1" else "true",
    "prerelease": pre == "1",
}, ensure_ascii=False))
' "$TAG" "$NAME" "main" "$PRERELEASE" <<<"$BODY_TEXT")"
  api_ok POST "/${CNB_REPO}/-/releases" "$PAYLOAD"
  RELEASE_ID="$(printf '%s' "$BODY" | json_get id)"
  if [[ -z "$RELEASE_ID" ]]; then
    echo "创建成功但没解析出 release id，服务端返回：" >&2
    echo "$BODY" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------- 4. 取上传地址并直传

echo "==> 申请上传地址"
api_ok POST "/${CNB_REPO}/-/releases/${RELEASE_ID}/asset-upload-url" \
  "$(python3 -c '
import json, sys
print(json.dumps({
    "asset_name": sys.argv[1],
    "size": int(sys.argv[2]),
    "overwrite": True,
    "ttl": 0,
}))
' "$ASSET" "$SIZE")"

UPLOAD_URL="$(printf '%s' "$BODY" | json_get upload_url)"
VERIFY_URL="$(printf '%s' "$BODY" | json_get verify_url)"
if [[ -z "$UPLOAD_URL" || -z "$VERIFY_URL" ]]; then
  echo "上传地址返回异常，服务端返回：" >&2
  echo "$BODY" >&2
  exit 1
fi

echo "==> 上传附件（$((SIZE / 1024 / 1024)) MB）"
UP_OUT="$TMP_DIR/upload-resp.txt"
UP_CODE="$(curl -sS -o "$UP_OUT" -w '%{http_code}' -T "$ZIP" \
  -H 'Content-Type: application/octet-stream' "$UPLOAD_URL")"
if [[ "$UP_CODE" != "200" && "$UP_CODE" != "201" ]]; then
  echo "上传失败（HTTP ${UP_CODE}）：" >&2
  cat "$UP_OUT" >&2
  exit 1
fi

# ---------------------------------------------------------------- 5. 确认

echo "==> 确认附件"
CONFIRM_URL="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "$VERIFY_URL")"
CF_OUT="$TMP_DIR/confirm-resp.txt"
CF_CODE="$(curl -sS -o "$CF_OUT" -w '%{http_code}' -X POST "$CONFIRM_URL" \
  -H "Authorization: Bearer ${CNB_TOKEN}" \
  -H 'Accept: application/vnd.cnb.api+json')"
if [[ "$CF_CODE" != "200" ]]; then
  echo "确认失败（HTTP ${CF_CODE}）：" >&2
  cat "$CF_OUT" >&2
  exit 1
fi

echo
echo "==> 完成"
echo "版本页：  https://cnb.cool/${CNB_REPO}/-/releases/tag/${TAG}"
echo "下载地址：https://cnb.cool/${CNB_REPO}/-/releases/download/${TAG}/${ASSET}"
echo "sha256：  $SHA"
