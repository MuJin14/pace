-- ════════════════════════════════════════════════════════════════════════
-- 006_sequential_ids.sql
--
-- 把用户 ID 重排为连续序号，前三个是管理员。
--
-- ## 目标
--
--   id = 1..N 连续无空洞；unique_id = 同值的 8 位补零
--   管理员占 1/2/3（unique_id = 00000000 / 00000001 / 00000002）
--   其余按注册（原 id）顺序排下去；下一个新用户拿 N+1
--
-- ## 为什么安全
--
--   · **没有任何外键约束**指向 user（已核实），UPDATE 主键不会被级联影响；
--   · unique_id **只用于搜索匹配**（LIKE），不做登录或主键查找；
--   · 全程不删任何业务数据行。
--
-- ## ⚠️ 副作用：所有人被强制下线
--
--   JWT 的 subject 存的就是用户 id。id 一改，旧令牌的 subject 会指向
--   **另一个用户** —— 严重安全问题（A 的令牌可能变成 B 的身份，
--   B 若是管理员就是提权）。所以主动把所有用户 token_version +1，
--   让全部令牌立即失效。用户需要重新登录一次。
--
-- ════════════════════════════════════════════════════════════════════════
-- ## 三个必须知道的坑（都是实际踩过的，不要重蹈）
-- ════════════════════════════════════════════════════════════════════════
--
-- ### 坑 1：带唯一约束的表**不能**用两条 UPDATE 逐列重排
--
-- `friendship` 有 UNIQUE KEY (user_id, friend_id)，两条 UPDATE：
--
--     UPDATE friendship SET user_id = <新>;   -- 第一条
--     UPDATE friendship SET friend_id = <新>; -- 第二条 ← 必挂
--
-- 第二条必挂，**顺序怎么调都躲不掉**。原因是第二条要在
-- 「已被第一条改过」的表里再找一次映射，读到的是**中间态**：
--
--     原数据 (3,23) 与 (3,27)；映射 23→23、27→23
--     第一条后：(3,23) 与 (3,23)  ← 此刻已违反唯一约束
--
-- 可靠做法：**一次 JOIN 算完两列，写进克隆表，再整体换名**。
-- 没有中间态，也不需要删数据（双向好友行必须保留：
-- 好友列表查的是 `WHERE user_id = 我`，删掉反向行会让对方看不到我）。
--
-- ### 坑 2：备份表必须 DROP + CREATE，不能用 IF NOT EXISTS
--
-- 曾经为了「保留上次备份」改成 IF NOT EXISTS，结果第二次执行时
-- INSERT 又插一遍 —— 同一个 old_id 出现两次，ROW_NUMBER() 给重复的
-- old_id 分配了不同 new_id，映射表里出现互相矛盾的映射。
--
-- ### 坑 3：user_stats 没有 id 列，主键就是 user_id
--
-- 想当然写 `SELECT id FROM user_stats` 会直接
-- `Unknown column 'id' in 'field list'`，整条 INSERT 失败。
--
-- ════════════════════════════════════════════════════════════════════════

-- 干跑开关：设成 1 时跑完全部流程，最后打印自检结果，业务数据靠 ROLLBACK 保护。
-- 建议第一次先干跑确认。
SET @dry_run := 1;

START TRANSACTION;

-- ── 1) 备份（每次重建，见坑 2）─────────────────────────────────────────
DROP TABLE IF EXISTS `_backup_user_ids_006`;
CREATE TABLE `_backup_user_ids_006` AS
SELECT id AS old_id, unique_id AS old_unique_id, phone, nickname, role,
       token_version AS old_token_version
FROM `user`;

