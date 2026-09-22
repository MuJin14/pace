# 校园跑（Campus Run）后端 API 文档 — 第一阶段

统一返回体 `Result<T>`：

```json
{ "code": 0, "message": "成功", "data": { } }
```

- 业务异常返回 HTTP 200 + `Result` 业务错误码
- JWT 缺失/无效返回 HTTP 401 + `Result(401, "未认证或登录已过期")`

## 错误码

| code | 含义 |
|------|------|
| 0    | 成功 |
| 400  | 参数错误 |
| 401  | 未认证或登录已过期 |
| 1001 | 手机号已注册 |
| 1002 | 用户不存在 |
| 1003 | 密码错误 |
| 2001 | 运动记录不存在 |
| 2002 | 无权访问该运动记录 |
| 500  | 服务器内部错误 |

## 1. 注册

```
POST /api/v1/auth/register
```

请求体：

```json
{ "phone": "13800138000", "password": "secret123", "nickname": "小明" }
```

成功响应（HTTP 200）：

```json
{
  "code": 0,
  "message": "成功",
  "data": {
    "token": "eyJhbGciOiJIUzI1NiJ9...",
    "userId": 1,
    "uniqueId": "CR-00001234",
    "nickname": "小明",
    "phone": "13800138000",
    "avatarUrl": null
  }
}
```

## 2. 登录

```
POST /api/v1/auth/login
```

请求体：

```json
{ "phone": "13800138000", "password": "secret123" }
```

成功响应结构与注册一致。

## 3. 当前用户信息（受保护）

```
GET /api/v1/user/me
Authorization: Bearer <token>
```

成功响应（HTTP 200）：

```json
{
  "code": 0,
  "message": "成功",
  "data": {
    "userId": 1,
    "uniqueId": "CR-00001234",
    "nickname": "小明",
    "phone": "13800138000",
    "avatarUrl": null,
    "createdAt": "2026-09-22 12:00:00"
  }
}
```

## 鉴权白名单

`/api/v1/auth/**`、`/error` 免鉴权；其余接口需携带 `Authorization: Bearer <token>`。

---

# 第二阶段 — 运动记录（Activity）

所有接口均需携带 `Authorization: Bearer <token>`。距离、时长、平均速度由服务端根据轨迹点计算，客户端仅上报原始轨迹。

## 4. 上传运动记录

```
POST /api/v1/activity
```

请求体：

```json
{
  "type": 1,
  "startTime": 1726992000000,
  "endTime": 1726995600000,
  "calories": 320.5,
  "track": [
    { "latitude": 39.9042, "longitude": 116.4074, "timestamp": 1726992000000, "accuracy": 12.5 },
    { "latitude": 39.9050, "longitude": 116.4080, "timestamp": 1726992100000, "accuracy": 10.0 }
  ]
}
```

- `type`：1=跑步 2=骑行；`startTime`/`endTime`：毫秒时间戳。
- 轨迹点数量：跑步最多 5000，骑行最多 15000。

成功响应：

```json
{
  "code": 0, "message": "成功",
  "data": {
    "activityId": 1001, "type": 1,
    "distanceMeters": 5230, "durationSeconds": 3600,
    "avgSpeed": 5.23, "avgPace": 688, "calories": 320.5,
    "startTime": "2026-09-22 20:00:00", "endTime": "2026-09-22 21:00:00"
  }
}
```

## 5. 分页查询历史

```
GET /api/v1/activity?page=1&size=20&type=1
```

- `type` 可选；`page` 默认 1；`size` 默认 20，上限 100。
- 按 `start_time` 倒序，仅返回当前用户自己的记录。

成功响应：

```json
{
  "code": 0, "message": "成功",
  "data": {
    "total": 42, "page": 1, "size": 20,
    "list": [
      { "activityId": 1001, "type": 1, "distanceMeters": 5230, "durationSeconds": 3600,
        "avgSpeed": 5.23, "avgPace": 688, "startTime": "2026-09-22 20:00:00",
        "endTime": "2026-09-22 21:00:00", "createdAt": "2026-09-22 21:00:01" }
    ]
  }
}
```

