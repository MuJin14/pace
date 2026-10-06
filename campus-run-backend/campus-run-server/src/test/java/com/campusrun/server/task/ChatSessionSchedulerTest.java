package com.campusrun.server.task;

import com.campusrun.server.websocket.WebSocketSessionManager;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;

/**
 * 会话回收时序的测试。
 *
 * <h2>为什么时序值得单独测</h2>
 *
 * 这两个常量直接决定「用户多久能看到红点」，但它们的效果**没有任何界面能体现**：
 *
 * <ul>
 *   <li>调大了 → 红点来得慢，用户只觉得「卡」，不会想到是服务端定时任务；</li>
 *   <li>调太小 → 健康连接被误杀，表现为**反复重连**（消息时断时续），
 *       比慢一点更难查，因为现象看起来像网络问题。</li>
 * </ul>
 *
 * 所以把「与客户端心跳间隔的倍数关系」钉成断言：
 * 改错了值会直接让测试失败，而不是等线上出问题。
 */
class ChatSessionSchedulerTest {

    /**
     * 空闲阈值必须显著大于客户端心跳间隔。
     *
     * <p>客户端每 25 秒发一次心跳并 {@code touch()} 刷新活跃时间。
     * 阈值如果贴近 25 秒，一次网络抖动（心跳晚到）就会误判为空闲，
     * 于是刚连上的用户被踢下线重连 —— 消息看起来「时有时无」。
     *
     * <p>1.5 倍是下限：允许**一次**心跳丢失仍不被误杀。
     */
    @Test
    void idleTimeout_leavesRoomForOneMissedHeartbeat() {
        double ratio = (double) ChatSessionScheduler.IDLE_TIMEOUT_MILLIS
                / ChatSessionScheduler.CLIENT_HEARTBEAT_INTERVAL_MILLIS;

        assertTrue(ratio >= 1.5,
                () -> String.format(
                        "空闲阈值 %.1fs 相对客户端心跳 %.1fs 只有 %.2f 倍，"
                                + "一次心跳丢失就会被误杀，导致反复重连。",
                        ChatSessionScheduler.IDLE_TIMEOUT_MILLIS / 1000.0,
                        ChatSessionScheduler.CLIENT_HEARTBEAT_INTERVAL_MILLIS / 1000.0,
                        ratio));
    }

    /**
     * 最坏情况的检测延迟 = 空闲阈值 + 扫描间隔，必须明显好于原来的 150 秒。
     *
     * <p>原来 {@code IDLE=90s} + {@code 每 60s 扫一次} → 最坏 150 秒，
     * 这正是用户抱怨「红点过了一分钟才出来」的来源。
     * 这里锁住「不超过 60 秒」，防止将来又把值调回去。
     */
    @Test
    void worstCaseDetectionDelay_isWithinOneMinute() {
        long worstCase = ChatSessionScheduler.IDLE_TIMEOUT_MILLIS
                + ChatSessionScheduler.SWEEP_INTERVAL_MILLIS;

        assertTrue(worstCase <= 60_000L,
                () -> String.format(
                        "最坏检测延迟 %.0fs 超过了 60 秒 —— 红点会明显滞后于消息。",
                        worstCase / 1000.0));
    }

    /** 扫描间隔要足够短，否则「判定超时」到「真正清理」之间又是一段白等。 */
    @Test
    void sweepInterval_isShortRelativeToIdleTimeout() {
        assertTrue(ChatSessionScheduler.SWEEP_INTERVAL_MILLIS
                        <= ChatSessionScheduler.IDLE_TIMEOUT_MILLIS / 3,
                "扫描间隔应显著小于空闲阈值，否则清理会被无谓地推迟");
    }

    /** 定时任务确实把空闲阈值透传给了 manager。 */
    @Test
    void scheduledSweep_usesConfiguredIdleTimeout() {
        WebSocketSessionManager manager = mock(WebSocketSessionManager.class);
        ChatSessionScheduler scheduler = new ChatSessionScheduler(manager);

        scheduler.sweepIdleSessions();

        org.mockito.Mockito.verify(manager)
                .sweep(ChatSessionScheduler.IDLE_TIMEOUT_MILLIS);
    }

    /** 常量本身应当是正数 —— 防止有人手滑写成 0 或负数（那会踢掉所有人）。 */
    @Test
    void constants_areSane() {
        assertEquals(45_000L, ChatSessionScheduler.IDLE_TIMEOUT_MILLIS);
        assertEquals(15_000L, ChatSessionScheduler.SWEEP_INTERVAL_MILLIS);
        assertTrue(ChatSessionScheduler.IDLE_TIMEOUT_MILLIS > 0);
    }

    /**
     * 启动日志里的倍数必须是**小数**，且断言的是真正被打印的方法。
     *
     * <p>真实踩到过：用整数除法算 45/25 得到 1，日志打成「倍数 1」——
     * 看起来像是阈值等于心跳间隔，读日志的人会以为配置错了。
     * 这行日志存在的意义就是给人对照，算错比不打还糟。
     */
    @Test
    void startupLog_showsFractionalRatio() {
        assertEquals("1.8", ChatSessionScheduler.heartbeatRatio());
    }
}