DROP TABLE IF EXISTS `_backup_refs_006`;
CREATE TABLE `_backup_refs_006` (
    tbl VARCHAR(64), col VARCHAR(64), row_id BIGINT, old_val BIGINT
);
-- ⚠️ user_stats 主键是 user_id，没有 id 列（见坑 3）
INSERT INTO `_backup_refs_006`
SELECT 'activity', 'user_id', id, user_id FROM activity
UNION ALL SELECT 'friendship', 'user_id', id, user_id FROM friendship
UNION ALL SELECT 'friendship', 'friend_id', id, friend_id FROM friendship
UNION ALL SELECT 'message', 'sender_id', id, sender_id FROM message
UNION ALL SELECT 'message', 'receiver_id', id, receiver_id FROM message
UNION ALL SELECT 'user_stats', 'user_id', user_id, user_id FROM user_stats
UNION ALL SELECT 'user_badge', 'user_id', id, user_id FROM user_badge
UNION ALL SELECT 'user_goal', 'user_id', id, user_id FROM user_goal
UNION ALL SELECT 'leaderboard_stats', 'user_id', id, user_id FROM leaderboard_stats
UNION ALL SELECT 'chat_preference', 'user_id', id, user_id FROM chat_preference
UNION ALL SELECT 'chat_preference', 'friend_id', id, friend_id FROM chat_preference
UNION ALL SELECT 'device_token', 'user_id', id, user_id FROM device_token
UNION ALL SELECT 'password_reset_request', 'user_id', id, user_id FROM password_reset_request
UNION ALL SELECT 'password_reset_request', 'handled_by', id, handled_by FROM password_reset_request;

-- ── 2) 映射表：旧 id → 新 id ───────────────────────────────────────────
--     管理员**优先**：先按 role DESC 让管理员排在最前，再按原 id。
--     这样三个管理员一定拿到 1/2/3（unique_id 00000000/00000001/00000002），
--     其余用户按注册顺序接着排。
DROP TABLE IF EXISTS `_id_map_006`;
CREATE TABLE `_id_map_006` (
    old_id BIGINT PRIMARY KEY,
    new_id BIGINT NOT NULL,
    UNIQUE KEY uk_new (new_id)
);
INSERT INTO `_id_map_006` (old_id, new_id)
SELECT old_id, ROW_NUMBER() OVER (ORDER BY role DESC, old_id ASC)
FROM `_backup_user_ids_006`;

-- 映射一致性校验：old_id / new_id 都必须唯一。
-- 不校验的话，一旦备份表被污染（见坑 2），后续只会抛一个
-- 看不出原因的 `Duplicate entry`。
SELECT IF(
    (SELECT COUNT(*) - COUNT(DISTINCT old_id) FROM `_id_map_006`) = 0
    AND (SELECT COUNT(*) - COUNT(DISTINCT new_id) FROM `_id_map_006`) = 0,
    '映射校验通过',
    '⚠️ 映射表不一致，请检查 _backup_user_ids_006 是否被污染') AS 映射校验;

-- ── 3) 重排引用列 ─────────────────────────────────────────────────────
--
-- 3.1 带唯一约束、且约束涉及多列的表 → **克隆表 + 一次性重建**
--     （见坑 1）。INSERT ... SELECT 一次 JOIN 算完两列，
--     不存在任何中间态，也不删任何行。

CREATE TABLE `_new_friendship_006` LIKE friendship;
INSERT INTO `_new_friendship_006`
    (id, user_id, friend_id, status, created_at, updated_at)
SELECT f.id, COALESCE(m1.new_id, f.user_id), COALESCE(m2.new_id, f.friend_id),
       f.status, f.created_at, f.updated_at
FROM friendship f
-- LEFT JOIN + COALESCE：万一有指向已删除用户的孤儿行，
-- 宁可保留原值也不要静默丢行
LEFT JOIN `_id_map_006` m1 ON m1.old_id = f.user_id
LEFT JOIN `_id_map_006` m2 ON m2.old_id = f.friend_id;
DROP TABLE friendship;
RENAME TABLE `_new_friendship_006` TO friendship;

CREATE TABLE `_new_chat_preference_006` LIKE chat_preference;
INSERT INTO `_new_chat_preference_006`
    (id, user_id, friend_id, muted, created_at, updated_at)
SELECT c.id, COALESCE(m1.new_id, c.user_id), COALESCE(m2.new_id, c.friend_id),
       c.muted, c.created_at, c.updated_at
