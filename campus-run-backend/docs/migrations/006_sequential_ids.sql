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

-- ⚠️ 这里**没有**干跑模式。
--
-- 曾经加过一个 `@dry_run` 开关，靠 ROLLBACK 撤销。它是**失灵**的：
-- 第 3.1 步的 CREATE / DROP / RENAME 属于 DDL，会**隐式提交**事务，
-- 于是 ROLLBACK 只能撤销最后一段 DML —— 一旦在那之后出错，
-- 前面已改的 user 表就留在库里了（实际发生过）。
--
-- 正确的「干跑」是执行前先跑 `probe_collisions.sql`：
-- 它只读、会一次性查出所有唯一约束的冲突，且**不碰任何数据**。
-- 确认全部「无冲突」后再执行本脚本。

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
-- ⚠️ 序号**从 0 开始**：ROW_NUMBER() 默认从 1 起，所以减 1。
-- 用户明确要求三个管理员是 00000000 / 00000001 / 00000002，
-- 后面加入的依次 00000003、00000004……
-- 于是 new_id 的范围是 0..N-1，下一个新用户是 N。
INSERT INTO `_id_map_006` (old_id, new_id)
SELECT old_id, ROW_NUMBER() OVER (ORDER BY role DESC, old_id ASC) - 1
FROM `_backup_user_ids_006`;

-- 映射一致性校验：old_id / new_id 都必须唯一。
-- 不校验的话，一旦备份表被污染（见坑 2），后续只会抛一个
-- 看不出原因的 `Duplicate entry`。
SELECT IF(
    (SELECT COUNT(*) - COUNT(DISTINCT old_id) FROM `_id_map_006`) = 0
    AND (SELECT COUNT(*) - COUNT(DISTINCT new_id) FROM `_id_map_006`) = 0,
    '映射校验通过',
    '⚠️ 映射表不一致，请检查 _backup_user_ids_006 是否被污染') AS 映射校验;

-- ── 3) 重排引用列：**两阶段**（先全部取负，再一次性映射）──────────────
--
-- ══════════════════════════════════════════════════════════════════════
-- ⚠️⚠️ 为什么必须是两阶段 —— 这是本次迁移最关键的教训。
--
-- 直觉做法是「一条 UPDATE 直接改成新值」：
--
--     UPDATE user_stats s JOIN map m ON s.user_id = m.old_id
--     SET s.user_id = m.new_id;
--
-- 它会撞主键，而且**不是数据有问题**：是**中间态**撞。
-- user_stats 的主键就是 user_id，而新序号是 0..N-1、旧 id 是 1..31，
-- 两个区间**大面积重叠**：
--
--     旧 user_id:  1  2  3
--     新 user_id:  0  1  2
--     更新 user_id=1 的行 → 2   ← 而 user_id=2 的行还在（还没轮到它）
--     更新 user_id=2 的行 → 3   ← 而 user_id=3 的行还在
--     => Duplicate entry
--
-- 换更新顺序也躲不掉：新旧区间重叠，任何顺序都会有某个瞬间撞上。
--
-- **可靠做法：先把所有值搬到一个「与目标区间完全不重叠」的空间，
-- 再一次性搬到目标。** 负数天然满足这个条件 ——
-- 目标序号是 0..N-1（非负），而 -(id+1) 全是负数，两者不可能相等。
--
-- 这样中间态永远是负数，任何唯一约束都不会被触发。
-- ══════════════════════════════════════════════════════════════════════

-- 3.1 先把所有引用列搬到负数空间（-old_id - 1）
--     同一个表的多列必须在**同一条 UPDATE** 里一起搬：
--     分成两条会留下「一列已负、一列仍正」的中间态。
UPDATE activity a SET a.user_id = -(a.user_id + 1);
UPDATE friendship f SET f.user_id = -(f.user_id + 1), f.friend_id = -(f.friend_id + 1);
UPDATE message g SET g.sender_id = -(g.sender_id + 1), g.receiver_id = -(g.receiver_id + 1);
UPDATE user_stats s SET s.user_id = -(s.user_id + 1);
UPDATE user_badge b SET b.user_id = -(b.user_id + 1);
UPDATE user_goal g SET g.user_id = -(g.user_id + 1);
UPDATE leaderboard_stats l SET l.user_id = -(l.user_id + 1);
UPDATE chat_preference c SET c.user_id = -(c.user_id + 1), c.friend_id = -(c.friend_id + 1);
UPDATE device_token d SET d.user_id = -(d.user_id + 1);
UPDATE password_reset_request p SET p.user_id = -(p.user_id + 1);
UPDATE password_reset_request p SET p.handled_by = -(p.handled_by + 1)
WHERE p.handled_by IS NOT NULL;

