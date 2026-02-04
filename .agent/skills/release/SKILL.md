---
name: release
description: 自动化项目的版本发布流程，包括版本号自增、ChangeLog 提取与汇总、代码提交、打标签以及推送到远程仓库。
---

# Release Skill

此 Skill 旨在提供一个标准化的发布流程。它通过脚本自动处理繁琐的操作，并利用 AI 总结用户可感知的改动。

## 目录结构
- `scripts/bump_version.py`: 自动更新 `pubspec.yaml` 版本号。
- `scripts/get_commits.py`: 提取自上次发布以来的 Git 提交记录。
- `scripts/format_release.py`: 格式化发布日志模板。

## 使用流程

1. **准备阶段**
   - 检查当前分支是否为发布分支（通常是 master/main）。
   - 确认工作区是干净的（没有未提交的改动）。

2. **版本号更新**
   - 运行 `python3 scripts/bump_version.py`。
   - 如果用户提供了版本号，则使用用户指定的；否则，脚本会自动在当前版本号的基础上增加一个小版本号（patch）。

3. **生成发布日志**
   - 运行 `python3 scripts/get_commits.py` 获取原始提交记录。
   - 将记录提供给 AI，根据 `scripts/format_release.py` 的定义，总结出用户可感知的改动。
   - 改动分类应包括：✨新增功能、🐛修复问题、🔧性能优化、📋其它。架构优化和技术细节无需列入用户日志。

4. **提交与标注**
   - 提交改动：`release: {版本号}\n\n{发布日志内容}`。
   - 打标签：`v{版本号}`。

5. **推送**
   - 将代码和标签推送到远程仓库：`git push origin {branch} --tags`。

## 注意事项
- 提交消息必须使用真实的换行，而不是 `\n` 字符串。
- 确认发布日志内容后，再进行 Commit 操作。
