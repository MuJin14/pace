-- ════════════════════════════════════════════════════════════════════════
-- 005_single_device_login.sql
--
-- 单设备登录（令牌版本）。
--
-- ## 为什么需要
--
-- 在此之前凭据是**纯 JWT**：服务端不留任何记录，于是同一个账号可以在
-- 任意多台设备上同时登录，并牵连出一串问题：
--
--   1. WebSocket 会话表是 `ConcurrentHashMap<Long, WebSocketSession>`，
--      以 userId 为 key —— 第二台设备登录会**顶掉**第一台的连接，
--      第一台从此收不到任何实时消息，且毫无提示；
--   2. 改密码不会让旧设备下线（refresh token 最长还能用 30 天）；
--   3. 已读回执是全局的：A 设备读了消息，B 设备的红点也没了，
--      于是 B **永远不会收到通知**；
--   4. 手机丢了没有「退出所有设备」的手段；
--   5. 两台设备同时记录运动，会产生两条重复轨迹。
--
-- ## 做法
--
-- 给用户加一个自增的 `token_version`，签发 JWT 时写进 claim，
-- 每次校验时与数据库比对，不一致即判定令牌已失效。
--
-- 加版本号而不是维护一张会话表：改动小、无需清理过期行，
-- 且「让某个用户的所有旧令牌立即失效」就是一句 `version + 1`。
--
-- 递增时机：
--   · 在**另一台设备**上登录（同设备重复登录不递增，否则自己把自己踢下线）；
--   · 修改密码；
--   · 管理员重置密码；
--   · 注销账号（顺带，虽然那时用户已经不存在）。
--
-- ⚠️ 幂等：重复执行不会报错。
-- ════════════════════════════════════════════════════════════════════════

SET @col_exists := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'user'
    AND COLUMN_NAME = 'token_version'
);

SET @sql := IF(@col_exists = 0,
  'ALTER TABLE `user` ADD COLUMN `token_version` INT NOT NULL DEFAULT 0 COMMENT ''令牌版本：递增即让该用户所有已签发令牌失效（单设备登录）'' AFTER `role`',
  'SELECT ''token_version already exists'' AS msg');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 已有用户全部从 0 开始：他们手上现有的令牌 version claim 缺失，
-- 校验时按 0 处理，因此**不会**被这次迁移强制下线。

-- 记录最近一次登录的设备标识。
--
-- ## 为什么需要它（否则会「自己把自己踢下线」）
--
-- 单设备登录的规则是「在**另一台**设备上登录时递增版本」。
-- 没有设备标识的话，同一台手机每次登录都会递增，于是：
--   · 用户杀掉 App 重进 → 被判定为「已在其他设备登录」；
--   · 而这正是最正常的操作。
--
-- 客户端上报一个本地持久化的随机串（不是硬件 ID，卸载前不变即可），
-- 服务端存下最近一次的；相同就视为同一台设备，不递增。
SET @dev_exists := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'user'
    AND COLUMN_NAME = 'device_id'
);

SET @sql2 := IF(@dev_exists = 0,
  'ALTER TABLE `user` ADD COLUMN `device_id` VARCHAR(64) NULL COMMENT ''最近一次登录的设备标识（用于判断是否换设备）'' AFTER `token_version`',
  'SELECT ''device_id already exists'' AS msg');
PREPARE stmt2 FROM @sql2;
EXECUTE stmt2;
DEALLOCATE PREPARE stmt2;

SELECT COUNT(*) AS users_at_version_0 FROM `user` WHERE `token_version` = 0;
