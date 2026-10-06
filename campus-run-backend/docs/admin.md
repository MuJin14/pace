# 管理后台与找回密码

## 为什么是这样设计的

App **没有邮箱字段、也没有短信服务**，用户忘记密码后毫无自救途径。

可选方案对比：

| 方案 | 代价 | 结论 |
|---|---|---|
| 短信验证码 | 腾讯云短信要实名 + 短信模板备案 + 按条付费 | 对当前规模不划算 |
| 邮箱验证码 | 需要新增邮箱字段、接 SMTP，还可能进垃圾邮件 | 成本更高 |
| **管理员协助** | 需要一个后台 + 给少量账号开权限 | **采用** |

传播范围小的时候，管理员方案是成本最低且**立刻可用**的。

---

## 一、给账号开管理员

管理员判定看 `user.role`：`0` = 普通用户，`1` = 管理员。

```sql
-- 在服务器上执行
cd /home/ubuntu/campus-run-backend
DBP="$(grep '^DB_PASSWORD=' .env | cut -d= -f2-)"
sudo docker exec campus-run-mysql mysql -uroot -p"$DBP" \
  --default-character-set=utf8mb4 campus_run -e "
UPDATE user SET role = 1 WHERE phone IN ('手机号1','手机号2');
SELECT id, nickname, phone, role FROM user ORDER BY id;"
```

**当前管理员**（2026-10-05 设置）：

| userId | 昵称 | 手机号 |
|---|---|---|
| 1 | Mujin | 13800138000 |
| 3 | 沐瑾 | 17530554523 |
| 4 | 沐瑾B | 19561723890 |

> ⚠️ 改完角色后用户**不需要重新登录**：权限以数据库为准
> （`JwtAuthenticationFilter.resolveCurrentRole`），带 60 秒 TTL 缓存。
> 这是为「撤销管理员要立即生效」做的，见下方「安全设计」。

---

## 二、日常操作

### 用户忘记密码，来求助时

**方式 A：他在 App 里自助申请（推荐）**

1. 用户在登录页点「忘记密码？」→ 填手机号 → 提交
2. 你打开 App →「我的 → 管理后台 → 找回密码申请」
3. 点「重置密码」→ **屏幕会显示一次性临时密码**
4. 把临时密码**当面或私聊**转达本人
5. 他登录后去「我的 → 修改密码」改成自己的密码

**方式 B：直接帮他重置（他没能力提交申请时）**

「管理后台 → 用户查询」→ 搜手机号/昵称/专属 ID → 「重置密码」。

### 用户查询

支持按**手机号 / 昵称 / 专属 ID** 模糊搜索，留空则按注册时间倒序列出。

---

## 三、安全设计（都是刻意为之，改代码前请先读）

### 1. 权限拒绝必须是 HTTP 403，不是 200 + body code=403

`SecurityExceptionHandler` 上的 `@ResponseStatus(HttpStatus.FORBIDDEN)` **不能删**。
删掉后返回 HTTP 200（只有 body 里是 403），前端 `catch` 不到，会把越权渲染成空态。

> 这是真实修过的 bug，回归由 `AdminAccessControlTest`（8 个用例）固化。

### 2. 权限以**数据库**为准，不是 JWT claim

`JwtAuthenticationFilter.resolveCurrentRole()` 每次请求按 userId 查角色，带 60 秒缓存。

**为什么不能只用 claim**：角色在签发 token 那一刻就固化了，
于是把某人从管理员改回普通用户后，他手上那枚 token 在有效期内（最长 2 小时）
**仍然是管理员** —— 撤销权限本该立即生效。修复由 `RoleChangeTakesEffectTest`（2 个用例）固化。

⚠️ 缓存是**进程内**的。多实例部署时各实例独立，生效时间可能相差一个 TTL。
上多实例时应换成 Redis（与 `RateLimiter` 的局限相同）。

### 3. 管理员**不能**重置自己的密码

