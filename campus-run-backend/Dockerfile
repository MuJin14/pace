# 后端运行镜像（多阶段构建）。
#
# 构建（在 campus-run-backend/ 下执行）：
#   docker build -t campus-run-server:latest .
#
# ⚠️ 国内构建注意：mvn 默认访问 repo.maven.apache.org 会**超时**，
# 表现为长时间卡在 `dependency:go-offline` 不动。
# 因此这里把 docker/maven-settings.xml（阿里云镜像）COPY 进镜像，
# 让所有 mvn 调用都走国内镜像。

# ── 构建阶段 ──────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /build

# Maven 镜像配置：必须放在任何 mvn 命令之前
COPY docker/maven-settings.xml /root/.m2/settings.xml

# 先只拷 POM 并预热依赖，让后续改代码时不必重新下载依赖（利用层缓存）
COPY pom.xml .
COPY campus-run-common/pom.xml campus-run-common/
COPY campus-run-server/pom.xml campus-run-server/

# 预热依赖。加 -T 1C 并行下载；即使这步部分失败也不影响后面的 package
# （package 阶段会把缺的依赖补下来），所以保留 || true。
RUN mvn -B -q -T 1C dependency:go-offline -DskipTests || true

COPY campus-run-common/src campus-run-common/src
COPY campus-run-server/src campus-run-server/src
# 跳过测试：CI 已在流水线里单独跑测试，镜像构建只需产物
RUN mvn -B -q clean package -DskipTests -pl campus-run-server -am

# ── 运行阶段 ──────────────────────────────────────────────
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app

# 以非 root 运行，降低容器逃逸后的影响面
RUN groupadd --system app && useradd --system --gid app app

COPY --from=build /build/campus-run-server/target/*.jar /app/app.jar

# ⚠️ 必须先建 uploads 目录并交给 app 用户，再 chown /app。
#
# 原因（真实事故：线上「上传头像失败 code=6003」）：
# compose 把命名卷挂到 /app/uploads。Docker **首次**挂载命名卷时，
# 会用镜像里该路径的属主来初始化卷内容；镜像里这个目录**不存在**的话，
# Docker 会以 **root** 创建挂载点 —— 容器里以 app 用户运行，
# `Files.createDirectories` 直接 EACCES，表现为「上传失败」。
#
# 只写 chown -R /app 是不够的：那发生在挂载点存在之前，
# chown 不会作用于后来挂上去的卷。
RUN mkdir -p /app/uploads/avatar /app/uploads/chat \
    && chown -R app:app /app

USER app

EXPOSE 8080
# 2C2G 服务器上 75% 可能偏大，留出 MySQL 的空间；按需用 JAVA_OPTS 覆盖
ENV JAVA_OPTS="-XX:MaxRAMPercentage=60 -XX:+UseSerialGC"
# 时区与业务一致（排行榜/目标的周期推导依赖 Asia/Shanghai）
ENV TZ=Asia/Shanghai

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
