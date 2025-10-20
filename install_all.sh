#!/bin/bash

# 脚本功能：将一个 APK 文件安装到所有通过 adb 连接的设备上。
# 用法: ./install_all.sh release
# 或者: ./install_all.sh debug

# 首先生成最新的 sites_manifest.json
echo "🔄 正在更新网站配置清单..."
if [ -f "./generate_sites_manifest.sh" ]; then
    ./generate_sites_manifest.sh
    echo ""
else
    echo "⚠️  警告: generate_sites_manifest.sh 脚本未找到，跳过清单更新"
    echo ""
fi

# 默认使用debug版本
BUILD_TYPE="debug"

# 如果提供了参数且为release，则使用release版本
if [ -n "$1" ] && [ "$1" = "release" ]; then
    BUILD_TYPE="release"
fi

# 根据构建类型设置APK路径
if [ "$BUILD_TYPE" = "release" ]; then
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
else
    APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
fi

# 显示当前使用的构建类型
echo "🔧 使用 ${BUILD_TYPE} 版本进行安装"

# 检查提供的 APK 文件是否存在
if [ ! -f "${APK_PATH}" ]; then
    echo "❌ 错误: 文件未找到 '${APK_PATH}'"
    exit 1
fi

echo "➡️  准备安装 APK: ${APK_PATH}"
echo "-------------------------------------------"

# 获取所有状态为 "device" 的设备序列号，并进行循环
adb devices | grep -w 'device' | cut -f1 | while read -r device_serial; do
    if [ -n "$device_serial" ]; then
        echo "▶️  正在向设备 [${device_serial}] 安装..."
        # 使用 -r 标志来保留数据更新安装
        adb -s "${device_serial}" install -r "${APK_PATH}"
        echo "✅  设备 [${device_serial}] 安装完成。"
        echo "-------------------------------------------"
    fi
done

echo "🎉 所有设备安装完毕。"