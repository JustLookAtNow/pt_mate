#!/bin/bash

# 自动生成 sites_manifest.json 文件
# 该脚本会扫描 assets/sites 目录下的所有 .json 文件
# 并自动生成 sites_manifest.json 文件

set -e  # 遇到错误时退出

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITES_DIR="$SCRIPT_DIR/assets/sites"
MANIFEST_FILE="$SCRIPT_DIR/assets/sites_manifest.json"

echo "🔍 正在扫描网站配置文件..."

# 检查 sites 目录是否存在
if [ ! -d "$SITES_DIR" ]; then
    echo "❌ 错误: assets/sites 目录不存在"
    exit 1
fi

# 进入 sites 目录
cd "$SITES_DIR"

# 获取所有 .json 文件，排除 sites_manifest.json
json_files=($(ls *.json 2>/dev/null | grep -v "sites_manifest.json" | sort))

# 检查是否找到任何配置文件
if [ ${#json_files[@]} -eq 0 ]; then
    echo "⚠️  警告: 在 assets/sites 目录中没有找到任何网站配置文件"
    echo '{"sites":[]}' > $MANIFEST_FILE
    echo "✅ 已生成空的 sites_manifest.json"
    exit 0
fi

echo "📋 找到 ${#json_files[@]} 个网站配置文件:"
for file in "${json_files[@]}"; do
    echo "   - $file"
done

# 生成 sites_manifest.json
echo "🔧 正在生成 sites_manifest.json..."

# 创建临时文件
temp_file=$(mktemp)

# 写入 JSON 开始
echo '{' > "$temp_file"
echo '  "sites": [' >> "$temp_file"

# 添加文件列表
for i in "${!json_files[@]}"; do
    if [ $i -eq $((${#json_files[@]} - 1)) ]; then
        # 最后一个文件，不加逗号
        echo "    \"${json_files[$i]}\"" >> "$temp_file"
    else
        # 不是最后一个文件，加逗号
        echo "    \"${json_files[$i]}\"," >> "$temp_file"
    fi
done

# 写入 JSON 结束
echo '  ]' >> "$temp_file"
echo '}' >> "$temp_file"

# 移动临时文件到目标位置
mv "$temp_file" $MANIFEST_FILE

echo "✅ sites_manifest.json 生成完成!"
echo ""
echo "📄 生成的内容:"
cat "$MANIFEST_FILE"

# 验证生成的 JSON 格式是否正确
if command -v python3 &> /dev/null; then
    if python3 -m json.tool $MANIFEST_FILE > /dev/null 2>&1; then
        echo ""
        echo "✅ JSON 格式验证通过"
    else
        echo ""
        echo "❌ 错误: 生成的 JSON 格式不正确"
        exit 1
    fi
elif command -v node &> /dev/null; then
    if node -e "JSON.parse(require('fs').readFileSync('$MANIFEST_FILE', 'utf8'))" > /dev/null 2>&1; then
        echo ""
        echo "✅ JSON 格式验证通过"
    else
        echo ""
        echo "❌ 错误: 生成的 JSON 格式不正确"
        exit 1
    fi
else
    echo ""
    echo "ℹ️  提示: 未找到 python3 或 node，跳过 JSON 格式验证"
fi

echo ""
echo "🎉 完成! sites_manifest.json 已更新"