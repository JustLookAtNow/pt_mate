#!/bin/bash

# 脚本功能：将一个 APK 文件安装到所有通过 adb 连接的设备上。
# 用法: ./install_all.sh /path/to/your/app.apk

# 检查是否提供了 APK 文件路径作为参数
if [ -z "$1" ]; then
    echo "❌ 错误: 请提供 APK 文件的路径。"
    echo "用法: $0 <path_to_apk>"
    exit 1
fi

APK_PATH="$1"

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