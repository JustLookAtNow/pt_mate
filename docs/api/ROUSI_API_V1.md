# PeerGo API v1 开发者文档

## 概述

PeerGo API v1 面向 MoviePilot、PT-depiler、自动发种器及其他站点工具。公开 URL 和主要 JSON 字段延续 PtYes API v1，内部实现统一使用 PeerGo 的用户、数字种子 ID、分类属性、审核、对象存储、权限和经济系统。

除特别说明外，所有响应均为 JSON：

```json
{
  "code": 0,
  "message": "success",
  "data": {}
}
```

- `code = 0` 表示成功。
- 失败时 HTTP 状态码表达错误类别，`code` 和 `message` 提供兼容信息。
- 私有响应使用 `Cache-Control: private, no-store`。

## 认证

在网页的「账户设置 → API Key」创建一把个人 API Key：

```http
Authorization: Bearer pgk_...
```

兼容旧客户端的请求头：

```http
api-token: pgk_...
```

若两个请求头同时出现，值必须完全相同。API Key 不应放进 URL、日志或截图。PeerGo 只保存不可还原的摘要；`last_used_at` 最多每六小时合并更新一次，不保存逐请求访问历史。

### 权限范围

| Scope | 用途 |
|---|---|
| `profile:read` | 当前/公开用户资料、做种奖励 |
| `torrent:read` | 列表、搜索、分类属性、详情、评论、收藏 |
| `torrent:download` | 生成短时下载能力并下载种子 |
| `torrent:upload` | 提交种子进入审核 |
| `torrent:purchase:read` | 查看购买状态及自己的购买记录 |
| `torrent:purchase:write` | 使用魔力值购买种子 |
| `attendance:read` | 查看签到状态 |
| `attendance:claim` | 执行签到 |

`torrent:upload` 和 `torrent:purchase:write` 默认不勾选，必须由用户主动授权。现有密钥不会因系统升级自动获得新增写权限。

## 身份与兼容边界

PeerGo 只有一套种子公开身份：正整数数字 ID。

- 详情、评论和购买路由只接受数字 ID，例如 `/api/v1/torrents/9830`。
- 为减少旧工具改动，列表和上传响应仍保留名为 `uuid` 的字段，但值是数字 ID 的字符串形式，例如 `"9830"`。
- `Idempotency-Key` 使用 UUID，仅标识一次写请求，不是种子身份。
- 不恢复、映射或持久化旧站的种子 UUID 身份。

## 用户 API

### 获取当前用户信息

```http
GET /api/v1/profile
```

需要 `profile:read`。

常用响应字段：

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 2179,
    "username": "example",
    "display_name": "示例用户",
    "level": 5,
    "level_text": "Lv.5",
    "registered_at": "2026-01-01T00:00:00Z",
    "last_active_at": "2026-08-27T12:00:00Z",
    "uploaded": 1073741824,
    "downloaded": 536870912,
    "ratio": 2,
    "karma": 1000,
    "experience": 15000,
    "email_verified": true,
    "vip": false,
    "vip_until": null,
    "seeding_leeching_data": {
      "seeding_count": 10,
      "seeding_size": 10737418240,
      "leeching_count": 2,
      "leeching_size": 2147483648
    }
  }
}
```

Tracker 活动暂不可用时，基础资料仍会返回，在线做种/下载统计为当前可用的安全聚合值。

### 获取指定用户公开资料

```http
GET /api/v1/profile/{username}
```

需要 `profile:read`。只返回公开字段，不返回邮箱、会话、IP、Tracker 凭据、限制证据或管理备注。

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 2180,
    "username": "other_user",
    "nickname": "其他用户",
    "avatar": "",
    "role": "user",
    "role_text": "用户",
    "level": 3,
    "uploaded": 2147483648,
    "downloaded": 1073741824,
    "ratio": 2,
    "registered_at": "2026-06-01T00:00:00Z",
    "is_vip": false
  }
}
```

## 分类与属性 API

### 获取分类和发种属性

```http
GET /api/v1/categories
```

需要 `torrent:read`。数据直接来自 PeerGo 后台当前启用的分类、属性和选项。

