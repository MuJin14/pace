package com.campusrun.server.security;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 限流器行为固化。
 *
 * <p>重点验证三件事：到量后拒绝、窗口滑动后恢复、不同 key 互不影响。
 * 第三点尤其重要——如果 key 维度退化（例如所有手机号共用一个计数），
 * 攻击者用任意号码就能把正常用户的配额打满。
 */
class RateLimiterTest {

    private RateLimiter limiter;

    @BeforeEach
    void setUp() {
        limiter = new RateLimiter();
    }

    @Test
    @DisplayName("窗口内未到量时放行，到量后拒绝")
    void allowsUpToLimitThenRejects() {
        for (int i = 0; i < 5; i++) {
            assertTrue(limiter.tryAcquire("login:phone:138", 5, 300), "第 " + (i + 1) + " 次应放行");
        }
        assertFalse(limiter.tryAcquire("login:phone:138", 5, 300), "第 6 次应被拒绝");
    }

    @Test
    @DisplayName("不同 key 的配额互相独立")
    void differentKeysAreIndependent() {
        for (int i = 0; i < 5; i++) {
            assertTrue(limiter.tryAcquire("login:phone:A", 5, 300));
        }
        assertFalse(limiter.tryAcquire("login:phone:A", 5, 300));
        // B 完全不受 A 影响
        assertTrue(limiter.tryAcquire("login:phone:B", 5, 300));
        // 不同动作也互相独立
        assertTrue(limiter.tryAcquire("register:phone:A", 5, 300));
    }

    @Test
    @DisplayName("窗口过期后配额恢复（用 0 长度窗口模拟过期）")
    void windowSlidesAndRestores() throws InterruptedException {
        // 窗口 0 秒：下一次调用时上一次记录已过窗口
        assertTrue(limiter.tryAcquire("k", 1, 0));
        Thread.sleep(5);
        assertTrue(limiter.tryAcquire("k", 1, 0), "窗口已滑过，应放行");
    }

    @Test
    @DisplayName("remaining 反映剩余可用次数且不为负")
    void remainingReportsLeft() {
        assertEquals(3, limiter.remaining("k", 3, 300));
        limiter.tryAcquire("k", 3, 300);
        assertEquals(2, limiter.remaining("k", 3, 300));
        limiter.tryAcquire("k", 3, 300);
        limiter.tryAcquire("k", 3, 300);
        assertEquals(0, limiter.remaining("k", 3, 300));
        assertFalse(limiter.tryAcquire("k", 3, 300));
        assertEquals(0, limiter.remaining("k", 3, 300), "超限后 remaining 不应为负");
    }

    @Test
    @DisplayName("reset 清空所有计数")
    void resetClearsAll() {
        limiter.tryAcquire("k", 1, 300);
        assertFalse(limiter.tryAcquire("k", 1, 300));
        limiter.reset();
        assertTrue(limiter.tryAcquire("k", 1, 300));
    }
}
