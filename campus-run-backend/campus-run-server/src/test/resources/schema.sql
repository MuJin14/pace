DROP TABLE IF EXISTS user;

CREATE TABLE user (
    id            BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    unique_id     VARCHAR(20)  NOT NULL,
    phone         VARCHAR(20)  NOT NULL,
    password_hash VARCHAR(100) NOT NULL,
    nickname      VARCHAR(30)  NOT NULL,
    avatar_url    VARCHAR(255),
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
