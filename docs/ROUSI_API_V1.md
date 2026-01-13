# API v1 开发者文档

## 概述

API v1 是面向开发者的公开 API，使用 Passkey 进行身份认证。所有 API 端点都需要在请求头中携带有效的 Passkey。

## 认证方式

所有请求必须在 `Authorization` 头中携带 Bearer Token（即用户的 Passkey）：

```
Authorization: Bearer <your_passkey>
```

### 获取 Passkey

用户可以在网站的「账户设置」页面查看和重置自己的 Passkey。

### 认证错误响应

| Code | Message |
|------|---------|
| 401 | 缺少认证信息 |
| 401 | 认证格式错误 |
| 401 | Passkey 不能为空 |
| 401 | 无效的 Passkey |
| 403 | 账号已被封禁 |

## 响应格式

所有 API 响应均为 JSON 格式：

```json
{
  "code": 0,
  "message": "success",
  "data": { ... }
}
```

- `code`: 状态码，0 表示成功，非 0 表示错误
- `message`: 状态消息
- `data`: 响应数据（仅成功时返回）

## API 端点

### 用户相关

#### 获取当前用户信息

```
GET /api/v1/profile
```

返回当前认证用户的完整信息。

**查询参数：**

| 参数 | 类型 | 说明 | 示例 |
|------|------|------|------|
| includes | string | 包含的关联数据，逗号分隔 | `inviter,valid_medals` |
| include_fields[user] | string | 包含的用户字段，逗号分隔 | `seeding_leeching_data` |

**includes 可选值：**
- `inviter`: 邀请者信息
- `valid_medals`: 有效勋章列表

