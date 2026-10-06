-- ============================================================================
-- 迁移 004：管理员后台（找回密码 / 用户管理）
--
-- 背景：App 没有邮箱字段、也没有短信服务，所以无法自助找回密码。
-- 方案是给少量受信任账号开管理员权限，由管理员协助重置。
-- 本迁移新增「重置申请」表，让用户能在 App 内自助发起申请，
-- 避免只能靠线下喊话（管理员看不到谁需要帮助）。
--
-- 幂等：可重复执行。用 information_schema 判断表是否已存在。
-- 注意 PREPARE 串里只放最简单的 SELECT 1（写带引号的中文会让 MySQL 报 1064）。
-- ============================================================================

SET @tbl := (SELECT COUNT(*) FROM information_schema.tables
             WHERE table_schema = DATABASE() AND table_name = 'password_reset_request');

SET @sql := IF(@tbl = 0,
    'CREATE TABLE password_reset_request (
        id          BIGINT       NOT NULL AUTO_INCREMENT,
        user_id     BIGINT       NOT NULL,
        phone       VARCHAR(20)  NOT NULL,
        nickname    VARCHAR(20)  DEFAULT NULL,
        status      TINYINT      NOT NULL DEFAULT 0,
        note        VARCHAR(200) DEFAULT NULL,
        handled_by  BIGINT       DEFAULT NULL,
        handled_at  DATETIME     DEFAULT NULL,
        created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_status_created (status, created_at),
        KEY idx_user (user_id)
    ) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
      COMMENT = ''密码重置申请（用户自助发起，管理员处理）''',
    'SELECT 1');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 状态取值说明（写在注释里而不是索引里）：
--   0 = 待处理   1 = 已重置   2 = 已拒绝
-- 不建外键，与项目其它表保持一致（级联删除由应用层显式实现）。

SELECT 'password_reset_request 就绪' AS step,
       (SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = 'password_reset_request') AS table_exists;
