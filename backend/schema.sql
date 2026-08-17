-- backend/schema.sql
-- ApiService(lib/services/api_service.dart)가 기대하는 데이터 구조에 맞춘 스키마입니다.

CREATE DATABASE IF NOT EXISTS microstone
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE microstone;

CREATE TABLE IF NOT EXISTS users (
  id            VARCHAR(64)  NOT NULL PRIMARY KEY,
  password_hash VARCHAR(255) NOT NULL,
  nickname      VARCHAR(64)  NOT NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS medications (
  id         VARCHAR(64)  NOT NULL PRIMARY KEY,
  user_id    VARCHAR(64)  NOT NULL,
  name       VARCHAR(100) NOT NULL,
  time       VARCHAR(5)   NOT NULL,   -- 'HH:mm'
  date       DATE         NOT NULL,
  is_done    TINYINT(1)   NOT NULL DEFAULT 0,
  taken_at   DATETIME     NULL,
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_user_date (user_id, date)
) ENGINE=InnoDB;
