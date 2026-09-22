# 管理员初始化

系统通过 `user.role` 字段区分角色：`0` = 普通用户，`1` = 管理员。

围栏管理接口（`/api/v1/admin/fences/**`）仅管理员可访问，由 Spring Security 方法级鉴权
`@PreAuthorize("hasRole('ADMIN')")` 控制。JWT 中携带 `role` 声明，登录时签发。

## 将某个用户设为管理员

先注册一个普通账号（或在已有数据中定位用户），然后执行：

```sql
UPDATE `user` SET `role` = 1 WHERE `phone` = '13800138000';
```

## 注意事项

1. **角色通过 JWT claim 传播**：修改数据库中的 `role` 后，该用户需要**重新登录**才能获得
   新角色（旧 token 仍按签发时的角色生效，直至过期）。
2. **撤销管理员**同理：`UPDATE user SET role = 0 WHERE ...` 后，用户需等待旧 token 过期或重新登录。
3. 若需要「实时」角色变更（不等待 token 过期），可改为每次请求查库校验，本阶段未采用该方案。

## 预置管理员（可选）

若希望系统初始化时自动创建一个管理员账号，可在 `docs/schema.sql` 末尾追加一条 INSERT：

```sql
-- 预置管理员（密码需为 BCrypt 密文，请勿使用明文）
INSERT INTO `user` (`unique_id`, `phone`, `password_hash`, `nickname`, `role`)
VALUES ('CR-00000001', '13800000000', '<BCrypt-HASH>', '管理员', 1);
```

> 生产环境请使用安全的初始密码并在首次登录后修改。
