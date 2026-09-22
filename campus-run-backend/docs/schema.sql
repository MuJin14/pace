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