`AdminUserServiceImpl.resetPassword` / `handleRequest` 都会拒绝 `target == operator`。

否则等于给管理员账号开一个「无需旧密码改自己密码」的**后门**：
access token 一泄漏，攻击者就能直接夺号。管理员改自己密码请用「修改密码」。

### 4. 重置会作废该用户全部 refresh token

写 `user.token_invalid_before = now()`。不写的话，
用户此前泄漏或残留在旧设备上的 refresh token（**30 天有效**）
仍能换到新 access token —— 重置就形同虚设。

### 5. 未注册手机号提交申请也返回成功

`createResetRequest` 对查不到的手机号**静默成功**。
否则这个免登录接口就成了「哪些手机号注册过本 App」的批量枚举器。

### 6. 同一用户只保留一条待处理申请

避免管理后台被同一个人连点几次刷屏。

### 7. 提交申请的放行是 `POST` + 精确路径

```java
.requestMatchers(HttpMethod.POST, "/api/v1/password-reset-requests").permitAll()
```

**不要**改成 `/api/v1/password-reset-requests/**` —— 那会让 `/mine`
（查看自己申请状态）也变成匿名可访问。回归测试：`myRequestStatusStillRequiresLogin`。

### 8. 用户列表不含任何密码字段

`AdminUserItem` 里没有密码相关字段，`AdminUserServiceTest` 用**反射**兜底，
防止将来有人「顺手」加上。

---

### 9. 管理后台路由本身也要拦，不能只藏菜单入口

前端菜单入口只在 `profile_page.dart` 用 `if (user.isAdmin)` 隐藏，
但 **`/admin` 路由是公开可达的**。少了守卫这一层：

- 普通用户深链或手输 `/admin` 能**看见后台界面本身**（有哪些页签、能干什么），
  只是每个请求都 403 —— 一屏错误，既像 App 坏了，也暴露了不该暴露的结构；
- 只藏菜单在客户端是**不可靠**的（何况前端代码是公开的）。

修法：`resolveRedirect` 里对 `/admin` 及其子路径做角色判定，
非管理员（含**拿不到角色信息**的情况）一律送回 `/home`。

> **安全默认**：角色字段缺失时按「非管理员」处理，而不是放行。
> 回归由 `router_guard_test.dart` 新增的 5 个用例固化。

⚠️ 仍然要强调：这只是**体验与信息暴露**层面的防线。
真正的安全边界是服务端每个接口的 `@PreAuthorize("hasRole('ADMIN')")`。

## 四、接口清单

| 方法 | 路径 | 权限 |
|---|---|---|
| `GET` | `/api/v1/admin/users?keyword=&page=&size=` | ADMIN |
| `POST` | `/api/v1/admin/users/{userId}/reset-password` | ADMIN |
| `GET` | `/api/v1/admin/password-reset-requests?status=` | ADMIN |
| `POST` | `/api/v1/admin/password-reset-requests/{id}/resolve` | ADMIN |
| `POST` | `/api/v1/admin/password-reset-requests/{id}/reject` | ADMIN |
| `POST` | `/api/v1/password-reset-requests?phone=&note=` | **免登录** |
| `GET` | `/api/v1/password-reset-requests/mine` | 需登录 |

`status`：`0` = 待处理，`1` = 已重置，`2` = 已拒绝。

---

## 五、前端入口

| 位置 | 说明 |
|---|---|
| 登录页密码框下方「忘记密码？」 | 进 `/forgot-password`，未登录也能进 |
| 「我的 → 忘记密码怎么办」 | 同上 |
| 「我的 → 管理后台」 | **仅管理员可见**，进 `/admin` |

管理后台两个页签：

- **找回密码申请** ——「有人等我」的队列，默认只看待处理
- **用户查询** ——「我要找某人」

刻意分开：混在一页会让「还有几个人在等」被搜索框淹没。

> 藏入口只是 UI 便利，**不是安全边界**。真正的校验是服务端的 `@PreAuthorize`。