-- 3.2 再从负数空间一次性映射到目标
--     映射表建在负数键上：from_id = -(old_id + 1) → to_id = new_id
DROP TABLE IF EXISTS `_neg_map_006`;
CREATE TABLE `_neg_map_006` (
    from_id BIGINT PRIMARY KEY,
    to_id BIGINT NOT NULL
);
INSERT INTO `_neg_map_006` (from_id, to_id)
SELECT -(old_id + 1), new_id FROM `_id_map_006`;

UPDATE activity a JOIN `_neg_map_006` m ON a.user_id = m.from_id SET a.user_id = m.to_id;
UPDATE friendship f JOIN `_neg_map_006` m ON f.user_id = m.from_id SET f.user_id = m.to_id;
UPDATE friendship f JOIN `_neg_map_006` m ON f.friend_id = m.from_id SET f.friend_id = m.to_id;
UPDATE message g JOIN `_neg_map_006` m ON g.sender_id = m.from_id SET g.sender_id = m.to_id;
UPDATE message g JOIN `_neg_map_006` m ON g.receiver_id = m.from_id SET g.receiver_id = m.to_id;
UPDATE user_stats s JOIN `_neg_map_006` m ON s.user_id = m.from_id SET s.user_id = m.to_id;
UPDATE user_badge b JOIN `_neg_map_006` m ON b.user_id = m.from_id SET b.user_id = m.to_id;
UPDATE user_goal g JOIN `_neg_map_006` m ON g.user_id = m.from_id SET g.user_id = m.to_id;
UPDATE leaderboard_stats l JOIN `_neg_map_006` m ON l.user_id = m.from_id SET l.user_id = m.to_id;
UPDATE chat_preference c JOIN `_neg_map_006` m ON c.user_id = m.from_id SET c.user_id = m.to_id;
UPDATE chat_preference c JOIN `_neg_map_006` m ON c.friend_id = m.from_id SET c.friend_id = m.to_id;
UPDATE device_token d JOIN `_neg_map_006` m ON d.user_id = m.from_id SET d.user_id = m.to_id;
UPDATE password_reset_request p JOIN `_neg_map_006` m ON p.user_id = m.from_id SET p.user_id = m.to_id;
UPDATE password_reset_request p JOIN `_neg_map_006` m ON p.handled_by = m.from_id SET p.handled_by = m.to_id;

-- ── 4) 重排 user.id ───────────────────────────────────────────────────
--     先挪到负数腾出位置，否则互相撞主键。
--
--     ⚠️ 用 -(id+1) 而不是 -id：新序号从 0 开始，需要一个能表示 0 的
--     中间值。若用 -id，原来的 id=0（如果有）会和 id 挪位前的 0 混淆。
--     目标序号是 0..N-1，负数区间与它完全不重叠。
UPDATE `user` SET id = -(id + 1);
UPDATE `user` u JOIN `_id_map_006` m ON u.id = -(m.old_id + 1)
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

-- ── 6) 提交 ───────────────────────────────────────────────────────────
--     注意：第 3.1 步的 DDL 已经隐式提交过前面的 DML，
--     所以这里的 COMMIT 主要是收尾（后面 user 表的改动）。
COMMIT;

DROP TABLE IF EXISTS `_neg_map_006`;

-- ── 7) 自检 ───────────────────────────────────────────────────────────
SELECT '用户数' AS item, COUNT(*) AS value FROM `user`
UNION ALL
SELECT 'id 连续（0..N-1 无空洞）',
       IF(COUNT(*) = MAX(id) + 1 AND MIN(id) = 0, '是',
          CONCAT('否 min=', MIN(id), ' max=', MAX(id)))
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
