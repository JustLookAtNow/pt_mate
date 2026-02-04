import sys

def main():
    version = sys.argv[1] if len(sys.argv) > 1 else "X.X.X"
    
    template = f"""## 🎉Highlights
- (暂无)

## ✨新增功能
- (请根据 commit 总结)

## 🐛修复问题
- (请根据 commit 总结)

## 🔧性能优化
- (请根据 commit 总结)

## 📋其它
- (请根据 commit 总结)
"""
    print(template)

if __name__ == "__main__":
    main()