```json
{
  "code": 0,
  "message": "success",
  "data": [
    {
      "id": 1,
      "name": "movie",
      "label": "电影",
      "icon": "film",
      "attributes": [
        {
          "name": "resolution",
          "label": "分辨率",
          "type": "select",
          "required": true,
          "options": [
            {"value": "2160p", "label": "4K/2160p"},
            {"value": "1080p", "label": "1080p"}
          ]
        },
        {
          "name": "source",
          "label": "来源",
          "type": "select",
          "required": true,
          "options": [
            {"value": "bluray", "label": "Blu-ray"},
            {"value": "webdl", "label": "WEB-DL"}
          ]
        },
        {
          "name": "genre",
          "label": "类型",
          "type": "multi-select",
          "required": false,
          "options": [
            {"value": "action", "label": "动作"},
            {"value": "science-fiction", "label": "科幻"}
          ]
        }
      ]
    }
  ]
}
```

属性规则：

- `select` 只接受一个选项。
- `multi-select` 接受一个或多个选项。
- 发种请求可使用属性 `name` 或后台显示名称。
- 选项可使用 `value` 或显示 `label`，服务端统一转换成稳定选项键。
- 旧字段 `source` 映射到 PeerGo 的 `source-medium` 属性。
- 已停用的属性或选项不会出现在响应中，也不能继续提交。
- 必填、同组至少选一项等最终规则由 PeerGo 数据库在同一事务中重新校验。

## 种子 API

### 获取种子列表

```http
GET /api/v1/torrents?page=1&page_size=20&category=movie&keyword=example
```

需要 `torrent:read`。

| 参数 | 类型 | 默认值 | 说明 |
|---|---:|---:|---|
| `page` | integer | 1 | 从 1 开始 |
| `page_size` | integer | 20 | 1–100 |
| `category` | string | 空 | 分类 API 返回的名称 |
| `keyword` | string | 空 | 标题/副标题关键词，最多 100 字符 |

`GET /api/v1/search` 是相同查询的兼容别名。

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "torrents": [
      {
        "id": 9830,
        "uuid": "9830",
        "title": "Example Movie 2026 1080p BluRay",
        "subtitle": "示例电影",
        "category": "movie",
        "category_name": "电影",
        "size": 4294967296,
        "seeders": 10,
        "leechers": 2,
        "downloads": 100,
        "uploader": "uploader_name",
        "uploader_id": 2179,
        "anonymous": false,
        "created_at": "2026-08-27T00:00:00Z",
        "promotion": {
          "type": 2,
          "time_type": 2,
          "is_active": true,
          "is_global": false,
          "until": "2026-08-31T00:00:00Z",
          "up_multiplier": 1,
          "down_multiplier": 0
        }
      }
    ],
    "total": 1,
    "page": 1,
    "page_size": 20,
    "total_pages": 1
  }
}
```

匿名种子的 `uploader` 为“匿名”，`uploader_id` 为 `0`。

### 上传种子

```http
POST /api/v1/torrents
Authorization: Bearer pgk_...
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
Content-Type: application/json
```

需要 `torrent:upload`。`Idempotency-Key` 可省略；建议工具生成 UUID 并在网络重试时复用。

```json
{
  "torrent": "ZDg6YW5ub3VuY2UzNjpodHRwOi8v...",
  "title": "Example Movie 2026 1080p BluRay x264",
  "subtitle": "示例电影",
  "description": "## 简介\n\n这是一部示例电影。",
  "category": "movie",
  "attributes": {
    "resolution": "1080p",
    "source": "Blu-ray",
    "genre": ["动作", "科幻"]
  },
  "tags": "国语,中字",
  "media_info": "General\nComplete name: ...",
  "images": [
    "data:image/jpeg;base64,/9j/4AAQ..."
  ],
  "anonymous": false,
  "price": 0,
  "imdb_id": "tt1234567",
  "tmdb_id": "12345",
  "douban_id": "1292052"
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `torrent` | 是 | Base64 `.torrent`，兼容接口上限 10 MiB，仍受当前站点策略约束 |
| `title` | 是 | 标题 |
| `subtitle` | 否 | 副标题 |
| `description` | 是 | Markdown；禁止 `![](...)` 和 `<img>` 图片链接 |
| `category` | 是 | 分类名称；空值仅在站点启用了 `other` 分类时回落到该分类 |
| `attributes` | 按分类 | 分类属性对象 |
| `tags` | 否 | 为兼容旧工具接受；PeerGo 当前不保存无约束标签垃圾数据 |
| `media_info` | 否 | MediaInfo/BDInfo 原文 |
| `images` | 否 | 最多 6 张，JPEG/PNG/WebP，每张最多 2 MiB，并受当前像素策略约束 |
| `anonymous` | 否 | 是否匿名发布 |
| `price` | 否 | 0–1,000,000 的整数魔力值；默认 0 |
| `imdb_id` | 否 | `tt` 加 7–10 位数字 |
| `tmdb_id` | 否 | 数字 ID |
| `douban_id` | 否 | 数字 ID |

响应：

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 9831,
    "uuid": "9831",
    "info_hash": "abc123def456abc123def456abc123def456abcd",
    "status": "pending"
  }
}
```

上传始终先进入 PeerGo 审核流程；具备站点“可信发布”资格的用户可能得到 `approved`。对象存储成功不等同于 Tracker 放行。

常用兼容错误码：

| code | 说明 |
|---:|---|
| 4001 | 请求或种子文件无效 |
| 4002 | 图片超过 6 张 |
| 4003 | 上传失败 |
| 4004 | info hash 或对象重复 |
| 4005 | 未验证邮箱、无发种权限或未授予 scope |
| 4006 | 文件超过当前策略 |
| 4007 | 分类不存在或已停用 |
| 4008 | 分类属性、必填项或选项无效 |

### 获取种子详情

```http
GET /api/v1/torrents/{numeric_id}
```

需要 `torrent:read`；拥有 `torrent:download` 时，且当前用户有下载权限，响应会带短时 `download_url`。

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 9830,
    "uuid": "9830",
    "title": "Example Movie 2026 1080p BluRay",
    "subtitle": "示例电影",
    "description": "## 简介\n\n...",
    "category": "movie",
    "category_name": "电影",
    "size": 4294967296,
    "seeders": 10,
    "leechers": 2,
    "downloads": 100,
    "uploader": "uploader_name",
    "uploader_id": 2179,
    "anonymous": false,
    "created_at": "2026-08-27T00:00:00Z",
    "info_hash": "abc123def456abc123def456abc123def456abcd",
    "files": [
      {"id": 1, "path": "movie.mkv", "size": 4294967296}
    ],
    "images": [
      {"url": "https://rousi.pro/api/v1/torrents/9830/screenshots/0", "is_cover": true}
    ],
    "media_info": "General\nComplete name: ...",
    "attributes": {
      "resolution": "1080p",
      "source": "bluray",
      "genre": ["action", "science-fiction"]
    },
    "download_url": "https://rousi.pro/api/compat/moviepilot/v1/torrents/9830/download?capability=...",
    "price": 0,
    "is_purchased": true,
    "other_versions": [],
    "promotion": {
      "type": 1,
      "time_type": 1,
      "is_active": false,
      "is_global": false,
      "until": null,
      "up_multiplier": 1,
      "down_multiplier": 1
    }
  }
}
```

