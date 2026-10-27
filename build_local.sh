#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export JAVA_HOME="$HOME/dev-tools/jdk17"
export ANDROID_HOME="$HOME/dev-tools/android-sdk"
export ANDROID_SDK_ROOT="$HOME/dev-tools/android-sdk"
export ANDROID_NDK_HOME="$HOME/dev-tools/android-sdk/ndk/28.2.13676358"
export PATH="$JAVA_HOME/bin:$HOME/dev-tools/go/bin:$HOME/dev-tools/flutter-latest/bin:$ANDROID_HOME/platform-tools:$PATH"
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
export GOPROXY="https://goproxy.cn,direct"
export GOSUMDB="off"

# 检查代理
if [ -n "$ALL_PROXY" ] || [ -n "$http_proxy" ]; then
    echo "[build_local] Using proxy settings..."
fi

cd "$DIR"

BUILD_ALL_SOURCES=("--all-sources")
APP_LABEL="真果鉴 (arm64-v8a 全源版)"

# 过滤自定义参数
ARGS=()
for arg in "$@"; do
    if [ "$arg" == "--hongguo" ]; then
        BUILD_ALL_SOURCES=()
        APP_LABEL="红果鉴 (arm64-v8a 纯红果版)"
    elif [ "$arg" != "--no-bump" ]; then
        ARGS+=("$arg")
    fi
done

# 自动自增版本号（支持 --no-bump 跳过自增）
if [[ "$*" != *"--no-bump"* ]]; then
    NEW_VER=$(python3 scripts/bump_version.py)
    echo "=========================================="
    echo "版本号已自动迭代为: $NEW_VER"
    echo "开始本地编译【$APP_LABEL】..."
    echo "=========================================="
else
    CUR_VER=$(python3 scripts/bump_version.py --get)
    echo "=========================================="
    echo "保持当前版本号: $CUR_VER"
    echo "开始本地编译【$APP_LABEL】..."
    echo "=========================================="
fi

python3 scripts/build_android.py --abi arm64-v8a "${BUILD_ALL_SOURCES[@]}" --cn-mirrors "${ARGS[@]}"

echo "=========================================="
echo "编译完成！新版本 APK 产物在: $DIR/dist/android/"
ls -lh "$DIR/dist/android/"
echo "=========================================="