**include_fields[user] 可选值：**
- `seeding_leeching_data`: 做种中/下载中数据

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 1,
    "username": "example",
    "email": "user@example.com",
    "nickname": "昵称",
    "avatar": "https://example.com/avatar.jpg",
    "role": "user",
    "role_text": "用户",
    "level": 5,
    "level_text": "Lv.5",
    "email_verified": true,
    "banned": false,
    "is_vip": true,
    "vip_until": "2025-12-31T23:59:59Z",
    "registered_at": "2024-01-01T00:00:00Z",
    "registered_at_human": "2024-01-01 00:00:00",
    "last_active_at": "2024-12-01T12:00:00Z",
    "last_active_at_human": "2024-12-01 12:00:00",
    "uploaded": 1073741824,
    "uploaded_text": "1.00 GB",
    "downloaded": 536870912,
    "downloaded_text": "512.00 MB",
    "ratio": 2.0,
    "ratio_text": "2.00",
    "karma": 1000.5,
    "karma_text": "1.00K",
    "credits": 500.0,
    "credits_text": "500.00",
    "experience": 15000.0,
    "seeding_time": 2592000,
    "seeding_time_text": "30d 0h 0m",
    "leeching_time": 86400,
    "leeching_time_text": "1d 0h 0m",
    "seeding_points_per_hour": 0.5,
    "seeding_points_per_hour_text": "0.50",
    "seeding_karma_per_hour": 1.2,
    "seeding_karma_per_hour_text": "1.20",
    "remaining_invites": 3,
    "attendance_card": 5,
    "inviter": {
      "id": 2,
      "username": "inviter_user",
      "role": "user",
      "role_text": "用户",
      "level": 10,
      "uploaded": 2147483648,
      "downloaded": 1073741824,
      "ratio": 2.0,
      "registered_at": "2023-01-01T00:00:00Z",
      "is_vip": true
    },
    "valid_medals": [
      {
        "id": 1,
        "name": "优秀做种者",
        "get_type": 4,
        "get_type_text": "工作组",
        "image_large": "https://example.com/medal_large.jpg",
        "image_small": "https://example.com/medal_small.jpg",
        "price": 100.0,
        "price_human": "100.00",
        "duration": 30,
        "expire_at": "2025-01-01T00:00:00Z",
        "user_medal_id": 1,
        "wearing_status": 2,
        "wearing_status_text": "佩戴中"
      }
    ],
    "seeding_leeching_data": {
      "seeding_count": 10,
      "seeding_size": 10737418240,
      "leeching_count": 2,
      "leeching_size": 2147483648
    }
  }
}
```

**字段说明：**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | uint | 用户 ID |
| username | string | 用户名 |
| email | string | 邮箱地址（可选） |
| nickname | string | 昵称（可选） |
| avatar | string | 头像 URL（可选） |
| role | string | 角色（user/admin） |
| role_text | string | 角色文本（用户/管理员） |
| level | int | 用户等级 |
| level_text | string | 用户等级文本（Lv.1, Lv.2 等） |
| email_verified | bool | 邮箱是否已验证 |
| banned | bool | 是否被封禁 |
| is_vip | bool | 是否为 VIP |
| vip_until | string | VIP 到期时间（可选，ISO 8601 格式）。如果为永久 VIP（VIPUntil 为 nil），此字段不返回 |
| registered_at | string | 注册时间（ISO 8601 格式） |
| registered_at_human | string | 注册时间格式化（人类可读） |
| last_active_at | string | 最后活跃时间（可选，ISO 8601 格式） |
| last_active_at_human | string | 最后活跃时间格式化（可选） |
| uploaded | int64 | 总上传量（字节） |
| uploaded_text | string | 上传量格式化（人类可读） |
| downloaded | int64 | 总下载量（字节） |
| downloaded_text | string | 下载量格式化（人类可读） |
| ratio | float64 | 分享率（上传量/下载量） |
| ratio_text | string | 分享率格式化（保留两位小数） |
| karma | float64 | 魔力值 |
| karma_text | string | 魔力值格式化（人类可读） |
| credits | float64 | PT 币（做种积分） |
| credits_text | string | PT 币格式化（人类可读） |
| experience | float64 | 经验值 |
| seeding_time | int64 | 做种时间（秒） |
| seeding_time_text | string | 做种时间格式化（人类可读） |
| leeching_time | int64 | 下载时间（秒） |
| leeching_time_text | string | 下载时间格式化（人类可读） |
| seeding_points_per_hour | float64 | 每小时做种积分 |
| seeding_points_per_hour_text | string | 每小时做种积分格式化 |
| seeding_karma_per_hour | float64 | 每小时做种魔力 |
| seeding_karma_per_hour_text | string | 每小时做种魔力格式化 |
| remaining_invites | int | 剩余邀请数量 |
| attendance_card | int | 补签卡数量 |
| inviter | object | 邀请者信息（通过 includes=inviter 获取） |
| valid_medals | array | 有效勋章列表（通过 includes=valid_medals 获取） |
| valid_medals[].id | uint | 勋章 ID |
| valid_medals[].name | string | 勋章名称 |
| valid_medals[].get_type | int | 获取类型（1=购买, 2=授予, 3=赞助, 4=工作组, 5=开发组） |
| valid_medals[].get_type_text | string | 获取类型文本 |
| valid_medals[].image_large | string | 勋章大图 URL |
| valid_medals[].image_small | string | 勋章小图 URL |
| valid_medals[].price | float64 | 勋章价格 |
| valid_medals[].price_human | string | 勋章价格格式化 |
| valid_medals[].duration | int | 持续时间（天） |
| valid_medals[].expire_at | string | 过期时间（可选，ISO 8601 格式） |
| valid_medals[].user_medal_id | uint | 用户勋章 ID |
| valid_medals[].wearing_status | int | 佩戴状态（1=拥有, 2=佩戴中） |
| valid_medals[].wearing_status_text | string | 佩戴状态文本 |
| seeding_leeching_data | object | 做种中/下载中数据（通过 include_fields[user]=seeding_leeching_data 获取） |

#### 获取指定用户公开信息

```
GET /api/v1/profile/:username
```

根据用户名获取用户的公开信息（受限）。

**参数：**

| 参数 | 类型 | 位置 | 说明 |
|------|------|------|------|
| username | string | path | 用户名 |

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 2,
    "username": "other_user",
    "nickname": "其他用户",
    "avatar": "https://example.com/avatar2.jpg",
    "role": "user",
    "role_text": "用户",
    "level": 3,
    "uploaded": 2147483648,
    "downloaded": 1073741824,
    "ratio": 2.0,
    "registered_at": "2024-06-01T00:00:00Z",
    "is_vip": false
  }
}
```

**字段说明：**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | uint | 用户 ID |
| username | string | 用户名 |
| nickname | string | 昵称（可选） |
| avatar | string | 头像 URL（可选） |
| role | string | 角色（user/admin） |
| role_text | string | 角色文本（用户/管理员） |
| level | int | 用户等级 |
| uploaded | int64 | 总上传量（字节） |
| downloaded | int64 | 总下载量（字节） |
| ratio | float64 | 分享率 |
| registered_at | string | 注册时间（ISO 8601 格式） |
| is_vip | bool | 是否为 VIP |

**错误码：**