详情文件列表当前最多返回前 100 项，避免单次兼容请求生成无界 JSON。完整文件树请使用 PeerGo 原生分页接口。

#### 付费种子保护

当 `price > 0` 且当前用户尚未购买：

- `info_hash` 是空字符串；
- `files` 是空数组；
- `download_url` 是空字符串；
- `is_purchased` 为 `false`。

上传者、已购买用户和免费种子可正常读取。下载动作仍会再次执行账户限制、邮箱、购买权和 Tracker 凭据检查。

### 获取种子评论

```http
GET /api/v1/torrents/{numeric_id}/comments?page=1&page_size=20
```

需要 `torrent:read`，`page_size` 为 1–100。

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "comments": [
      {
        "id": "0198f20a-6da8-7e51-9c64-111111111111",
        "content": "感谢分享！",
        "user_id": 2180,
        "username": "commenter",
        "avatar": "",
        "created_at": "2026-08-27T12:00:00Z"
      }
    ],
    "total": 1,
    "page": 1,
    "page_size": 20,
    "total_pages": 1
  }
}
```

评论自身使用 PeerGo UUID；这不是种子身份。用户仍使用稳定数字 ID。

## 收藏 API

### 获取我的收藏

```http
GET /api/v1/bookmarks?page=1&page_size=20
```

需要 `torrent:read`，`page_size` 为 1–100。返回结构与种子列表一致，按收藏时间倒序。不可见或已删除种子不会返回。

收藏/取消收藏写操作仍使用 PeerGo 原生网页 API，兼容 v1 暂不开放。

## 购买 API

购买使用 PeerGo 原子魔力账本和不可变权益记录。客户端不得通过“下载失败后自动购买”等隐式行为代替用户确认。

### 查看购买状态

```http
GET /api/v1/torrents/{numeric_id}/purchase
```

需要 `torrent:purchase:read`。

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "torrent_id": 9830,
    "title": "Example Movie",
    "price": 100,
    "tax": 10,
    "seller_income": 90,
    "magic_balance": 500,
    "state": "purchase_required",
    "is_purchased": false,
    "purchased_at": null,
    "legacy_import": false
  }
}
```

