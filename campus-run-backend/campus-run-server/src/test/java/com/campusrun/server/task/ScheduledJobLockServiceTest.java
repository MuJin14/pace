package com.campusrun.server.task;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

import java.time.LocalDate;
import java.time.ZoneId;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 定时任务互斥锁行为固化。
 *
 * <p>这些用例的价值在「防重复执行」：多实例部署时若锁失效，排行榜 30 天榜会被重复累加、
 * 连续打卡会被重复重置，而这类问题在单实例测试里看不出来。
 */
@SpringBootTest
@ActiveProfiles("test")
class ScheduledJobLockServiceTest {

    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    @Autowired
    private ScheduledJobLockService jobLock;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @AfterEach
    void cleanUp() {
        jdbcTemplate.update("DELETE FROM scheduled_job_lock");
    }

    @Test
    @DisplayName("同一天同一任务：第一个实例拿到锁，第二个被拒绝")
    void sameJobSameDay_onlyOneWinner() {
        assertTrue(jobLock.tryAcquireToday("leaderboard.rebuildRolling30d"), "首次应拿到锁");
        assertFalse(jobLock.tryAcquireToday("leaderboard.rebuildRolling30d"), "重复调用应被拒绝");
        assertFalse(jobLock.tryAcquireToday("leaderboard.rebuildRolling30d"), "第三次仍应被拒绝");
    }

    @Test
    @DisplayName("不同任务互不影响")
    void differentJobsAreIndependent() {
        assertTrue(jobLock.tryAcquireToday("job.a"));
        assertTrue(jobLock.tryAcquireToday("job.b"));
        assertFalse(jobLock.tryAcquireToday("job.a"));
        assertFalse(jobLock.tryAcquireToday("job.b"));
    }

    @Test
    @DisplayName("换一天（历史记录不影响当天）")
    void historicalRowDoesNotBlockToday() {
        jdbcTemplate.update(
                "INSERT INTO scheduled_job_lock (job_name, run_date, instance_id) VALUES (?, ?, ?)",
                "job.a", LocalDate.now(ZONE).minusDays(1), "old-instance");

        assertTrue(jobLock.tryAcquireToday("job.a"), "昨天的锁不应阻塞今天");
    }

    @Test
    @DisplayName("purgeBefore 清理历史记录，保留近期")
    void purgeRemovesOldRowsOnly() {
        LocalDate today = LocalDate.now(ZONE);
        jdbcTemplate.update(
                "INSERT INTO scheduled_job_lock (job_name, run_date, instance_id) VALUES (?, ?, ?)",
                "job.old", today.minusDays(60), "x");
        jdbcTemplate.update(
                "INSERT INTO scheduled_job_lock (job_name, run_date, instance_id) VALUES (?, ?, ?)",
                "job.recent", today.minusDays(3), "x");

        int removed = jobLock.purgeBefore(today.minusDays(30));

        assertEquals(1, removed, "只应清掉 30 天前那条");
        Integer left = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM scheduled_job_lock WHERE job_name = 'job.recent'", Integer.class);
        assertEquals(1, left);
    }
}
