package com.campusrun.server.task;

import com.campusrun.server.websocket.WebSocketSessionManager;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 回收「已经不在了」的 WebSocket 会话。
 *
 * <h2>为什么这个任务决定了「红点什么时候出现」</h2>
 *
 * 客户端在这条链路上有一个**结构性缺陷**（当前不便发新版修复，故在服务端补偿）：
 *
 * <ol>
 *   <li>它的心跳只负责「发」、**不校验响应** —— socket 半死时写入本地缓冲区
 *       并不抛错，于是客户端**根本不知道连接断了**；</li>
 *   <li>它只在 {@code onDone} / {@code onError} 时才把自己置为「未连接」，
 *       而「回前台」的分支只看「连接对象是否存在」—— 对象还在就不重连，
 *       于是半死连接可以一直挂着。</li>
 * </ol>
 *
 * 结果：服务端这边**唯一**能清掉僵尸会话、逼客户端重连的机制就是本 sweep；
 * 而红点正是靠「重连后补拉未读数」才出现的 ——
 * 所以 sweep 有多快，用户看到的红点就有多快。
 *
 * <h2>原来的值为什么太长</h2>
 *
 * 原先是 {@code IDLE=90s} + {@code 每 60s 扫一次}：最坏 150 秒、平均约 75 秒。
 * 用户反馈「消息到了，红点过了一分钟才出来」，与这个量级完全吻合。
 *
 * <h2>现在为什么是这两个数</h2>
 *
 * <ul>
 *   <li>{@code IDLE=45s}：客户端心跳间隔 25 秒，这里要留足余量。
 *       45/25 = 1.8 倍，允许一次心跳丢失（网络抖动、系统调度延迟）
 *       而**不会误杀健康连接**。压到 25~30 秒会变成「心跳稍慢就被踢」，
 *       反而导致反复重连，比慢一点更糟。</li>
 *   <li>{@code 每 15s 扫一次}：扫描只是遍历一个很小的 Map，代价可忽略；
 *       缩短它只是为了让「判定超时 → 真正清理」的等待变短。</li>
 * </ul>
 *
 * 合起来：最坏 60 秒、平均约 37 秒，比原来快一半以上。
 *
 * <h2>这条路的极限</h2>
 *
 * 纯服务端做不到「秒级」。要更快只有两个办法，都需要改客户端：
 *   · 心跳校验响应（收到 pong 才算活着），超时主动重连；
 *   · 回前台时无条件重建连接（而不是看连接对象是否存在）。
 *
 * ⚠️ 这两个数**不要低于客户端心跳间隔的 1.5 倍**。改之前先确认
 * {@code global_ws_provider.dart} 里的 {@code _startHeartbeat} 周期
 * （当前 25 秒）。
 */
@Component
@Profile("!test")
public class ChatSessionScheduler {

    /**
     * 判定「空闲」的阈值。
     *
     * <p>客户端每 25 秒发一次心跳，每次心跳都会 {@code touch()} 刷新活跃时间，
     * 所以只要客户端还活着，这个值不会被触发。
     *
     * <p>包可见是为了让测试能断言「与心跳间隔的倍数关系」——
     * 改错了值会让生产环境变成反复重连，那种问题很难从现象上归因。
     */
    static final long IDLE_TIMEOUT_MILLIS = 45_000L;

    /** 扫描间隔。只影响「超时判定」到「真正清理」之间的延迟。 */
    static final long SWEEP_INTERVAL_MILLIS = 15_000L;

    private static final Logger log = LoggerFactory.getLogger(ChatSessionScheduler.class);

    /**
     * 启动时把参数打进日志。
     *
     * <p>为什么要专门打这一行：这两个值的效果**只在用户端可见**（红点快慢），
     * 服务端一切正常、也不报错。没有这行日志的话，「改动到底生效了没有」
     * 只能靠翻 jar 或反编译来确认 —— 排查一次的成本很高。
     *
     * <p>更重要的是它顺便把「依赖关系」写进了运行日志：空闲阈值必须
     * 大于客户端心跳间隔，看到这行就能立刻对照。
     */
    @PostConstruct
    public void logConfiguration() {
        log.info("WebSocket 空闲会话回收: 阈值 {}s, 扫描间隔 {}s "
                        + "(客户端心跳 {}s, 倍数 {})",
                IDLE_TIMEOUT_MILLIS / 1000,
                SWEEP_INTERVAL_MILLIS / 1000,
                CLIENT_HEARTBEAT_INTERVAL_MILLIS / 1000,
                heartbeatRatio());
    }

    /**
     * 空闲阈值相对客户端心跳间隔的倍数，保留一位小数。
     *
     * <p>⚠️ 必须用浮点除法：整数除法会把 45/25 = 1.8 算成 1，
     * 而「倍数 1」读起来像是阈值等于心跳间隔（必然误杀健康连接）。
     * 这行日志是给人对照用的，算错比不打还糟。
     *
     * <p>提成独立方法是为了让测试断言**真正被打印出来的那个值**，
     * 而不是在测试里重算一遍（那只能证明测试算得对）。
     */
    static String heartbeatRatio() {
        return String.format("%.1f",
                (double) IDLE_TIMEOUT_MILLIS / CLIENT_HEARTBEAT_INTERVAL_MILLIS);
    }

    /**
     * 客户端的心跳间隔（毫秒）。**仅用于测试断言两者的倍数关系**，
     * 不参与运行时逻辑 —— 真正的值在 App 侧的
     * {@code lib/core/ws/global_ws_provider.dart} 的 {@code _startHeartbeat}。
     */
    static final long CLIENT_HEARTBEAT_INTERVAL_MILLIS = 25_000L;

    private final WebSocketSessionManager sessionManager;

    public ChatSessionScheduler(WebSocketSessionManager sessionManager) {
        this.sessionManager = sessionManager;
    }

    @Scheduled(fixedDelay = SWEEP_INTERVAL_MILLIS)
    public void sweepIdleSessions() {
        sessionManager.sweep(IDLE_TIMEOUT_MILLIS);
    }
}