| Code | 说明 |
|------|------|
| 1001 | 用户不存在 |
| 1002 | 该用户已被封禁 |

---

### 种子相关

#### 获取种子列表

```
GET /api/v1/torrents
```

获取种子列表，支持分页和筛选。

**参数：**

| 参数 | 类型 | 位置 | 默认值 | 说明 |
|------|------|------|--------|------|
| page | int | query | 1 | 页码 |
| page_size | int | query | 20 | 每页数量（最大 100） |
| category | string | query | - | 分类名称 |
| keyword | string | query | - | 搜索关键词 |

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "torrents": [
      {
        "id": 1,
        "uuid": "550e8400-e29b-41d4-a716-446655440000",
        "title": "Example Movie 2024 1080p BluRay",
        "subtitle": "示例电影",
        "category": "movie",
        "category_name": "电影",
        "size": 4294967296,
        "seeders": 10,
        "leechers": 2,
        "downloads": 100,
        "uploader": "uploader_name",
        "uploader_id": 1,
        "anonymous": false,
        "created_at": "2024-12-01T00:00:00Z",
        "cover_image": "https://example.com/cover.jpg",
        "promotion": {
          "type": 2,
          "time_type": 2,
          "is_active": true,
          "is_global": false,
          "until": "2025-01-31T00:00:00+0800",
          "up_multiplier": 1.0,
          "down_multiplier": 0.0
        }
      }
    ],
    "total": 100,
    "page": 1,
    "page_size": 20,
    "total_pages": 5
  }
}
```

**字段说明：**

| 字段 | 类型 | 说明 |
|------|------|------|
| torrents | array | 种子列表 |
| torrents[].id | uint | 种子 ID |
| torrents[].uuid | string | 种子 UUID |
| torrents[].title | string | 标题 |
| torrents[].subtitle | string | 副标题（可选） |
| torrents[].category | string | 分类名称 |
| torrents[].category_name | string | 分类显示名称 |
| torrents[].size | int64 | 种子大小（字节） |
| torrents[].seeders | int | 当前做种人数 |
| torrents[].leechers | int | 当前下载人数 |
| torrents[].downloads | int | 总下载次数 |
| torrents[].uploader | string | 上传者用户名（匿名时显示「匿名」） |
| torrents[].uploader_id | uint | 上传者 ID（匿名时为 0） |
| torrents[].anonymous | bool | 是否匿名发布 |
| torrents[].created_at | string | 创建时间（ISO 8601 格式） |
| torrents[].cover_image | string | 封面图片 URL（可选） |
| torrents[].promotion | object | 促销信息（可选） |
| torrents[].promotion.type | int | 促销类型（1=普通, 2=免费, 3=2X, 4=2X免费, 5=50%, 6=2X50%, 7=30%） |
| torrents[].promotion.time_type | int | 时间类型（0=跟随全站, 1=永久, 2=到期时间） |
| torrents[].promotion.is_active | bool | 是否激活 |
| torrents[].promotion.is_global | bool | 是否使用全站促销 |
| torrents[].promotion.until | string | 到期时间（可选，ISO 8601 格式，如 `2025-01-31T00:00:00+0800`） |
| torrents[].promotion.up_multiplier | float64 | 上传倍数 |
| torrents[].promotion.down_multiplier | float64 | 下载倍数 |
| total | int64 | 总数量 |
| page | int | 当前页码 |
| page_size | int | 每页数量 |
| total_pages | int | 总页数 |

#### 上传种子

```
POST /api/v1/torrents
```

上传新种子。

**请求体：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| torrent | string | 是 | Base64 编码的种子文件（最大 10MB） |
| title | string | 是 | 标题 |
| subtitle | string | 否 | 副标题 |
| description | string | 是 | 描述（支持 Markdown，**禁止包含图片链接**） |
| category | string | 否 | 分类名称（如 movie, tv, music） |
| attributes | object | 否 | 分类属性（如 resolution, source, genre 等，来源 source 应放在此处） |
| tags | string | 否 | 标签（逗号分隔，如 "国语,中字,HDR"） |
| media_info | string | 否 | MediaInfo/BDInfo 信息 |
| images | array | 否 | Base64 编码的图片数组（最多 6 张，单张最大 5MB，总计最大 20MB） |
| anonymous | bool | 否 | 是否匿名发布 |
| price | number | 否 | 种子价格（0 为免费，大于 0 需要购买才能下载） |

**特别说明：**

1. **图片处理**：所有图片必须通过 `images` 字段上传，第一张图片将自动设为封面。
2. **描述格式**：`description` 字段支持 Markdown 格式，但**不允许包含任何图片链接**（如 `![](url)` 或 `<img>` 标签）。所有截图、海报等图片请通过 `images` 字段上传。
3. **分类属性**：上传前请先调用 `GET /api/v1/categories` 获取分类及其属性定义，确保 `attributes` 中的值符合要求。

**请求示例：**

```json
{
  "torrent": "ZDg6YW5ub3VuY2UzNjpodHRwOi8v...",
  "title": "Example Movie 2024 1080p BluRay x264",
  "subtitle": "示例电影",
  "description": "## 简介\n\n这是一部示例电影的详细描述...\n\n## 演员\n\n- 演员A\n- 演员B",
  "category": "movie",
  "attributes": {
    "resolution": "1080p",
    "source": "Blu-ray",
    "genre": ["动作", "科幻"]
  },
  "tags": "国语,中字",
  "media_info": "General\nComplete name: ...",
  "images": [
    "data:image/jpeg;base64,/9j/4AAQ...",
    "data:image/jpeg;base64,/9j/4BBR..."
  ],
  "anonymous": false
}
```

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "uuid": "550e8400-e29b-41d4-a716-446655440000",
    "info_hash": "abc123def456...",
    "status": "approved"
  }
}
```

