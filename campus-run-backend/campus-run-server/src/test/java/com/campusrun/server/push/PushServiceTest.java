package com.campusrun.server.push;

import com.campusrun.server.entity.DeviceToken;
import com.campusrun.server.entity.User;
import com.campusrun.server.mapper.DeviceTokenMapper;
import com.campusrun.server.mapper.UserMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 离线推送的核心行为。
 *
 * <p>重点不是「能发出去」，而是几个容易出错的边界：
 * <ol>
 *   <li>**令牌失效要清理**，否则每次发消息都白推一次；</li>
 *   <li>**临时故障不能删令牌**，删了用户永远收不到通知；</li>
 *   <li>推送异常**不能影响消息发送**（消息已落库）；</li>
 *   <li>多设备都要推，不能只推最后一个。</li>
 * </ol>
 */
@ExtendWith(MockitoExtension.class)
class PushServiceTest {

    @Mock
    private DeviceTokenMapper deviceTokenMapper;
    @Mock
    private UserMapper userMapper;
    @Mock
    private PushSender pushSender;

    private PushService pushService;

    @BeforeEach
    void setUp() {
        pushService = new PushService(deviceTokenMapper, userMapper, pushSender);
    }

    private DeviceToken device(String token) {
        DeviceToken d = new DeviceToken();
        d.setToken(token);
        d.setUserId(2L);
        d.setPlatform("android");
        return d;
    }

    @Test
    @DisplayName("给收件人的每台设备都推一次")
    void pushesToAllDevices() {
        when(deviceTokenMapper.selectByUserId(2L))
                .thenReturn(List.of(device("tok-a"), device("tok-b")));
        when(pushSender.send(anyString(), anyString(), anyString(), any())).thenReturn(PushSender.Result.SUCCESS);

        pushService.pushMessage(2L, "TesterB", "在吗", 77L);

        verify(pushSender).send(eq("tok-a"), eq("TesterB"), eq("在吗"), any());
        verify(pushSender).send(eq("tok-b"), eq("TesterB"), eq("在吗"), any());
    }

    @Test
    @DisplayName("标题用发件人昵称；昵称为空时兜底为「新消息」")
    void titleUsesSenderNickname() {
        when(deviceTokenMapper.selectByUserId(2L)).thenReturn(List.of(device("t")));
        when(pushSender.send(anyString(), anyString(), anyString(), any())).thenReturn(PushSender.Result.SUCCESS);

        pushService.pushMessage(2L, "沐瑾", "hi", 1L);
        verify(pushSender).send(eq("t"), eq("沐瑾"), eq("hi"), any());

        pushService.pushMessage(2L, "   ", "hi", 1L);
        verify(pushSender).send(eq("t"), eq("新消息"), eq("hi"), any());
    }

    @Test
    @DisplayName("data 里带路由与消息 id，供客户端点击后跳转（值必须是字符串）")
    void dataCarriesRouteAndMessageId() {
        when(deviceTokenMapper.selectByUserId(2L)).thenReturn(List.of(device("t")));
        when(pushSender.send(anyString(), anyString(), anyString(), any())).thenReturn(PushSender.Result.SUCCESS);

        pushService.pushMessage(2L, "沐瑾", "hi", 99L);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, String>> captor = ArgumentCaptor.forClass(Map.class);
        verify(pushSender).send(eq("t"), anyString(), anyString(), captor.capture());
        assertEquals("/friends", captor.getValue().get("route"));
        assertEquals("99", captor.getValue().get("messageId"));
        assertTrue(captor.getValue().values().stream().allMatch(v -> v instanceof String),
                "FCM 的 data 值必须全是字符串，否则请求会被拒");
    }

    @Test
    @DisplayName("令牌失效 → 删除该令牌（避免每次白推）")
    void invalidTokenIsRemoved() {
        when(deviceTokenMapper.selectByUserId(2L)).thenReturn(List.of(device("dead")));
        when(pushSender.send(anyString(), anyString(), anyString(), any()))
                .thenReturn(PushSender.Result.INVALID_TOKEN);

        pushService.pushMessage(2L, "沐瑾", "hi", 1L);

        verify(deviceTokenMapper).deleteByToken("dead");
    }

