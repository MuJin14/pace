DROP TABLE IF EXISTS user;

CREATE TABLE user (
    id            BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    unique_id     VARCHAR(20)  NOT NULL,
    phone         VARCHAR(20)  NOT NULL,
    password_hash VARCHAR(100) NOT NULL,
    nickname      VARCHAR(30)  NOT NULL,
    avatar_url    VARCHAR(255),
    role          TINYINT      NOT NULL DEFAULT 0,
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_phone UNIQUE (phone),
    CONSTRAINT uk_unique_id UNIQUE (unique_id)
);

DROP TABLE IF EXISTS activity;

CREATE TABLE activity (
    id               BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id          BIGINT       NOT NULL,
    type             TINYINT      NOT NULL,
    mode             TINYINT      NOT NULL DEFAULT 1,
    invalid          TINYINT      NOT NULL DEFAULT 0,
    fence_id         BIGINT,
    outside_ratio    DECIMAL(5,4),
    distance_meters  INT          NOT NULL DEFAULT 0,
    duration_seconds INT          NOT NULL DEFAULT 0,
    avg_speed        DECIMAL(6,2),
    calories         DECIMAL(8,2),
    start_time       TIMESTAMP    NOT NULL,
    end_time         TIMESTAMP    NOT NULL,
    start_lat        DECIMAL(10,7),
    start_lng        DECIMAL(10,7),
    end_lat          DECIMAL(10,7),
    end_lng          DECIMAL(10,7),
    track_json       TEXT,
    created_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS leaderboard_stats;

CREATE TABLE leaderboard_stats (
    id              BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id         BIGINT      NOT NULL,
    scope           VARCHAR(20) NOT NULL,
    period          VARCHAR(20) NOT NULL,
    type            TINYINT     NOT NULL,
    distance_meters INT         NOT NULL DEFAULT 0,
    created_at      TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_user_scope_period_type UNIQUE (user_id, scope, period, type)
);

CREATE INDEX idx_scope_period_type_distance ON leaderboard_stats (scope, period, type, distance_meters);

DROP TABLE IF EXISTS friendship;

CREATE TABLE friendship (
    id         BIGINT    NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id    BIGINT    NOT NULL,
    friend_id  BIGINT    NOT NULL,
    status     TINYINT   NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_user_friend UNIQUE (user_id, friend_id)
);

CREATE INDEX idx_friend_status ON friendship (friend_id, status);

DROP TABLE IF EXISTS message;

CREATE TABLE message (
    id          BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    sender_id   BIGINT        NOT NULL,
    receiver_id BIGINT        NOT NULL,
    content     VARCHAR(2000) NOT NULL,
    type        TINYINT       NOT NULL DEFAULT 1,
    delivered   TINYINT       NOT NULL DEFAULT 0,
    read_at     TIMESTAMP,
    created_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_receiver_delivered_id ON message (receiver_id, delivered, id);
CREATE INDEX idx_sender_id ON message (sender_id, id);
CREATE INDEX idx_receiver_id ON message (receiver_id, id);

DROP TABLE IF EXISTS campus_fence;

CREATE TABLE campus_fence (
    id                    BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name                  VARCHAR(50)   NOT NULL,
    center_lat            DECIMAL(10,7) NOT NULL,
    center_lng            DECIMAL(10,7) NOT NULL,
    radius_meters         INT           NOT NULL,
    allowed_outside_ratio DECIMAL(5,4)  NOT NULL DEFAULT 0.3000,
    enabled               TINYINT       NOT NULL DEFAULT 1,
    created_at            TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS user_goal;

CREATE TABLE user_goal (
    id                      BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id                 BIGINT      NOT NULL,
    period_type             VARCHAR(20) NOT NULL,
    target_distance_meters  INT         NOT NULL,
    current_distance_meters INT         NOT NULL DEFAULT 0,
    start_date              DATE        NOT NULL,
    end_date                DATE        NOT NULL,
    status                  TINYINT     NOT NULL DEFAULT 0,
    created_at              TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS badge;

CREATE TABLE badge (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    code        VARCHAR(50)  NOT NULL,
    name        VARCHAR(50)  NOT NULL,
    icon        VARCHAR(255),
    description VARCHAR(255),
    rule_type   VARCHAR(30)  NOT NULL,
    rule_value  INT          NOT NULL,
    enabled     TINYINT      NOT NULL DEFAULT 1,
    sort        INT          NOT NULL DEFAULT 0,
    created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_badge_code UNIQUE (code)
);

DROP TABLE IF EXISTS user_badge;

CREATE TABLE user_badge (
    id         BIGINT    NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id    BIGINT    NOT NULL,
    badge_id   BIGINT    NOT NULL,
    awarded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_user_badge UNIQUE (user_id, badge_id)
);

DROP TABLE IF EXISTS user_stats;

CREATE TABLE user_stats (
    user_id                     BIGINT NOT NULL PRIMARY KEY,
    total_distance_meters       INT    NOT NULL DEFAULT 0,
    total_activity_count        INT    NOT NULL DEFAULT 0,
    streak_days                 INT    NOT NULL DEFAULT 0,
    last_activity_date          DATE,
    weekly_goal_completed_count INT    NOT NULL DEFAULT 0,
    updated_at                  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_fence_enabled ON campus_fence (enabled);
CREATE INDEX idx_user_goal_status ON user_goal (user_id, status);
CREATE INDEX idx_user_goal_period_status ON user_goal (user_id, period_type, status);
CREATE INDEX idx_user_badge_badge ON user_badge (badge_id);