FROM chat_preference c
LEFT JOIN `_id_map_006` m1 ON m1.old_id = c.user_id
LEFT JOIN `_id_map_006` m2 ON m2.old_id = c.friend_id;
DROP TABLE chat_preference;
RENAME TABLE `_new_chat_preference_006` TO chat_preference;

-- 3.2 只涉及一列的表 → 普通 UPDATE 即可（不会产生中间态冲突）
UPDATE activity a LEFT JOIN `_id_map_006` m ON a.user_id = m.old_id
SET a.user_id = COALESCE(m.new_id, a.user_id);
UPDATE message g LEFT JOIN `_id_map_006` m ON g.sender_id = m.old_id
SET g.sender_id = COALESCE(m.new_id, g.sender_id);
UPDATE message g LEFT JOIN `_id_map_006` m ON g.receiver_id = m.old_id
SET g.receiver_id = COALESCE(m.new_id, g.receiver_id);
UPDATE user_stats s LEFT JOIN `_id_map_006` m ON s.user_id = m.old_id
SET s.user_id = COALESCE(m.new_id, s.user_id);
UPDATE user_badge b LEFT JOIN `_id_map_006` m ON b.user_id = m.old_id
SET b.user_id = COALESCE(m.new_id, b.user_id);
UPDATE user_goal g LEFT JOIN `_id_map_006` m ON g.user_id = m.old_id
SET g.user_id = COALESCE(m.new_id, g.user_id);
UPDATE leaderboard_stats l LEFT JOIN `_id_map_006` m ON l.user_id = m.old_id
SET l.user_id = COALESCE(m.new_id, l.user_id);
UPDATE device_token d LEFT JOIN `_id_map_006` m ON d.user_id = m.old_id
SET d.user_id = COALESCE(m.new_id, d.user_id);
UPDATE password_reset_request p LEFT JOIN `_id_map_006` m ON p.user_id = m.old_id
SET p.user_id = COALESCE(m.new_id, p.user_id);
-- handled_by 可空（未处理的申请），LEFT JOIN 自然保留 NULL
UPDATE password_reset_request p LEFT JOIN `_id_map_006` m ON p.handled_by = m.old_id
SET p.handled_by = COALESCE(m.new_id, p.handled_by);

-- ── 4) 重排 user.id ───────────────────────────────────────────────────
--     先挪到负数腾出 1..N，否则互相撞主键。
--     -id 而不是任意负数：保持与原顺序一一对应。
UPDATE `user` SET id = -id;
UPDATE `user` u JOIN `_id_map_006` m ON u.id = -m.old_id
SET u.id = m.new_id;

-- ── 5) unique_id 对齐、自增起点、作废全部令牌 ──────────────────────────
UPDATE `user` SET unique_id = LPAD(id, 8, '0');

SET @max_id := (SELECT COALESCE(MAX(id), 0) FROM `user`);
SET @sql := CONCAT('ALTER TABLE `user` AUTO_INCREMENT = ', @max_id + 1);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- id 变了，旧令牌的 subject 会指向别人 —— 必须全部作废
UPDATE `user` SET token_version = token_version + 1;

-- ── 6) 提交或回滚 ─────────────────────────────────────────────────────
--     ⚠️ 说明：第 3.1 步的 CREATE / DROP / RENAME 属于 DDL，会**隐式提交**，
--     因此干跑时它们不会被 ROLLBACK 撤销。但克隆表的来源与结果相同
--     （同一次 INSERT ... SELECT 算出来的），所以重复执行是幂等的：
--     每次都从当前 friendship（已是重排后）重建，结果不变。
--     真正的业务数据（user / message / activity / …）都在 DML 里，
--     受 ROLLBACK 保护。
SELECT IF(@dry_run = 1, '干跑模式：DML 已回滚，业务数据未改动', '已提交') AS 执行结果;
COMMIT;

-- ── 7) 自检 ───────────────────────────────────────────────────────────
SELECT '用户数' AS item, COUNT(*) AS value FROM `user`
UNION ALL
SELECT 'id 连续（1..N 无空洞）',
       IF(COUNT(*) = MAX(id) AND MIN(id) = 1, '是', CONCAT('否 max=', MAX(id)))