**响应字段说明：**

| 字段 | 类型 | 说明 |
|------|------|------|
| uuid | string | 种子 UUID，用于后续查询 |
| info_hash | string | 种子 info_hash（40 位十六进制） |
| status | string | 种子状态：approved（已通过）、pending（待审核） |

**错误码：**

| Code | 说明 |
|------|------|
| 4001 | 请求参数错误 |
| 4002 | 图片数量超过限制（最多6张） |
| 4003 | 上传失败 |
| 4004 | 种子已存在 |
| 4005 | 无上传权限（账号被封禁） |
| 4006 | 文件大小超过限制（种子最大10MB，单张图片最大5MB，图片总计最大20MB） |
| 4007 | 无效的分类 |
| 4008 | 属性验证失败（缺少必填属性或属性值无效） |

#### 获取种子详情

```
GET /api/v1/torrents/:id
```

根据种子 ID 或 UUID 获取详细信息。支持两种查询方式：
- 数字 ID：`/api/v1/torrents/123`
- UUID：`/api/v1/torrents/550e8400-e29b-41d4-a716-446655440000`

**参数：**

| 参数 | 类型 | 位置 | 说明 |
|------|------|------|------|
| id | string | path | 种子 ID（数字）或 UUID |

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 1,
    "uuid": "550e8400-e29b-41d4-a716-446655440000",
    "title": "Example Movie 2024 1080p BluRay",
    "subtitle": "示例电影",
    "description": "这是一部示例电影的详细描述...",
    "category": "movie",
    "category_name": "电影",
    "size": 4294967296,
    "seeders": 10,
    "leechers": 2,
    "downloads": 100,
    "uploader": "uploader_name",
    "uploader_id": 1,
    "anonymous": false,
    "created_at": "2024-12-01T00:00:00Z",
    "info_hash": "abc123def456...",
    "files": [
      {"id": 1, "path": "movie.mkv", "size": 4294967296}
    ],
    "images": [
      {"url": "https://example.com/screenshot1.jpg", "is_cover": true},
      {"url": "https://example.com/screenshot2.jpg", "is_cover": false}
    ],
    "media_info": "General\nComplete name: ...",
    "attributes": {
      "resolution": "1080p",
      "source": "BluRay"
    },
    "download_url": "https://example.com/api/torrent/xxx/download/passkey",
    "price": 0,
    "is_purchased": true,
    "promotion": {
      "type": 2,
      "time_type": 2,
      "is_active": true,
      "is_global": false,
      "until": "2025-01-31T00:00:00+0800",
      "up_multiplier": 1.0,
      "down_multiplier": 0.0
    }
  }
}
```

**字段说明：**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | uint | 种子 ID |
| uuid | string | 种子 UUID |
| title | string | 标题 |
| subtitle | string | 副标题（可选） |
| description | string | 描述（Markdown 格式） |
| category | string | 分类名称 |
| category_name | string | 分类显示名称 |
| size | int64 | 种子大小（字节） |
| seeders | int | 当前做种人数 |
| leechers | int | 当前下载人数 |
| downloads | int | 总下载次数 |
| uploader | string | 上传者用户名（匿名时显示「匿名」） |
| uploader_id | uint | 上传者 ID（匿名时为 0） |
| anonymous | bool | 是否匿名发布 |
| created_at | string | 创建时间（ISO 8601 格式） |
| info_hash | string | 种子 info_hash（付费未购买时为空） |
| files | array | 文件列表（付费未购买时为空） |
| files[].id | uint | 文件 ID |
| files[].path | string | 文件路径 |
| files[].size | int64 | 文件大小（字节） |
| images | array | 图片列表 |
| images[].url | string | 图片 URL |
| images[].is_cover | bool | 是否为封面图 |
| media_info | string | MediaInfo/BDInfo 信息（可选） |
| attributes | object | 分类属性键值对 |
| download_url | string | 下载链接（已含 Passkey，付费未购买时为空） |
| price | float64 | 价格（0 为免费） |
| is_purchased | bool | 当前用户是否已购买 |
| promotion | object | 促销信息（可选） |
| promotion.type | int | 促销类型（1=普通, 2=免费, 3=2X, 4=2X免费, 5=50%, 6=2X50%, 7=30%） |
| promotion.time_type | int | 时间类型（0=跟随全站, 1=永久, 2=到期时间） |
| promotion.is_active | bool | 是否激活 |
| promotion.is_global | bool | 是否使用全站促销 |
| promotion.until | string | 到期时间（可选，ISO 8601 格式，如 `2025-01-31T00:00:00+0800`） |
| promotion.up_multiplier | float64 | 上传倍数 |
| promotion.down_multiplier | float64 | 下载倍数 |

**注意：** 对于付费种子（`price > 0`），如果用户未购买：
- `info_hash` 字段为空
- `files` 字段为空
- `download_url` 字段为空
- `is_purchased` 为 `false`

#### 获取种子评论

```
GET /api/v1/torrents/:id/comments
```

获取指定种子的评论列表。

**参数：**

| 参数 | 类型 | 位置 | 默认值 | 说明 |
|------|------|------|--------|------|
| id | string | path | - | 种子 ID（数字）或 UUID |
| page | int | query | 1 | 页码 |
| page_size | int | query | 20 | 每页数量（最大 100） |

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "comments": [
      {
        "id": 1,
        "content": "感谢分享！",
        "user_id": 2,
        "username": "commenter",
        "avatar": "https://example.com/avatar.jpg",
        "created_at": "2024-12-01T12:00:00Z"
      }
    ],
    "total": 10,
    "page": 1,
    "page_size": 20,
    "total_pages": 1
  }
}
```