`state` 可能为：`free`、`uploader`、`purchased`、`purchase_required`、`purchase_disabled`。

### 购买种子

```http
POST /api/v1/torrents/{numeric_id}/purchase
Authorization: Bearer pgk_...
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
Content-Type: application/json

{"expected_price":100}
```

需要 `torrent:purchase:write`。`Idempotency-Key` 必须是 UUID；网络重试必须复用同一个值。

建议提交 `expected_price`。若管理员在读取状态后调整价格，服务端返回 `409`，不会按新价格静默扣款。

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "request_id": "550e8400-e29b-41d4-a716-446655440000",
    "torrent_id": 9830,
    "price": 100,
    "tax": 10,
    "seller_income": 90,
    "balance_after": 400,
    "purchased_at": "2026-08-27T12:00:00Z",
    "replayed": false
  }
}
```

购买、税费、卖家收入、权益授予和余额变化在同一个数据库事务中完成。

### 获取我的购买记录

```http
GET /api/v1/purchases?page=1&page_size=20
```

需要 `torrent:purchase:read`，`page_size` 为 1–50。返回当前有效且未退款的权益；历史成交价不会随管理员后来改价而改变。

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "purchases": [
      {
        "torrent_id": 9830,
        "title": "Example Movie",
        "category_name": "电影",
        "torrent_state": "published",
        "price": 100,
        "purchased_at": "2026-08-27T12:00:00Z",
        "legacy_import": false
      }
    ],
    "total": 1,
    "page": 1,
    "page_size": 20,
    "total_pages": 1
  }
}
```

## 做种奖励与签到兼容

### 最近一次做种奖励结算

```http
GET /api/v1/seeding-reward
```

需要 `profile:read`。返回最近一个已完成结算窗口的奖励，不因外部工具轮询而新建数据库记录。

```json
{"code":0,"message":"success","data":{"total_reward":12}}
```

### 签到状态

```http
GET /api/points/attendance/stats
```

需要 `attendance:read`。

### 执行签到

```http
POST /api/points/attendance
Content-Type: application/json

{"mode":"fixed"}
```

需要 `attendance:claim`。`mode` 省略时为 `fixed`。

## 下载兼容

详情返回的 `download_url` 是带签名的短时能力 URL：

- 有效期约 5 分钟；
- 绑定用户、种子 ID 和 API Key 版本；
- API Key 被轮换或撤销后立即失效；
- 下载时仍执行 PeerGo 购买、限制、邮箱和 Tracker 凭据规则。

PT-depiler 的旧固定路由 `/api/torrent/{numeric_id}/download/{api_key}` 暂时保留用于迁移，但新工具必须使用请求头认证及详情返回的短时 URL，避免密钥进入代理日志和浏览器历史。

## HTTP 错误

| HTTP | 常见原因 |
|---:|---|
| 400 | 参数、分页、分类属性、文件或幂等键无效 |
| 401 | API Key 缺失、格式错误、无效或已撤销 |
| 402 | 魔力值余额不足，或下载前需要购买 |
| 403 | scope/站点权限不足、账号受限、购买关闭 |
| 404 | 用户、分类或已发布种子不存在 |
| 409 | 价格变化、重复请求冲突、无需购买、状态变化 |
| 429 | 单用户内存速率限制触发 |
| 503 | 对象存储或兼容依赖暂不可用 |

错误响应示例：

```json
{
  "code": 409,
  "message": "种子价格已变化，请重新确认"
}
```

## cURL 示例

```bash
curl -H 'Authorization: Bearer pgk_REPLACE_ME' \
  'https://rousi.pro/api/v1/categories'
```

```bash
curl -H 'Authorization: Bearer pgk_REPLACE_ME' \
  'https://rousi.pro/api/v1/torrents?page=1&page_size=100&category=movie'
```

```bash
curl -X POST \
  -H 'Authorization: Bearer pgk_REPLACE_ME' \
  -H 'Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000' \
  -H 'Content-Type: application/json' \
  --data '{"expected_price":100}' \
  'https://rousi.pro/api/v1/torrents/9830/purchase'
```

## 版本策略

API v1 优先保持 URL 和常用字段兼容；安全边界、唯一身份、审核、存储、权限和结算始终以 PeerGo 为准。新增能力会优先向 v1 添加可选字段或新端点；只有无法安全兼容时才进入后续 API 版本。