    @Test
    @DisplayName("临时故障 → 保留令牌（删了用户就永远收不到通知）")
    void retryableFailureKeepsToken() {
        when(deviceTokenMapper.selectByUserId(2L)).thenReturn(List.of(device("flaky")));
        when(pushSender.send(anyString(), anyString(), anyString(), any()))
                .thenReturn(PushSender.Result.RETRYABLE_FAILURE);

        pushService.pushMessage(2L, "沐瑾", "hi", 1L);

        verify(deviceTokenMapper, never()).deleteByToken(anyString());
    }

    @Test
    @DisplayName("未配置凭证（开发模式）不报错、不删令牌")
    void notConfiguredIsHarmless() {
        when(deviceTokenMapper.selectByUserId(2L)).thenReturn(List.of(device("dev")));
        when(pushSender.send(anyString(), anyString(), anyString(), any()))
                .thenReturn(PushSender.Result.NOT_CONFIGURED);

        pushService.pushMessage(2L, "沐瑾", "hi", 1L);

        verify(deviceTokenMapper, never()).deleteByToken(anyString());
    }

    @Test
    @DisplayName("推送过程抛异常不影响调用方（消息已落库，推送只是增强）")
    void exceptionIsSwallowed() {
        when(deviceTokenMapper.selectByUserId(2L)).thenThrow(new RuntimeException("db down"));

        // 不应抛出
        pushService.pushMessage(2L, "沐瑾", "hi", 1L);

        verify(pushSender, never()).send(anyString(), anyString(), anyString(), any());
    }

    @Test
    @DisplayName("没有登记设备时直接返回，不调用推送")
    void noDevicesSkips() {
        when(deviceTokenMapper.selectByUserId(2L)).thenReturn(List.of());

        pushService.pushMessage(2L, "沐瑾", "hi", 1L);

        verify(pushSender, never()).send(anyString(), anyString(), anyString(), any());
    }

    @Test
    @DisplayName("超长正文按码点截断，不产生半个 emoji")
    void previewTruncatesByCodePoint() {
        when(deviceTokenMapper.selectByUserId(2L)).thenReturn(List.of(device("t")));
        when(pushSender.send(anyString(), anyString(), anyString(), any())).thenReturn(PushSender.Result.SUCCESS);

        // 60 个 emoji（每个占 2 个 UTF-16 char，1 个码点）+ 中文
        // 总码点 63 > 50，必须截断；若实现按 UTF-16 长度切就会切出半个 emoji
        String content = "🏃".repeat(60) + "跑完了";
        pushService.pushMessage(2L, "沐瑾", content, 1L);

        ArgumentCaptor<String> body = ArgumentCaptor.forClass(String.class);
        verify(pushSender).send(eq("t"), anyString(), body.capture(), any());
        String preview = body.getValue();
        assertTrue(preview.endsWith("…"), "应被截断: " + preview);
        // 不含「孤立代理对」（半个 emoji）
        for (int i = 0; i < preview.length(); i++) {
            char c = preview.charAt(i);
            if (Character.isHighSurrogate(c)) {
                assertTrue(i + 1 < preview.length() && Character.isLowSurrogate(preview.charAt(i + 1)),
                        "截断产生了半个 emoji");
                i++;
            } else {
                assertTrue(!Character.isLowSurrogate(c), "截断产生了半个 emoji");
            }
        }
    }

    @Test
    @DisplayName("登记设备令牌会写入归属，登出按令牌删除")
    void registerAndUnregister() {
        pushService.register(5L, "tok-x", "ios");
        verify(deviceTokenMapper).upsert(5L, "tok-x", "ios");

        // platform 为空按 android 兜底
        pushService.register(5L, "tok-y", null);
        verify(deviceTokenMapper).upsert(5L, "tok-y", "android");

        pushService.unregister("tok-x");
        verify(deviceTokenMapper).deleteByToken("tok-x");

        // 空令牌不应产生删除调用
        pushService.unregister("  ");
        verify(deviceTokenMapper, times(1)).deleteByToken(anyString());
    }

    @Test
    @DisplayName("nicknameOf 取不到用户时返回 null，由调用方兜底")
    void nicknameOfMissingUser() {
        when(userMapper.selectById(9L)).thenReturn(null);
        assertEquals(null, pushService.nicknameOf(9L));

        User u = new User();
        u.setId(9L);
        u.setNickname("沐瑾");
        when(userMapper.selectById(9L)).thenReturn(u);
        assertEquals("沐瑾", pushService.nicknameOf(9L));
    }
}