**字段说明：**

| 字段 | 类型 | 说明 |
|------|------|------|
| comments | array | 评论列表 |
| comments[].id | uint | 评论 ID |
| comments[].content | string | 评论内容 |
| comments[].user_id | uint | 评论者用户 ID |
| comments[].username | string | 评论者用户名 |
| comments[].avatar | string | 评论者头像 URL（可选） |
| comments[].created_at | string | 评论时间（ISO 8601 格式） |
| total | int64 | 总数量 |
| page | int | 当前页码 |
| page_size | int | 每页数量 |
| total_pages | int | 总页数 |

---

### 分类相关

#### 获取分类列表

```
GET /api/v1/categories
```

获取所有种子分类及其属性定义。属性信息用于上传种子时填写 `attributes` 字段。

**响应示例：**

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
            {"value": "1080p", "label": "1080p"},
            {"value": "720p", "label": "720p"}
          ]
        },
        {
          "name": "source",
          "label": "来源",
          "type": "select",
          "required": true,
          "options": [
            {"value": "bluray", "label": "Blu-ray"},
            {"value": "webdl", "label": "WEB-DL"},
            {"value": "hdtv", "label": "HDTV"}
          ]
        },
        {
          "name": "genre",
          "label": "类型",
          "type": "multi-select",
          "required": false,
          "options": [
            {"value": "action", "label": "动作"},
            {"value": "comedy", "label": "喜剧"},
            {"value": "drama", "label": "剧情"}
          ]
        }
      ]
    },
    {
      "id": 2,
      "name": "tv",
      "label": "剧集",
      "icon": "tv",
      "attributes": [...]
    }
  ]
}
```

**字段说明：**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | uint | 分类 ID |
| name | string | 分类名称（用于 API 传参） |
| label | string | 分类显示名称 |
| icon | string | 分类图标名称 |
| attributes | array | 属性定义列表 |
| attributes[].name | string | 属性名称（用于 API 传参） |
| attributes[].label | string | 属性显示名称 |
| attributes[].type | string | 属性类型（见下表） |
| attributes[].required | bool | 是否必填 |
| attributes[].options | array | 选项列表（仅 select/multi-select 类型） |
| attributes[].options[].value | string | 选项值 |
| attributes[].options[].label | string | 选项显示名称 |

**属性类型说明：**

| Type | 说明 |
|------|------|
| select | 单选，从 options 中选择一个值 |
| multi-select | 多选，从 options 中选择多个值（数组） |
| text | 文本输入 |

---

### 搜索

#### 搜索种子

```
GET /api/v1/search
```

根据关键词搜索种子。参数与 `/api/v1/torrents` 相同。

---

## 错误码说明

| Code | 说明 |
|------|------|
| 0 | 成功 |
| 1001 | 用户不存在 |
| 2001 | 获取种子列表失败 |
| 2002 | 种子不存在 |
| 2003 | 种子未通过审核 |
| 2004 | 获取评论失败 |
| 3001 | 获取分类失败 |
| 4001 | 上传参数错误 |
| 4002 | 图片数量超过限制 |
| 4003 | 上传失败 |
| 4004 | 种子已存在 |

---

## 使用示例

### cURL

```bash
# 获取当前用户信息
curl -H "Authorization: Bearer YOUR_PASSKEY" \
  https://example.com/api/v1/profile

