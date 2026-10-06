#!/usr/bin/env bash
# ============================================================================
# Remote half of the campus-run deploy (runs on the server).
#
# Uploaded together with: the source zip (already extracted to
# /home/ubuntu/src-extract) and the two migration files in $TMP_DIR.
#
# Steps: backup DB -> apply migrations -> copy source -> rebuild container -> verify.
# Idempotent: migrations guard themselves, and only the 5 newest backups are kept.
# ============================================================================
set -euo pipefail

REMOTE_DIR="${REMOTE_DIR:-/home/ubuntu/campus-run-backend}"
TMP_DIR="${TMP_DIR:-/home/ubuntu/deploy-tmp}"
SRC_DIR="${SRC_DIR:-/home/ubuntu/src-extract}"
SKIP_MIGRATIONS="${SKIP_MIGRATIONS:-0}"

cd "$REMOTE_DIR"

if docker ps >/dev/null 2>&1; then DOCKER="docker"; else DOCKER="sudo docker"; fi
echo "DOCKER=$DOCKER"
echo "PWD=$(pwd)"

DBP="$(grep '^DB_PASSWORD=' .env | cut -d= -f2-)"
echo "DB_PASSWORD length: ${#DBP}"

echo
echo "=== 1. containers ==="
$DOCKER ps --format '{{.Names}}\t{{.Status}}'

echo
echo "=== 2. backup database ==="
BACKUP="$HOME/backup-$(date +%F-%H%M%S).sql"
$DOCKER exec campus-run-mysql mysqldump -uroot -p"$DBP" campus_run > "$BACKUP" 2>/dev/null || true
SIZE=$(wc -c < "$BACKUP")
echo "backup: $BACKUP ($SIZE bytes)"
if [ "$SIZE" -lt 1000 ]; then
    echo "!! backup looks empty - aborting so we never deploy without a safety net"
    exit 1
fi
ls -1t "$HOME"/backup-*.sql 2>/dev/null | tail -n +6 | xargs -r rm -f
echo "kept backups:"; ls -1t "$HOME"/backup-*.sql | head -5

if [ "$SKIP_MIGRATIONS" != "1" ]; then
    # 通用循环：$TMP_DIR 里的每个 .sql 都按文件名顺序执行。
    # 这样新增迁移不需要再改这个脚本，也就不会出现「迁移写了但没被执行」。
    #
    # ⚠️ 刻意**不**在末尾加 `|| true`：之前那处 `|| true` 掩盖过真实的迁移失败，
    # 让部署「看起来成功」而库里其实是旧的。迁移脚本本身是幂等的，
    # 失败就应当中止部署 —— 带着半套 schema 上线比部署失败糟糕得多。
    for mig in $(ls -1 "$TMP_DIR"/*.sql 2>/dev/null | sort); do
        name=$(basename "$mig")
        echo
        echo "=== migration $name ==="
        if ! $DOCKER exec -i campus-run-mysql mysql -uroot -p"$DBP" \
                --default-character-set=utf8mb4 campus_run \
                < "$mig" 2>&1 | grep -v 'Using a password'; then
            echo "!! migration $name FAILED - aborting deploy"
            exit 1
        fi
        echo "  ok: $name"
    done

    echo
    echo "=== 5. verify schema + badge bytes ==="
    $DOCKER exec campus-run-mysql mysql -uroot -p"$DBP" \
        --default-character-set=utf8mb4 campus_run -e "
SELECT code, name, HEX(name) AS name_hex FROM badge ORDER BY sort;
SELECT COUNT(*) AS user_new_cols FROM information_schema.columns
  WHERE table_schema='campus_run' AND table_name='user'
    AND column_name IN ('gender','age','gender_public','age_public','token_invalid_before');
SELECT COUNT(*) AS message_media_col FROM information_schema.columns
  WHERE table_schema='campus_run' AND table_name='message' AND column_name='media_url';
SELECT COUNT(*) AS chat_preference_rows FROM chat_preference;
SELECT COUNT(*) AS password_reset_table FROM information_schema.tables
  WHERE table_schema='campus_run' AND table_name='password_reset_request';
" 2>&1 | grep -v 'Using a password'
fi

echo
echo "=== 6. verify the source we just extracted is in place ==="
# The tar is extracted straight over $REMOTE_DIR by deploy-server.ps1, so there
# is nothing to copy here - only a sanity check that the deploy is the new code.
if [ ! -f campus-run-server/pom.xml ]; then
    echo "!! campus-run-server/pom.xml missing - the tar extraction did not land"
    exit 1
fi
CHAT_PREF=$(grep -c 'chatPreferenceMapper.deleteByUser' campus-run-server/src/main/java/com/campusrun/server/service/impl/UserServiceImpl.java || true)
DEVICE_TOK=$(grep -c 'deviceTokenMapper.deleteByUserId' campus-run-server/src/main/java/com/campusrun/server/service/impl/UserServiceImpl.java || true)
echo "UserServiceImpl uses chatPreferenceMapper.deleteByUser : $CHAT_PREF (expect >=1)"
echo "UserServiceImpl uses deviceTokenMapper.deleteByUserId : $DEVICE_TOK (expect >=1)"
if [ "$CHAT_PREF" -lt 1 ] || [ "$DEVICE_TOK" -lt 1 ]; then
    echo "!! source does not contain the delete-account cleanup fix - refusing to deploy"
    exit 1
fi

echo
echo "=== 7. rebuild + restart app (mvn runs inside Docker) ==="
$DOCKER compose -f docker-compose.deploy.yml up -d --build app 2>&1 | tail -30

echo
echo "=== 7b. fix upload volume ownership ==="
# ⚠️ 这一步**必须**有，而且不能靠 Dockerfile 里的 mkdir+chown 代替。
#
# 原因：命名卷的内容属主由 Docker 在**首次创建卷时**从镜像里复制/推断。
# 一旦卷已经存在（我们这个卷就是），改 Dockerfile 对它毫无影响 ——
# 卷里记的仍是当初的 root:root。容器以非 root 的 app 用户运行，
# 于是上传一律失败（code=6003「图片保存失败」），
# 而日志里只有一句 IOException，很难定位到卷属主。
#
# 这里每次部署都纠正一次，代价接近 0，但换卷/重建/迁移机器都不会再踩。
$DOCKER exec -u root campus-run-app chown -R app:app /app/uploads 2>/dev/null \
    && echo "  uploads 属主已修正" \
    || echo "  (容器尚未就绪，跳过属主修正 —— 下一段重启后会再试)"

echo
echo "=== 7c. restart app so the startup check re-runs ==="
$DOCKER compose -f docker-compose.deploy.yml restart app 2>&1 | tail -5

echo
echo "=== 8. wait for startup ==="
sleep 30
$DOCKER ps --format '{{.Names}}\t{{.Status}}'
echo '--- app log tail ---'
$DOCKER logs --tail 25 campus-run-app 2>&1 | tail -25
echo '--- upload dir check (must NOT say 不可写) ---'
$DOCKER logs campus-run-app 2>&1 | grep -E '上传目录' || echo "  (没有启动自检日志，需确认 FileStorageService 版本)"

echo
echo "=== 9. self-test ==="
curl -s -o /dev/null -w "  leaderboard -> HTTP %{http_code} (401 = alive)\n" \
  "http://127.0.0.1:8080/api/v1/leaderboard?scope=daily&type=1" || true
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"phone":"13800138000","password":"secret123"}' \
  "http://127.0.0.1:8080/api/v1/auth/login" | head -c 200 || true
echo

echo
echo "=== DEPLOY DONE ==="
