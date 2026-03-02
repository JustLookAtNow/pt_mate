# Gazelle JSON API Documentation

## 1. Introduction
The Gazelle JSON API provides an easily parseable interface for interacting with the site. It is a standard feature in public Gazelle installations and works out of the box. All API requests return data in JSON format, facilitating development for third-party applications and scripts.

## 2. Security and Authentication
### Authentication
To use the API, you must be authenticated.
*   **Method**: Send a `POST` request to `http://<your-site>.cd/login.php`.
*   **Parameters**: `username` and `password`.
*   **Session Management**: Store the session cookie returned after a successful login and include it in the headers of all subsequent API requests.

### Usage Policy
Using the API bestows a level of trust. Abuse or malicious use is a bannable offense. 
*   **Rate Limiting**: Refrain from making more than **five (5) requests every ten (10) seconds**.

## 3. General Outline
All request URLs follow this structure:  
`ajax.php?action=<ACTION>`

### Standard Response Format
A successful request returns:
```json
{
  "status" : "success",
  "response" : {
    // Response data
  }
}
```
If a request is invalid or fails, the `status` will be `failure` and the `response` may be undefined.

---

## 4. API Actions

### Index
Returns basic information about the current user.
*   **URL**: `ajax.php?action=index`
*   **Arguments**: None
*   **Response Structure**:
```json
{
    "username": "用户名",
    "id": 469,
    "authkey": "认证密钥",
    "passkey": "Passkey",
    "notifications": {
        "messages": 0, // 未读消息数
        "notifications": 9000, // 新通知数
        "newAnnouncement": false, // 是否有新公告
        "newBlog": false // 是否有新博客
    },
    "userstats": {
        "uploaded": 585564424629, // 上传量 (Bytes)
        "downloaded": 177461229738, // 下载量 (Bytes)
        "ratio": 3.29, // 分享率
        "requiredratio": 0.6, // 要求分享率
        "class": "VIP" // 用户等级
    }
}
```

### User Profile
Detailed statistics and profile info for a specific user.
*   **URL**: `ajax.php?action=user`
*   **Arguments**: 
    *   `id`: The ID of the user to display.
*   **Response Structure & Field Descriptions**:
```json
{
    "username": "用户名",
    "avatar": "头像链接",
    "isFriend": false, // 是否为好友
    "profileText": "个人简介内容",
    "stats": {
        "joinedDate": "加入时间",
        "lastAccess": "最后在线时间",
        "uploaded": 585564424629,
        "downloaded": 177461229738,
        "ratio": 3.3,
        "requiredRatio": 0.6
    },
    "ranks": {
        "uploaded": 98, // 上传排名百分比
        "downloaded": 95,
        "uploads": 85, // 发布数排名
        "requests": 0, // 求种数排名
        "bounty": 79, // 打赏赏金排名
        "posts": 98, // 论坛回帖排名
        "artists": 0, // 艺术家贡献排名
        "overall": 85 // 综合排名
    },
    "personal": {
        "class": "用户等级名称",
        "paranoia": 0, // 隐私设置等级 (0=公开)
        "paranoiaText": "隐私描述",
        "donor": true, // 是否为捐赠者
        "warned": false, // 是否被警告
        "enabled": true, // 账号是否正常启用
        "passkey": "redacted"
    },
    "community": {
        "posts": 863, // 论坛回帖数
        "torrentComments": 13, // 种子评论数
        "collagesStarted": 0, // 创建的多媒体包数
        "collagesContrib": 0, // 参与的多媒体包数
        "requestsFilled": 0, // 发布的求种完成数
        "requestsVoted": 13, // 参与投票的求种数
        "perfectFlacs": 2, // 发布的 Perfect FLAC 数
        "uploaded": 29, // 上传种子总数
        "groups": 14, // 涉及的种子组数
        "seeding": 309, // 正在做种数
        "leeching": 0, // 正在下载数
        "snatched": 678, // 已完种数
        "invited": 7 // 邀请人数
    }
}
```

### Messages (Inbox/Sentbox)
*   **URL**: `ajax.php?action=inbox`
*   **Arguments**:
    *   `page`: Page number (default: 1).
    *   `type`: `inbox` or `sentbox` (default: `inbox`).
    *   `sort`: `unread` to prioritize unread messages.
    *   `search`: Filter by string.
    *   `searchtype`: `subject`, `message`, or `user`.
*   **Response**: Contains an array of messages with `convId`, `subject`, `unread`, `senderId`, `date`, etc.

### Conversation
View a specific message thread.
*   **URL**: `ajax.php?action=inbox&type=viewconv`
*   **Arguments**:
    *   `id`: Message ID.
