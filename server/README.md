# PTMate Server

PTMate应用的后端服务，提供自动更新检查和使用统计功能。

## 功能特性

- 自动更新检查API
- 应用使用统计收集
- GitHub Actions集成（版本发布通知）
- PostgreSQL数据存储

## API接口

### 1. 检查更新和上报统计

**POST** `/api/v1/check-update`

请求体：
```json
{
  "device_id": "unique-device-id",
  "platform": "android|ios|linux|macos|windows",
  "app_version": "2.11.0"
}
```

响应：
```json
{
  "has_update": true,
  "latest_version": "2.12.0",
  "release_notes": "新功能和修复...",
  "download_url": "https://github.com/user/repo/releases/tag/v2.12.0"
}
```

### 2. GitHub Actions版本更新

**POST** `/api/v1/github/version-update`

请求体：
```json
{
  "version": "2.12.0",
  "release_notes": "发布说明...",
  "download_url": "https://github.com/user/repo/releases/tag/v2.12.0"
}
```

## 环境配置

复制 `.env.example` 到 `.env` 并配置以下变量：

```bash
# 数据库配置
DB_HOST=localhost
DB_PORT=5432
DB_USER=ptmate
DB_PASSWORD=your_password
DB_NAME=ptmate_db
DB_SSLMODE=disable

# 服务器配置
PORT=8080
GIN_MODE=release

# GitHub配置
GITHUB_WEBHOOK_SECRET=your_github_webhook_secret

# CORS配置
ALLOWED_ORIGINS=*

# 管理端登录配置
ADMIN_USERNAME=admin
ADMIN_PASSWORD=change_me
ADMIN_JWT_SECRET=super_secret_key
ADMIN_TOKEN_TTL_HOURS=168 # 默认7天
```

## 数据库设置

1. 安装PostgreSQL
2. 创建数据库和用户：

```sql
CREATE DATABASE ptmate_db;
CREATE USER ptmate WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE ptmate_db TO ptmate;
```

## 运行服务

```bash
# 安装依赖
go mod tidy

# 运行服务
go run .
```

## 部署

服务可以部署到任何支持Go的云平台，如：
- Heroku
- Railway
- DigitalOcean App Platform
- AWS/GCP/Azure

确保配置好环境变量和PostgreSQL数据库连接。

## 管理看板

- 访问 `/admin/login` 登录后进入 `/admin`
- 看板功能：
  - KPI：今日DAU、最近30天MAU、累计设备
  - 饼图：平台占比、版本占比（点击分片可联动下方列表筛选）
  - 设备列表：分页、搜索、筛选
  - 趋势：日活（DAU）折线图，支持 7 天 / 30 天 / 自定义范围；旁边显示窗口设备数（仅趋势模块受时间窗口影响）

> 时区说明：趋势的每日统计以 UTC+8 为准（Asia/Shanghai）；数据库仍使用 UTC 存储。