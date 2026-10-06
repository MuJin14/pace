package com.campusrun.server.websocket;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.util.concurrent.ConcurrentHashMap;

@Component
public class WebSocketSessionManager {

    private final ConcurrentHashMap<Long, WebSocketSession> sessions = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<Long, Long> lastActiveAt = new ConcurrentHashMap<>();
    private final ObjectMapper objectMapper;

    public WebSocketSessionManager(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public void addSession(Long userId, WebSocketSession session) {
        sessions.put(userId, session);
        lastActiveAt.put(userId, System.currentTimeMillis());
    }

    public void removeSession(Long userId, WebSocketSession session) {
        sessions.remove(userId, session);
        lastActiveAt.remove(userId);
    }

    public boolean isOnline(Long userId) {
        return sessions.containsKey(userId);
    }

    public boolean sendToUser(Long userId, Object payload) {
        WebSocketSession session = sessions.get(userId);
        if (session == null || !session.isOpen()) {
            return false;
        }
        try {
            String json = objectMapper.writeValueAsString(payload);
            synchronized (session) {
                session.sendMessage(new TextMessage(json));
            }
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    public void touch(Long userId) {
        lastActiveAt.put(userId, System.currentTimeMillis());
    }

    /**
     * 仅供测试：抹掉某个用户的活跃时间记录。
     *
     * <p>用来构造「有会话但没有活跃记录」这种不一致状态 ——
     * 正常路径下 {@code addSession} 一定会写入，所以只能从外部制造。
     */
    void removeActivityForTest(Long userId) {
        lastActiveAt.remove(userId);
    }

    /**
     * 清理空闲超时的会话。
     *
     * <h2>⚠️ 必须「先关、再移除」，不能只从 Map 里删掉</h2>
     *
     * 这是红点延迟问题里最关键的一处细节。
     *
     * 只做 {@code sessions.remove(...)} 的话，服务端这边**看起来**清理干净了，
     * 但客户端的 TCP 连接**没有任何变化** —— 它不会被通知、也不会触发重连。
     * 于是连接继续挂着，客户端以为「我还连着」，红点自然是旧的。
     *
     * 而 {@link #sendToUser} 是按 Map 里有没有这个人来投递的，
     * 移除之后消息就投不出去了 —— 客户端既收不到消息、也不知道要重连，
     * 只能等它自己发现（客户端当前不具备这个能力，见 ChatSessionScheduler 的说明）。
     *
     * 正确做法是先 {@code close()}：服务端发出的关闭帧会让客户端收到
     * onDone/onError，客户端随即重连并补拉未读数 —— 红点就是在这时候出现的。
     *
     * <h2>关闭状态为什么用 SESSION_NOT_RELIABLE</h2>
     *
     * 取 1002/1011 之类的状态码会让客户端日志出现「服务器错误」的噪声，
     * 而这里的语义只是「这条连接长时间没动静了，重建一条」。
     */
    public void sweep(long idleTimeoutMillis) {
        long now = System.currentTimeMillis();
        sessions.forEach((userId, session) -> {
            Long last = lastActiveAt.get(userId);
            // 没有活跃记录的也一并清理：正常情况下 addSession 会写入，
            // 缺失说明状态已经不一致了，留着只会占位并让 sendToUser 误判在线。
            if (last == null || now - last > idleTimeoutMillis) {
                closeAndRemove(userId, session);
            }
        });
    }

    /**
     * 关闭并移除一个会话。
     *
     * <p>关闭失败也照样移除：{@code close()} 抛异常（对端已断）恰恰说明
     * 这条连接没用了，此时更需要把 Map 里的引用清掉，否则后续
     * {@link #sendToUser} 会一直往一个死连接上写。
     */
    private void closeAndRemove(Long userId, WebSocketSession session) {
        try {
            if (session.isOpen()) {
                session.close(CloseStatus.SESSION_NOT_RELIABLE);
            }
        } catch (Exception ignored) {
            // 对端已经断了 —— 正是我们要清理的情况
        }
        sessions.remove(userId, session);
        lastActiveAt.remove(userId);
    }
}
