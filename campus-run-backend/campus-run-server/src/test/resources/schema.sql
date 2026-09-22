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
