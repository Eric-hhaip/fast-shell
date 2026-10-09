#!/usr/bin/env bash
# Fast Shell 标准发布打包
#
# 做三件事：
#   1. --split-debug-info 剥离 AOT 快照里的调试信息（App.framework 16M → 13M），
#      符号文件留在 build/symbols，需要符号化崩溃日志时用 flutter symbolize；
#   2. 打完包对产物做一次体检：列出包体构成，暴露意外被打进来的资源；
#   3. 提示签名/隔离属性处理方式。
#
# 用法：
#   tool/build_release.sh
#   FLUTTER_BIN=/path/to/flutter tool/build_release.sh
set -euo pipefail

cd "$(dirname "$0")/.."

FLUTTER_BIN="${FLUTTER_BIN:-$HOME/Work/develop/flutter/bin/flutter}"
if [ ! -x "$FLUTTER_BIN" ]; then
  FLUTTER_BIN="$(command -v flutter || true)"
fi
if [ -z "$FLUTTER_BIN" ]; then
  echo "找不到 flutter，请设置 FLUTTER_BIN=/path/to/flutter" >&2
  exit 1
fi

APP="build/macos/Build/Products/Release/Fast Shell.app"
ASSETS="$APP/Contents/Frameworks/App.framework/Resources/flutter_assets"

echo "==> 构建（release + 剥离调试信息）"
"$FLUTTER_BIN" build macos --release --split-debug-info=build/symbols

echo
echo "==> 产物体检：${APP}（$(du -sh "$APP" | cut -f1)）"
echo "--- 包体构成 ---"
du -sh "$APP/Contents"/* 2>/dev/null | sort -hr
echo "--- Frameworks ---"
du -sh "$APP/Contents/Frameworks"/* 2>/dev/null | sort -hr

echo "--- flutter_assets（这里只应出现真正用到的资源）---"
if [ -d "$ASSETS" ]; then
  du -sh "$ASSETS"/* 2>/dev/null | sort -hr
  echo "  · 文件清单："
  find "$ASSETS" -type f | sed "s|$ASSETS/|    |" | sort
else
  echo "  未找到 flutter_assets（异常，请检查构建日志）"
fi

echo "--- 不该出现的东西（调试残留/源码/工具目录）---"
unexpected=$(find "$APP" \
  \( -name "*.dSYM" -o -name "*.dart" -o -name "*.map" -o -name "tool" -o -name "test" \) \
  -print 2>/dev/null || true)
if [ -n "$unexpected" ]; then
  echo "  发现可疑内容：" >&2
  echo "$unexpected" >&2
else
  echo "  无"
fi

echo
echo "==> 完成"
echo "产物：$APP"
echo "符号：build/symbols（保留好，用于符号化崩溃日志）"
echo "首次分发到别的机器若被 Gatekeeper 拦：xattr -dr com.apple.quarantine \"$APP\""