# 搜索种子
curl -H "Authorization: Bearer YOUR_PASSKEY" \
  "https://example.com/api/v1/torrents?keyword=movie&page=1&page_size=10"

# 获取种子详情（使用 UUID）
curl -H "Authorization: Bearer YOUR_PASSKEY" \
  https://example.com/api/v1/torrents/550e8400-e29b-41d4-a716-446655440000

# 获取种子详情（使用数字 ID）
curl -H "Authorization: Bearer YOUR_PASSKEY" \
  https://example.com/api/v1/torrents/123
```

### Python

```python
import requests

PASSKEY = "your_passkey"
BASE_URL = "https://example.com/api/v1"

headers = {"Authorization": f"Bearer {PASSKEY}"}

# 获取当前用户信息
response = requests.get(f"{BASE_URL}/profile", headers=headers)
print(response.json())

# 搜索种子
response = requests.get(
    f"{BASE_URL}/torrents",
    headers=headers,
    params={"keyword": "movie", "page": 1, "page_size": 10}
)
print(response.json())
```

### JavaScript

```javascript
const PASSKEY = 'your_passkey';
const BASE_URL = 'https://example.com/api/v1';

const headers = {
  'Authorization': `Bearer ${PASSKEY}`
};

// 获取当前用户信息
fetch(`${BASE_URL}/profile`, { headers })
  .then(res => res.json())
  .then(data => console.log(data));

// 搜索种子
fetch(`${BASE_URL}/torrents?keyword=movie&page=1&page_size=10`, { headers })
  .then(res => res.json())
  .then(data => console.log(data));
```

---

## 注意事项

1. **请求频率限制**：请合理控制请求频率，避免对服务器造成过大压力
2. **Passkey 安全**：请妥善保管您的 Passkey，不要泄露给他人
3. **匿名种子**：对于匿名发布的种子，`uploader` 字段会显示为「匿名」，`uploader_id` 为 0
4. **下载链接**：种子详情中的 `download_url` 已包含您的 Passkey，可直接用于下载
5. **图片 URL 处理**：
   - 所有图片 URL（头像、种子封面、勋章图片等）如果配置了 WebP Server，会自动转换为 WebP Server 地址
   - 勋章图片（`image_large`、`image_small`）如果是相对路径，会自动加上站点地址（`site.base_url`）转换为完整 URL
   - 图片 URL 格式：`https://webp-server.example.com/uploads/images/xxx.jpg` 或 `https://site.example.com/uploads/images/xxx.jpg`
6. **角色字段**：
   - `role`：角色代码（`user`/`admin`）
   - `role_text`：角色文本（`用户`/`管理员`）
7. **促销信息**：
   - 所有种子接口（列表、详情、搜索）都包含 `promotion` 字段
   - 促销优先级：全站促销 > 种子独立促销
   - 促销类型：1=普通, 2=免费, 3=2X, 4=2X免费, 5=50%, 6=2X50%, 7=30%
   - 时间类型：0=跟随全站, 1=永久, 2=到期时间
   - 全站促销也会显示到期时间（`until` 字段）
   - 上传/下载倍数总是返回，即使促销未激活
   - 到期时间格式：ISO 8601（如 `2025-01-31T00:00:00+0800`）
