package com.campusrun.server.security;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 进程内滑动窗口限流器。
 *
 * <p>为什么需要：登录/注册/刷新令牌是三个「不花钱就能反复调用」的入口。
 * 没有限流时，攻击者可以对同一手机号无限次尝试密码（暴力破解），
 * 也可以批量注册刷号；这些都会直接冲击账号体系。
 *
 * <p>为什么是进程内而不是 Redis：本项目已明确不用 Redis，且当前是单实例部署。
 * 用 {@link ConcurrentHashMap} + 每 key 的时间戳队列实现，零依赖、零运维。
 * <b>局限</b>：多实例部署时各实例独立计数，实际限额是「单实例限额 × 实例数」；
 * 届时把本类替换为基于 Redis 的实现即可（接口保持不变）。
 *
 * <p>内存安全：key 数量有上限（{@link #MAX_KEYS}），并且每次调用会顺带清理过期条目，
 * 避免被大量随机 key（例如伪造不同手机号）撑爆内存。
 */
@Component
public class RateLimiter {

    private static final Logger log = LoggerFactory.getLogger(RateLimiter.class);

    /** 同时跟踪的 key 上限，超过后先清理过期项，仍然超限则拒绝新 key（fail-closed）。 */
    private static final int MAX_KEYS = 20_000;

    private final Map<String, Deque<Long>> hits = new ConcurrentHashMap<>();
    private final AtomicLong lastSweep = new AtomicLong(System.currentTimeMillis());

    /**
     * 尝试消费一次配额。
     *
     * @param key        限流维度（例如 {@code login:13800138000} 或 {@code login:ip:1.2.3.4}）
     * @param limit      窗口内允许的最大次数
     * @param windowSecs 窗口长度（秒）
     * @return true = 放行；false = 已超限，调用方应返回 429
     */
    public boolean tryAcquire(String key, int limit, long windowSecs) {
        long now = System.currentTimeMillis();
        long windowMillis = windowSecs * 1000L;
        sweepIfNeeded(now, windowMillis);

        Deque<Long> queue = hits.get(key);
        if (queue == null) {
            if (hits.size() >= MAX_KEYS) {
                // 无法为新 key 分配配额时选择拒绝，避免内存被稀释攻击撑爆
                log.warn("限流器 key 数量达到上限 {}，拒绝新 key", MAX_KEYS);
                return false;
            }
            queue = new ArrayDeque<>();
            Deque<Long> existing = hits.putIfAbsent(key, queue);
            if (existing != null) {
                queue = existing;
            }
        }

        synchronized (queue) {
            long cutoff = now - windowMillis;
            while (!queue.isEmpty() && queue.peekFirst() < cutoff) {
                queue.pollFirst();
            }
            if (queue.size() >= limit) {
                return false;
            }
            queue.addLast(now);
            return true;
        }
    }

    /** 剩余可用次数（用于提示「请稍后再试」或调试）。 */
    public int remaining(String key, int limit, long windowSecs) {
        Deque<Long> queue = hits.get(key);
        if (queue == null) {
            return limit;
        }
        long cutoff = System.currentTimeMillis() - windowSecs * 1000L;
        synchronized (queue) {
            while (!queue.isEmpty() && queue.peekFirst() < cutoff) {
                queue.pollFirst();
            }
            return Math.max(0, limit - queue.size());
        }
    }

    /** 测试用：清空所有计数。 */
    public void reset() {
        hits.clear();
    }

    private void sweepIfNeeded(long now, long windowMillis) {
        long last = lastSweep.get();
        // 最多每 60 秒清理一次，避免每次请求都全表扫描
        if (now - last < 60_000L) {
            return;
        }
        if (!lastSweep.compareAndSet(last, now)) {
            return;
        }
        long cutoff = now - windowMillis;
        hits.entrySet().removeIf(entry -> {
            Deque<Long> q = entry.getValue();
            synchronized (q) {
                while (!q.isEmpty() && q.peekFirst() < cutoff) {
                    q.pollFirst();
                }
                return q.isEmpty();
            }
        });
    }
}