## 6. 查询详情

```
GET /api/v1/activity/{id}
```

- 非本人记录返回 `2002`；记录不存在返回 `2001`。

成功响应（列表字段基础上多 `calories` 与 `track`）：

```json
{
  "code": 0, "message": "成功",
  "data": {
    "activityId": 1001, "type": 1, "distanceMeters": 5230, "durationSeconds": 3600,
    "avgSpeed": 5.23, "avgPace": 688, "calories": 320.5,
    "startTime": "2026-09-22 20:00:00", "endTime": "2026-09-22 21:00:00",
    "createdAt": "2026-09-22 21:00:01",
    "track": [
      { "latitude": 39.9042, "longitude": 116.4074, "timestamp": 1726992000000, "accuracy": 12.5 }
    ]
  }
}
```

---

# 第三阶段 — 排行榜（Leaderboard）

以下接口均需携带 `Authorization: Bearer <token>`。`scope` 与 `type` 为必填参数；`period` 缺省时服务端解析为当前周期（daily=今天、weekly=本周一、monthly=本月；rolling30d 恒为 `CURRENT`）。非法 `scope` / `type` / `period` 返回 `400`。

## 7. 榜单分页查询

```
GET /api/v1/leaderboard
```

请求参数：

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| scope | string | 是 | - | 榜单维度：`daily` / `weekly` / `rolling30d` / `monthly` |
| type | int | 是 | - | 运动类型：`1`=跑步 `2`=骑行 |
| period | string | 否 | 当前周期 | 周期标识；`daily`/`weekly` 为 `yyyy-MM-dd`，`monthly` 为 `yyyy-MM`；`rolling30d` 忽略此参数 |
| page | int | 否 | 1 | 页码 |
| size | int | 否 | 20 | 每页条数，上限 100 |

成功响应 `data` 字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| total | long | 榜单总人数 |
| page | long | 当前页码 |
| size | long | 每页条数 |
| list | array | 榜单条目，按 `distanceMeters` 降序排列 |

`list` 条目字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| rank | long | 名次（从 1 开始） |
| userId | long | 用户 ID |
| uniqueId | string | 专属 ID |
| nickname | string | 昵称 |
| avatarUrl | string | 头像地址，可为 null |
| distanceMeters | int | 累计距离（米） |

示例请求：

```
GET /api/v1/leaderboard?scope=daily&period=2026-09-22&type=1&page=1&size=20
Authorization: Bearer <token>
```

示例响应：

```json
{
  "code": 0, "message": "成功",
  "data": {
    "total": 128, "page": 1, "size": 20,
    "list": [
      { "rank": 1, "userId": 3, "uniqueId": "CR-00000003", "nickname": "小明",
        "avatarUrl": null, "distanceMeters": 15230 },
      { "rank": 2, "userId": 9, "uniqueId": "CR-00000009", "nickname": "阿强",
        "avatarUrl": null, "distanceMeters": 12100 }
    ]
  }
}
```

## 8. 个人排名

```
GET /api/v1/leaderboard/my-rank
```

请求参数：

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| scope | string | 是 | - | 榜单维度：`daily` / `weekly` / `rolling30d` / `monthly` |
| type | int | 是 | - | 运动类型：`1`=跑步 `2`=骑行 |
| period | string | 否 | 当前周期 | 周期标识，含义同榜单查询 |

成功响应 `data` 字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| rank | long | 当前用户名次（从 1 开始）；不在榜上时为 null |
| distanceMeters | long | 当前用户累计距离（米）；不在榜上时为 0 |
| total | long | 榜单总人数 |

示例请求：

```
GET /api/v1/leaderboard/my-rank?scope=daily&period=2026-09-22&type=1
Authorization: Bearer <token>
```

示例响应：

```json
{
  "code": 0, "message": "成功",
  "data": { "rank": 7, "distanceMeters": 5200, "total": 128 }
}
```
