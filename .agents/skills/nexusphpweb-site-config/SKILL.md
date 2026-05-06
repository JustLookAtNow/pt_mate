---
name: nexusphpweb-site-config
description: 适配 NexusPHPWeb 类型站点的站点配置与 infoFinder 字段编写。需要检查 `assets/sites_manifest.json` 中站点 id 是否存在，缺失时先调用 Add Site 技能创建配置文件，然后依据 `docs/SITE_CONFIGURATION_GUIDE.md` 与 `assets/site_configs.json` 的 NexusPHPWeb 模板生成或更新 `infoFinder`，并用用户提供的 cookie 抓取静态页面信息时使用。
---

# NexusPHPWeb Site Config

## 概览

用于在本仓库中创建或更新 NexusPHPWeb 类型站点配置，重点生成 `infoFinder`，并保证站点 id、manifest 与配置文件一致。

## 工作流

1. 收集用户输入：`id`、`cookie`。必要时确认 cookie 是否为有效登录态；只有在 `id` 不存在时才询问站点根网址与名称。
2. 检查 `assets/sites_manifest.json`：确认 `id` 是否已存在。
3. 若 `id` 不存在：调用 Add Site 技能创建基础站点配置与 manifest 条目，再继续后续步骤。
4. 若 `id` 已存在：读取 `assets/sites/{id}.json` 获取站点根网址与站点类型，避免重复向用户询问。
5. 读取规范与模板：打开 `docs/SITE_CONFIGURATION_GUIDE.md`，再查看 `assets/site_configs.json` 中 `NexusPHPWeb` 部分，确定字段含义与默认结构。
6. 抓取页面：NexusPHPWeb 为静态站点，使用用户 `cookie` 直接访问页面并提取 HTML 信息，编写 `infoFinder`。优先尝试常见路径（如 `usercp.php`、`torrents.php`、`usercp.php?action=tracker`），确保稳定可访问。
7. WAF/反爬处理：若访问返回挑战页（如 SafeLine/Cloudflare）或网络不可达，要求用户提供页面 HTML 文件（浏览器“查看源代码/另存为 HTML”）。必要时从 view‑source 包装 HTML 中提取真实源码（`td.line-content` 合并为真实 HTML）。
8. 路径异常处理：若常见请求 path 下找不到目标信息或直接 404，要求用户提供正确的 path，再继续提取。
9. 写入配置：在站点配置文件中补全或更新 `infoFinder`，保持与模板风格一致。

## 关键约束

- 只在 `id` 缺失时使用 Add Site 技能创建配置文件。
- `infoFinder` 的字段结构以 `docs/SITE_CONFIGURATION_GUIDE.md` 与模板为准，避免自创字段。
- 页面抓取必须带 cookie，优先从可稳定访问的页面中提取信息。
- 未能定位页面路径时必须向用户要 path，避免猜测。
- 仅在无法从 `assets/sites/{id}.json` 获取站点根网址时，才向用户询问站点根网址。
- 若被 WAF 拦截，必须改为使用用户提供的本地 HTML 进行解析，避免猜测。
