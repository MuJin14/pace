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