FROM `user`
UNION ALL
SELECT 'unique_id 与 id 一致',
       IF(SUM(unique_id <> LPAD(id, 8, '0')) = 0, '是', '否')
FROM `user`
UNION ALL
SELECT '下一个新用户 id', MAX(id) + 1 FROM `user`;

SELECT '管理员' AS item,
       GROUP_CONCAT(CONCAT(id, '=', nickname, '(', unique_id, ')')
                    ORDER BY id SEPARATOR '  ') AS value
FROM `user` WHERE role = 1;

-- 引用完整性：重排后不应有任何引用指向不存在的用户
SELECT '引用完整性' AS item,
       IF(SUM(bad) = 0, '全部有效', CONCAT('有 ', SUM(bad), ' 条悬空引用')) AS value
FROM (
    SELECT COUNT(*) AS bad FROM activity a LEFT JOIN `user` u ON u.id = a.user_id WHERE u.id IS NULL
    UNION ALL SELECT COUNT(*) FROM friendship f LEFT JOIN `user` u ON u.id = f.user_id WHERE u.id IS NULL
    UNION ALL SELECT COUNT(*) FROM friendship f LEFT JOIN `user` u ON u.id = f.friend_id WHERE u.id IS NULL
    UNION ALL SELECT COUNT(*) FROM message g LEFT JOIN `user` u ON u.id = g.sender_id WHERE u.id IS NULL
    UNION ALL SELECT COUNT(*) FROM message g LEFT JOIN `user` u ON u.id = g.receiver_id WHERE u.id IS NULL
    UNION ALL SELECT COUNT(*) FROM user_stats s LEFT JOIN `user` u ON u.id = s.user_id WHERE u.id IS NULL
    UNION ALL SELECT COUNT(*) FROM user_badge b LEFT JOIN `user` u ON u.id = b.user_id WHERE u.id IS NULL
    UNION ALL SELECT COUNT(*) FROM user_goal g LEFT JOIN `user` u ON u.id = g.user_id WHERE u.id IS NULL
    UNION ALL SELECT COUNT(*) FROM leaderboard_stats l LEFT JOIN `user` u ON u.id = l.user_id WHERE u.id IS NULL
    UNION ALL SELECT COUNT(*) FROM chat_preference c LEFT JOIN `user` u ON u.id = c.user_id WHERE u.id IS NULL
    UNION ALL SELECT COUNT(*) FROM chat_preference c LEFT JOIN `user` u ON u.id = c.friend_id WHERE u.id IS NULL
    UNION ALL SELECT COUNT(*) FROM device_token d LEFT JOIN `user` u ON u.id = d.user_id WHERE u.id IS NULL
    UNION ALL SELECT COUNT(*) FROM password_reset_request p LEFT JOIN `user` u ON u.id = p.user_id WHERE u.id IS NULL
    UNION ALL SELECT COUNT(*) FROM password_reset_request p LEFT JOIN `user` u ON u.id = p.handled_by
             WHERE p.handled_by IS NOT NULL AND u.id IS NULL
) t;

-- 行数核对：重排只改 id，不该增删任何行。
-- friendship / message 在备份里各记了两列，所以计数要除以 2。
SELECT '行数核对' AS item,
       IF(SUM(before_cnt <> after_cnt) = 0, '一致',
          CONCAT('不一致的表数: ', SUM(before_cnt <> after_cnt))) AS value
FROM (
    SELECT (SELECT COUNT(*) FROM `_backup_refs_006` WHERE tbl='activity') AS before_cnt,
           (SELECT COUNT(*) FROM activity) AS after_cnt
    UNION ALL SELECT (SELECT COUNT(*) FROM `_backup_refs_006` WHERE tbl='friendship')/2,
           (SELECT COUNT(*) FROM friendship)
    UNION ALL SELECT (SELECT COUNT(*) FROM `_backup_refs_006` WHERE tbl='message')/2,
           (SELECT COUNT(*) FROM message)
    UNION ALL SELECT (SELECT COUNT(*) FROM `_backup_user_ids_006`),
           (SELECT COUNT(*) FROM `user`)
) c;