*   **Response**: 
```json
{
  "convId": 123,
  "subject": "Subject",
  "messages": [
    {
      "messageId": 456,
      "senderName": "Sender",
      "sentDate": "2023-01-01 12:00:00",
      "bbBody": "BBCode content",
      "body": "HTML content"
    }
  ]
}
```

### Top 10
Returns the top-rated items.
*   **URL**: `ajax.php?action=top10`
*   **Arguments**:
    *   `type`: `torrents`, `tags`, or `users` (default: `torrents`).
    *   `limit`: `10`, `100`, or `250` (default: `10`).
*   **Response**: Contains top items categorized by timeframes (day, week, overall) with fields like `torrentId`, `groupName`, `artist`, `snatched`, `seeders`, `leechers`, `data` (total transfer).

### User Search
*   **URL**: `ajax.php?action=usersearch`
*   **Arguments**:
    *   `search`: The search term.
    *   `page`: Page number.
*   **Response**: Lists matching users with `userId`, `username`, `donor`, `class`, etc.

### Requests Search
*   **URL**: `ajax.php?action=requests`
*   **Arguments**: `search`, `page`, `tag`, `tags_type`, `show_filled`, etc.
*   **Response**: `results` contains `requestId`, `title`, `bounty`, `artists` list, `isFilled`, etc.

### Torrent Search (Browse)
*   **URL**: `ajax.php?action=browse`
*   **Arguments**: `searchstr`, `page`, and advanced filters (`taglist`, `order_by`, `freetorrent`, `media`, `format`, `encoding`, etc.).
*   **Response Structure**: Returns a list of `Groups`. Each group contains a `torrents` array with `torrentId`, `size`, `seeders`, `snatches`, `isFreeleech`, etc.

### Bookmarks
*   **URL**: `ajax.php?action=bookmarks`
*   **Arguments**:
    *   `type`: `torrents` or `artists` (default: `torrents`).
*   **Response**: List of bookmarked torrents or artists.

### Subscriptions
*   **URL**: `ajax.php?action=subscriptions`
*   **Arguments**:
    *   `showunread`: `1` for only unread, `0` for all (default: `1`).
*   **Response**: Contains `threadId`, `threadTitle`, `lastPostId`, `new` (boolean).

### Forums
*   **Category View**: `ajax.php?action=forum&type=main` - Category list.
*   **Forum View**: `ajax.php?action=forum&type=viewforum&forumid=<ID>` - Thread list.
*   **Thread View**: `ajax.php?action=forum&type=viewthread&threadid=<ID>` - Post list with `poll` and `posts` details.

### Artist
Returns artist details, tags, statistics, and torrent groups.
*   **URL**: `ajax.php?action=artist`
*   **Arguments**: `id`, `artistname`.
*   **Response**: Includes `statistics` (torrent counts), `torrentgroup` (works), `similarArtists`.

### Torrent
Details for a specific torrent.
*   **URL**: `ajax.php?action=torrent`
*   **Arguments**: `id` (Torrent ID) or `hash`.
*   **Response**:
```json
{
  "group": {
    "id": 123,
    "name": "Album Name",
    "musicInfo": { "artists": [...] }
  },
  "torrent": {
    "id": 456,
    "infoHash": "...",
    "fileList": "file1.flac{1234567}||file2.flac{234567}",
    "filePath": "Directory Name",
    "size": 12345678,
    "seeders": 10,
    "leechers": 2
  }
}
```

### Torrent Group
Details for a group of torrents.
*   **URL**: `ajax.php?action=torrentgroup`
*   **Arguments**: `id` (Group ID).
*   **Response**: Similar to `artist`'s group list, containing all releases (formats/encodings) in that group.

### Request
Details for a specific request.
*   **URL**: `ajax.php?action=request`
*   **Arguments**: `id`.
*   **Response**: Includes `totalBounty`, `topContributors`, `comments`.

### Collages
*   **URL**: `ajax.php?action=collage`
*   **Arguments**: `id`.
*   **Response**: Collage metadata (name, description, creator).

### Notifications
*   **URL**: `ajax.php?action=notifications`
*   **Arguments**: `page`.
*   **Response**: List of new torrents based on user notification filters.

### Similar Artists
*   **URL**: `ajax.php?action=similar_artists`
*   **Arguments**: `id`, `limit`.
*   **Response**: List of artists with `id`, `name`, `score`.

### Announcements
Returns site news and blog posts.
*   **URL**: `ajax.php?action=announcements`
*   **Arguments**: None.
*   **Response**:
```json
{
  "announcements": [
    {
      "newsId": 1,
      "title": "Title",
      "body": "Body text",
      "newsTime": "2023-01-01 12:00:00"
    }
  ],
  "blogPosts": [...]
}
```
