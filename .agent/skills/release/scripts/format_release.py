import sys

def main():
    version = sys.argv[1] if len(sys.argv) > 1 else "X.X.X"
    
    template = f"""## 🎉Highlights
- (请根据 commit 总结亮点，如果没亮点则整块省略，不要写“暂无”等字样且不保留标题)

## ✨新增功能
- (请根据 commit 总结内容，如果没有新增功能则整块省略)

## 🐛修复问题
- (请根据 commit 总结内容，如果没有修复问题则整块省略)

## 🔧性能优化
- (请根据 commit 总结内容，如果没有性能优化则整块省略)

## 📋其它
- (请根据 commit 总结内容，如果没有其它改动则整块省略)
"""
    print(template)

if __name__ == "__main__":
    main()
