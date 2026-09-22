-- 校园跑（Campus Run）数据库初始化脚本
-- 第一阶段（MVP）：仅 user 表；activity / friendship / message 在后续阶段加入

CREATE DATABASE IF NOT EXISTS campus_run
    DEFAULT CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE campus_run;

CREATE TABLE IF NOT EXISTS `user` (
    `id`            BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    `unique_id`     VARCHAR(20)  NOT NULL COMMENT '专属ID，格式 CR-XXXXXXXX',
    `phone`         VARCHAR(20)  NOT NULL COMMENT '手机号（登录账号）',
    `password_hash` VARCHAR(100) NOT NULL COMMENT 'BCrypt 密码哈希',
    `nickname`      VARCHAR(30)  NOT NULL COMMENT '昵称',
    `avatar_url`    VARCHAR(255) DEFAULT NULL COMMENT '头像地址',
    `role`          TINYINT      NOT NULL DEFAULT 0 COMMENT '角色：0=普通 1=管理员',
    `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '注册时间',
    `updated_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                 ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_phone` (`phone`),
    UNIQUE KEY `uk_unique_id` (`unique_id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '用户表';

CREATE TABLE IF NOT EXISTS `activity` (
    `id`               BIGINT        NOT NULL AUTO_INCREMENT COMMENT '主键',
    `user_id`          BIGINT        NOT NULL COMMENT '所属用户ID',
    `type`             TINYINT       NOT NULL COMMENT '运动类型：1=跑步 2=骑行',
    `mode`             TINYINT       NOT NULL DEFAULT 1 COMMENT '模式：1=普通 2=专属',
    `invalid`          TINYINT       NOT NULL DEFAULT 0 COMMENT '是否无效：0=有效 1=无效',
    `fence_id`         BIGINT        DEFAULT NULL COMMENT '命中的校园围栏ID',
    `outside_ratio`    DECIMAL(5,4)  DEFAULT NULL COMMENT '围栏外轨迹点占比',
    `distance_meters`  INT           NOT NULL DEFAULT 0 COMMENT '距离（米），服务端计算',
    `duration_seconds` INT           NOT NULL DEFAULT 0 COMMENT '时长（秒），服务端计算',
    `avg_speed`        DECIMAL(6,2)  DEFAULT NULL COMMENT '平均速度（km/h），服务端计算',
    `calories`         DECIMAL(8,2)  DEFAULT NULL COMMENT '消耗卡路里（千卡）',
    `start_time`       DATETIME      NOT NULL COMMENT '开始时间',
    `end_time`         DATETIME      NOT NULL COMMENT '结束时间',
    `start_lat`        DECIMAL(10,7) DEFAULT NULL COMMENT '起点纬度',
    `start_lng`        DECIMAL(10,7) DEFAULT NULL COMMENT '起点经度',
    `end_lat`          DECIMAL(10,7) DEFAULT NULL COMMENT '终点纬度',
    `end_lng`          DECIMAL(10,7) DEFAULT NULL COMMENT '终点经度',
    `track_json`       LONGTEXT      DEFAULT NULL COMMENT '轨迹点 JSON 数组',
    `created_at`       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at`       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
                                     ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    KEY `idx_user_start_time` (`user_id`, `start_time`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '运动记录表';

CREATE TABLE IF NOT EXISTS `leaderboard_stats` (
    `id`              BIGINT      NOT NULL AUTO_INCREMENT COMMENT '主键',
    `user_id`         BIGINT      NOT NULL COMMENT '用户ID',
    `scope`           VARCHAR(20) NOT NULL COMMENT '榜单维度：daily/weekly/rolling30d/monthly',
    `period`          VARCHAR(20) NOT NULL COMMENT '周期标识：daily=yyyy-MM-dd，weekly=周一日期，monthly=yyyy-MM，rolling30d 恒为 CURRENT',
    `type`            TINYINT     NOT NULL COMMENT '运动类型：1=跑步 2=骑行',
    `distance_meters` INT         NOT NULL DEFAULT 0 COMMENT '累计距离（米）',
    `created_at`      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at`      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_user_scope_period_type` (`user_id`, `scope`, `period`, `type`),
    KEY `idx_scope_period_type_distance` (`scope`, `period`, `type`, `distance_meters` DESC)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '排行榜统计表';

CREATE TABLE IF NOT EXISTS `friendship` (
    `id`         BIGINT   NOT NULL AUTO_INCREMENT COMMENT '主键（也作为好友申请ID）',
    `user_id`    BIGINT   NOT NULL COMMENT '关系持有方用户ID（谁的好友/谁发出的申请）',
    `friend_id`  BIGINT   NOT NULL COMMENT '关系对方用户ID',
    `status`     TINYINT  NOT NULL DEFAULT 0 COMMENT '状态：0=PENDING 1=ACCEPTED',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                           ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_user_friend` (`user_id`, `friend_id`),
    KEY `idx_friend_status` (`friend_id`, `status`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '好友关系表';

CREATE TABLE IF NOT EXISTS `message` (
    `id`          BIGINT        NOT NULL AUTO_INCREMENT COMMENT '主键',
    `sender_id`   BIGINT        NOT NULL COMMENT '发送者用户ID',
    `receiver_id` BIGINT        NOT NULL COMMENT '接收者用户ID',
    `content`     VARCHAR(2000) NOT NULL COMMENT '消息内容（文本）',
    `type`        TINYINT       NOT NULL DEFAULT 1 COMMENT '消息类型：1=文本（预留 2=图片等）',
    `delivered`   TINYINT       NOT NULL DEFAULT 0 COMMENT '送达状态：0=未送达(离线) 1=已送达',
    `read_at`     DATETIME      DEFAULT NULL COMMENT '已读时间（预留字段，本阶段不做已读逻辑）',
    `created_at`  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '发送时间（服务端时间）',
    PRIMARY KEY (`id`),
    KEY `idx_receiver_delivered_id` (`receiver_id`, `delivered`, `id`),
    KEY `idx_sender_id` (`sender_id`, `id`),
    KEY `idx_receiver_id` (`receiver_id`, `id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '聊天消息表';

CREATE TABLE IF NOT EXISTS `campus_fence` (
    `id`                    BIGINT        NOT NULL AUTO_INCREMENT COMMENT '主键',
    `name`                  VARCHAR(50)   NOT NULL COMMENT '围栏名称',
    `center_lat`            DECIMAL(10,7) NOT NULL COMMENT '中心纬度',
    `center_lng`            DECIMAL(10,7) NOT NULL COMMENT '中心经度',
    `radius_meters`         INT           NOT NULL COMMENT '半径（米）',
    `allowed_outside_ratio` DECIMAL(5,4)  NOT NULL DEFAULT 0.3000 COMMENT '允许在围栏外的轨迹点比例',
    `enabled`               TINYINT       NOT NULL DEFAULT 1 COMMENT '是否启用：0=否 1=是',
    `created_at`            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at`            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
                                          ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    KEY `idx_enabled` (`enabled`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '校园围栏表';

CREATE TABLE IF NOT EXISTS `user_goal` (
    `id`                      BIGINT      NOT NULL AUTO_INCREMENT COMMENT '主键',
    `user_id`                 BIGINT      NOT NULL COMMENT '用户ID',
    `period_type`             VARCHAR(20) NOT NULL COMMENT '周期类型：weekly/monthly/custom',
    `target_distance_meters`  INT         NOT NULL COMMENT '目标距离（米）',
    `current_distance_meters` INT         NOT NULL DEFAULT 0 COMMENT '当前累计距离（米）',
    `start_date`              DATE        NOT NULL COMMENT '开始日期',
    `end_date`                DATE        NOT NULL COMMENT '结束日期',
    `status`                  TINYINT     NOT NULL DEFAULT 0 COMMENT '状态：0=进行中 1=已完成 2=已过期 3=已取消',
    `created_at`              DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at`              DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP
                                         ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    KEY `idx_user_status` (`user_id`, `status`),
    KEY `idx_user_period_status` (`user_id`, `period_type`, `status`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '用户运动目标表';

CREATE TABLE IF NOT EXISTS `badge` (
    `id`          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    `code`        VARCHAR(50)  NOT NULL COMMENT '唯一码',
    `name`        VARCHAR(50)  NOT NULL COMMENT '名称',
    `icon`        VARCHAR(255) DEFAULT NULL COMMENT '图标 URL',
    `description` VARCHAR(255) DEFAULT NULL COMMENT '描述',
    `rule_type`   VARCHAR(30)  NOT NULL COMMENT '规则类型：total_distance/activity_count/streak_days/weekly_goal_complete',
    `rule_value`  INT          NOT NULL COMMENT '规则阈值/次数',
    `enabled`     TINYINT      NOT NULL DEFAULT 1 COMMENT '是否启用',
    `sort`        INT          NOT NULL DEFAULT 0 COMMENT '排序',
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_code` (`code`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '勋章定义表';

CREATE TABLE IF NOT EXISTS `user_badge` (
    `id`         BIGINT   NOT NULL AUTO_INCREMENT COMMENT '主键',
    `user_id`    BIGINT   NOT NULL COMMENT '用户ID',
    `badge_id`   BIGINT   NOT NULL COMMENT '勋章ID',
    `awarded_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '获得时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_user_badge` (`user_id`, `badge_id`),
    KEY `idx_badge` (`badge_id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '用户勋章表';

CREATE TABLE IF NOT EXISTS `user_stats` (
    `user_id`                    BIGINT NOT NULL COMMENT '用户ID（主键）',
    `total_distance_meters`      INT    NOT NULL DEFAULT 0 COMMENT '累计有效里程（米）',
    `total_activity_count`       INT    NOT NULL DEFAULT 0 COMMENT '累计有效运动次数',
    `streak_days`                INT    NOT NULL DEFAULT 0 COMMENT '连续打卡天数',
    `last_activity_date`         DATE   DEFAULT NULL COMMENT '最近一次有效运动日期',
    `weekly_goal_completed_count` INT   NOT NULL DEFAULT 0 COMMENT '完成周目标次数',
    `updated_at`                 DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                          ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`user_id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '用户运动统计表';

-- 勋章种子数据
INSERT IGNORE INTO `badge` (`code`, `name`, `icon`, `description`, `rule_type`, `rule_value`, `enabled`, `sort`) VALUES
('distance_10km',   '初跑10公里',   NULL, '累计有效里程达到 10 公里',   'total_distance', 10000, 1, 1),
('distance_100km',  '百公里达人',   NULL, '累计有效里程达到 100 公里',  'total_distance', 100000, 1, 2),
('distance_500km',  '五百公里大神', NULL, '累计有效里程达到 500 公里',  'total_distance', 500000, 1, 3),
('count_10',        '十次运动',     NULL, '累计完成 10 次有效运动',    'activity_count', 10, 1, 4),
('count_100',       '百次运动',     NULL, '累计完成 100 次有效运动',   'activity_count', 100, 1, 5),
('streak_7',        '连续打卡7天',  NULL, '连续 7 天完成有效运动',     'streak_days', 7, 1, 6),
('streak_30',       '连续打卡30天', NULL, '连续 30 天完成有效运动',    'streak_days', 30, 1, 7),
('weekly_goal_1',   '周目标达成',   NULL, '首次完成周目标',           'weekly_goal_complete', 1, 1, 8);
