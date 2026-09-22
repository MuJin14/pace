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
