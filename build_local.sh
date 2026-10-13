#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export JAVA_HOME="$HOME/dev-tools/jdk17"
export ANDROID_HOME="$HOME/dev-tools/android-sdk"
export ANDROID_SDK_ROOT="$HOME/dev-tools/android-sdk"
export ANDROID_NDK_HOME="$HOME/dev-tools/android-sdk/ndk/28.2.13676358"
export PATH="$JAVA_HOME/bin:$HOME/dev-tools/go/bin:$HOME/dev-tools/flutter/bin:$ANDROID_HOME/platform-tools:$PATH"
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
export GOPROXY="https://goproxy.cn,direct"
export GOSUMDB="off"

# 检查代理
if [ -n "$ALL_PROXY" ] || [ -n "$http_proxy" ]; then
    echo "[build_local] Using proxy settings..."
fi

echo "=========================================="
echo "开始本地编译【真果鉴】(arm64-v8a 全源版)..."
echo "=========================================="

cd "$DIR"
python3 scripts/build_android.py --abi arm64-v8a --all-sources --cn-mirrors "$@"

echo "=========================================="
echo "编译完成！APK 产物在: $DIR/dist/android/"
echo "=========================================="
