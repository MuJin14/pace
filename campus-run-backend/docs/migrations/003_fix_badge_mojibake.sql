-- ============================================================
-- 修复 003：勋章文案双重编码（mojibake）
--
-- 症状：App 勋章墙显示「Ã¥Ë†ÂÃ¨Â·â10Ã¥âÂ¬Ã©âÂ¡Å」这类乱码。
-- 成因：schema.sql 里的种子数据是 **UTF-8**，但导入时 MySQL 客户端
--       用的是 latin1 连接字符集 → 每个中文字节被当作 latin1 字符再编码成 utf8mb4，
--       于是「初」变成「Ã¥Ë†Â」。
--
-- 修法：用**正确的文案覆盖**（而不是 REPLACE 去还原 —— 双重编码有多种变体，
--       做反向替换容易漏；直接用权威值覆盖最稳）。
--
-- 幂等：按 code 更新，重复执行结果一致。
-- ============================================================

USE campus_run;

-- ── 1. 用正确文案覆盖 badge 定义 ────────────────────────────────
-- 值取自 docs/schema.sql 的权威种子数据（已验证为干净 UTF-8）。

UPDATE `badge` SET `name` = '初跑10公里',     `description` = '累计有效里程达到 10 公里'
  WHERE `code` = 'distance_10km';
UPDATE `badge` SET `name` = '百公里达人',     `description` = '累计有效里程达到 100 公里'
  WHERE `code` = 'distance_100km';
UPDATE `badge` SET `name` = '五百公里大神',   `description` = '累计有效里程达到 500 公里'
  WHERE `code` = 'distance_500km';
UPDATE `badge` SET `name` = '十次运动',       `description` = '累计完成 10 次有效运动'
  WHERE `code` = 'count_10';
UPDATE `badge` SET `name` = '百次运动',       `description` = '累计完成 100 次有效运动'
  WHERE `code` = 'count_100';
UPDATE `badge` SET `name` = '连续打卡7天',    `description` = '连续 7 天完成有效运动'
  WHERE `code` = 'streak_7';
UPDATE `badge` SET `name` = '连续打卡30天',   `description` = '连续 30 天完成有效运动'
  WHERE `code` = 'streak_30';
UPDATE `badge` SET `name` = '周目标达成',     `description` = '首次完成周目标'
  WHERE `code` = 'weekly_goal_1';

-- ── 2. 补齐缺失的勋章定义 ───────────────────────────────────────
-- 服务器上只出现了一部分勋章（与导入中断有关），用 INSERT IGNORE 补齐。
INSERT IGNORE INTO `badge` (`code`, `name`, `icon`, `description`, `rule_type`, `rule_value`, `enabled`, `sort`) VALUES
('distance_10km',  '初跑10公里',   NULL, '累计有效里程达到 10 公里',  'total_distance', 10000, 1, 1),
('distance_100km', '百公里达人',   NULL, '累计有效里程达到 100 公里', 'total_distance', 100000, 1, 2),
('distance_500km', '五百公里大神', NULL, '累计有效里程达到 500 公里', 'total_distance', 500000, 1, 3),
('count_10',       '十次运动',     NULL, '累计完成 10 次有效运动',    'total_count', 10, 1, 4),
('count_100',      '百次运动',     NULL, '累计完成 100 次有效运动',   'total_count', 100, 1, 5),
('streak_7',       '连续打卡7天',  NULL, '连续 7 天完成有效运动',     'streak_days', 7, 1, 6),
('streak_30',      '连续打卡30天', NULL, '连续 30 天完成有效运动',    'streak_days', 30, 1, 7),
('weekly_goal_1',  '周目标达成',   NULL, '首次完成周目标',            'weekly_goal', 1, 1, 8);

-- ── 3. 清理孤儿 user_badge（导致接口返回 name=null 的条目）──────
-- 迁移时 user_badge.badge_id 引用到了服务器上不存在的 badge 行。
DELETE ub FROM `user_badge` ub
  LEFT JOIN `badge` b ON b.id = ub.badge_id
  WHERE b.id IS NULL;

-- ── 4. 校验：应无任何乱码字符 ───────────────────────────────────
SELECT id, code, name FROM `badge` ORDER BY sort, id;

SELECT '乱码行数（应为 0）' AS check_name, COUNT(*) AS cnt
FROM `badge` WHERE `name` LIKE '%Ã%' OR `name` LIKE '%Â%' OR `name` LIKE '%â%';

SELECT '孤儿 user_badge（应为 0）' AS check_name, COUNT(*) AS cnt
FROM `user_badge` ub LEFT JOIN `badge` b ON b.id = ub.badge_id WHERE b.id IS NULL;
