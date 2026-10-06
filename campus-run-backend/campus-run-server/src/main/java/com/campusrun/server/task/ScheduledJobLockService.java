package com.campusrun.server.task;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.ZoneId;

/**
 * 定时任务的跨实例互斥锁。
 *
 * <p><b>为什么需要</b>：原先的定时任务都是裸 {@code @Scheduled}。一旦部署两个实例
 * （滚动发布、扩容、双活），同一个任务会在两个实例上同时执行——排行榜 30 天榜会被重复累加、
 * 过期目标会被重复处理、连续打卡天数会被重复重置。这类 bug 在单实例测试中完全看不出来。
 *
 * <p><b>实现方式</b>：利用数据库唯一键做「插入成功即抢到锁」。
 * 表 {@code scheduled_job_lock} 上有 {@code UNIQUE KEY (job_name, run_date)}：
 * <ul>
 *   <li>插入成功 → 本实例执行；</li>
 *   <li>主键冲突 → 今天已被别的实例执行过，本次跳过。</li>
 * </ul>
 *
 * <p><b>为什么用数据库而不是 ShedLock/Redis</b>：项目已明确不用 Redis，且引入 ShedLock
 * 需要新依赖与新表结构。本项目这些任务全部是「每天一次」的语义，
 * 用 {@code (job_name, run_date)} 唯一键表达「今天只跑一次」最直接、可读性最好，
 * 且天然幂等（重启、补跑都不会重复执行）。
 *
 * <p><b>已知局限</b>：如果实例在「抢到锁之后、任务完成之前」崩溃，当天该任务不会补跑。
 * 对这些任务来说是可接受的：榜单重算与清理都有次日兜底，且比「重复累加」的危害小得多。
 */
@Service
public class ScheduledJobLockService {

    private static final Logger log = LoggerFactory.getLogger(ScheduledJobLockService.class);

    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    private final JdbcTemplate jdbcTemplate;

    public ScheduledJobLockService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * 尝试取得「今天执行 jobName 一次」的资格。
     *
     * @param jobName 任务名（稳定标识，改名等于换锁）
     * @return true = 本实例获得执行权；false = 今天已执行过，应跳过
     */
    public boolean tryAcquireToday(String jobName) {
        LocalDate today = LocalDate.now(ZONE);
        try {
            jdbcTemplate.update(
                    "INSERT INTO scheduled_job_lock (job_name, run_date, instance_id, created_at) "
                            + "VALUES (?, ?, ?, CURRENT_TIMESTAMP)",
                    jobName, today, instanceId());
            log.info("定时任务抢锁成功，job={}, date={}", jobName, today);
            return true;
        } catch (org.springframework.dao.DuplicateKeyException e) {
            log.info("定时任务今天已由其它实例执行，job={}, date={}，本实例跳过", jobName, today);
            return false;
        } catch (Exception e) {
            // 数据库异常时选择「不执行」而不是「执行」：宁可漏跑一天（次日兜底），
            // 也不要因为锁表不可用导致多实例同时重复执行。
            log.error("定时任务抢锁异常，job={}，本次跳过执行", jobName, e);
            return false;
        }
    }

    /** 清理历史锁记录，避免表无限增长（由排行榜清理任务顺带调用）。 */
    public int purgeBefore(LocalDate date) {
        return jdbcTemplate.update("DELETE FROM scheduled_job_lock WHERE run_date < ?", date);
    }

    private String instanceId() {
        try {
            return java.net.InetAddress.getLocalHost().getHostName();
        } catch (Exception e) {
            return "unknown";
        }
    }
}
