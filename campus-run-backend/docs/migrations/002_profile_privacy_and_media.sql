-- ============================================================
-- 校园跑 · 迁移 002：资料可见性 + 富媒体消息 + 聊天免打扰
--
-- 用途：对**已存在的生产库**执行（新建库直接用 docs/schema.sql 即可）
--
-- 执行前务必先备份：
--   docker exec campus-run-mysql mysqldump -uroot -p'<密码>' campus_run > backup-$(date +%F).sql
--
-- 幂等：用 information_schema 判断列/表是否存在，可重复执行。
--   （写法说明：PREPARE 串里只放最简单的 SELECT 1，避免引号嵌套导致的语法错误）
-- ============================================================

USE campus_run;

-- ── 1. user 表：性别 / 年龄 + 可见性 ──────────────────────────────
--   可见性默认 0（不公开）—— 隐私默认关闭，公开需用户主动开启。

SET @db := DATABASE();

SET @exists := (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'user' AND COLUMN_NAME = 'gender');
SET @sql := IF(@exists = 0,
    'ALTER TABLE `user` ADD COLUMN `gender` TINYINT DEFAULT NULL COMMENT ''0=保密 1=男 2=女''',
    'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

SET @exists := (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'user' AND COLUMN_NAME = 'age');
SET @sql := IF(@exists = 0,
    'ALTER TABLE `user` ADD COLUMN `age` INT DEFAULT NULL COMMENT ''1-120''',
    'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

SET @exists := (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'user' AND COLUMN_NAME = 'gender_public');
SET @sql := IF(@exists = 0,
    'ALTER TABLE `user` ADD COLUMN `gender_public` TINYINT NOT NULL DEFAULT 0 COMMENT ''1=他人可见''',
    'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

SET @exists := (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'user' AND COLUMN_NAME = 'age_public');
SET @sql := IF(@exists = 0,
    'ALTER TABLE `user` ADD COLUMN `age_public` TINYINT NOT NULL DEFAULT 0 COMMENT ''1=他人可见''',
    'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ── 1.5 改密后使旧 refresh token 失效 ────────────────────────────
-- 签发时间早于该值的 refresh token 一律拒绝。
-- 不加这个的话，改密只能拦住「用新密码登录」，而别人手里 30 天有效的
-- refresh token 仍能不断换到新 access token —— 等于没改。
SET @exists := (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'user' AND COLUMN_NAME = 'token_invalid_before');
SET @sql := IF(@exists = 0,
    'ALTER TABLE `user` ADD COLUMN `token_invalid_before` DATETIME DEFAULT NULL',
    'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ── 2. message 表：富媒体 ────────────────────────────────────────
SET @exists := (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'message' AND COLUMN_NAME = 'media_url');
SET @sql := IF(@exists = 0,
    'ALTER TABLE `message` ADD COLUMN `media_url` VARCHAR(255) DEFAULT NULL COMMENT ''type=2 时必填''',
    'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- content 改为可空：图片/表情包消息可以没有文字
ALTER TABLE `message` MODIFY COLUMN `content` VARCHAR(2000) DEFAULT NULL;

-- ── 3. chat_preference：会话级免打扰 ─────────────────────────────
CREATE TABLE IF NOT EXISTS `chat_preference` (
    `id`         BIGINT   NOT NULL AUTO_INCREMENT COMMENT '主键',
    `user_id`    BIGINT   NOT NULL COMMENT '设置方用户ID',
    `friend_id`  BIGINT   NOT NULL COMMENT '会话对方用户ID',
    `muted`      TINYINT  NOT NULL DEFAULT 0 COMMENT '是否免打扰：0=否 1=是',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                          ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_user_friend` (`user_id`, `friend_id`),
    KEY `idx_user_muted` (`user_id`, `muted`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '聊天会话偏好（免打扰）';

-- ── 4. 结果校验 ──────────────────────────────────────────────────
SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'user'
  AND COLUMN_NAME IN ('gender', 'age', 'gender_public', 'age_public')
ORDER BY COLUMN_NAME;

SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'message'
  AND COLUMN_NAME IN ('content', 'type', 'media_url')
ORDER BY COLUMN_NAME;

SELECT COUNT(*) AS chat_preference_exists
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'chat_preference';
