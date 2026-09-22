# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# 项目：校园跑 Campus Run

面向高校学生的运动记录与社交 App（跑步/骑行轨迹记录 + 排行榜 + 好友聊天 + 专属模式）。

## 技术栈

Java 17, Spring Boot 3.2, MySQL 8, Redis 7, MyBatis-Plus, Spring Security + JWT, WebSocket, Flutter

## 当前状态

处于设计阶段，后端/前端代码尚未脚手架，`campus-run-backend`、`campus-run-app`、`docs` 目录尚未创建。

## 设计文档

- `runApp_frame.txt`：完整设计文档（系统架构、数据库表结构、功能模块、里程碑、GPS 轨迹算法）
- `extra_suggest.md`：防作弊、排行榜防刷、社交合规、国内上架等补充建议

## 目录结构（规划）

- campus-run-backend：后端（Spring Boot）
- campus-run-app：Flutter 客户端
- docs：设计文档、API、SQL

## 常用命令

- 启动依赖：`docker compose up -d`
- 启动后端：`mvn spring-boot:run`
- 后端测试：`mvn test`
- 运行单个测试：`mvn test -Dtest=XxxTest#testMethod`
- 前端依赖：`flutter pub get`
- 前端运行：`flutter run`

## 关键领域约定

- 专属 ID：格式 `CR-XXXXXXXX`（CR = Campus Run，8 位数字，全局唯一）
- 运动类型：`1` = 跑步，`2` = 骑行
- Redis 排行榜：ZSET，key 为 `leaderboard:{period}:{type}`（如 `leaderboard:weekly:running`），score = 距离（米），member = 用户 ID；用 `ZINCRBY` 更新，`ZREVRANGE`/`ZREVRANK` 查询
- 核心表：`user`、`activity`（运动记录，轨迹以 JSON 存储）、`friendship`、`message`（详见 runApp_frame.txt 第五章）
- GPS 轨迹：滑动平均平滑 + 道格拉斯-普克抽稀；防作弊需地理围栏、随机打卡点、速度/步频校验

## 代码规范

- Controller 不写业务逻辑
- Service 负责事务
- DTO 与 Entity 分离
- 统一返回 Result<T>
- 全局异常处理
- 密码必须 BCrypt
- 禁止提交密钥和真实配置

## 当前阶段

第一阶段（MVP）：用户注册登录 + 专属 ID + 运动记录

后续：第二阶段排行榜 + 轨迹可视化 → 第三阶段好友 + 聊天 → 第四阶段专属模式
