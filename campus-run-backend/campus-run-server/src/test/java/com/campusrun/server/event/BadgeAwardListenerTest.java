package com.campusrun.server.event;

import com.campusrun.server.dto.response.BadgeResponse;
import com.campusrun.server.dto.websocket.WsMessage;
import com.campusrun.server.entity.Badge;
import com.campusrun.server.websocket.WebSocketSessionManager;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class BadgeAwardListenerTest {

    @Mock
    private WebSocketSessionManager sessionManager;

    private Badge badge() {
        Badge badge = new Badge();
        badge.setId(42L);
        badge.setCode("d_1000");
        badge.setName("千里马");
        badge.setIcon("icon.png");
        badge.setDescription("累计 1000 米");
        badge.setRuleType("total_distance");
        badge.setRuleValue(1000);
        return badge;
    }

    @Test
    void onAwarded_mapsAllFieldsAndSendsBadgeAwardedMessage() {
        BadgeAwardListener listener = new BadgeAwardListener(sessionManager);
        Long userId = 7L;

        listener.onAwarded(new BadgeAwardedEvent(userId, badge()));

        ArgumentCaptor<WsMessage> captor = ArgumentCaptor.forClass(WsMessage.class);
        verify(sessionManager).sendToUser(org.mockito.ArgumentMatchers.eq(userId), captor.capture());

        WsMessage message = captor.getValue();
        assertEquals("badge_awarded", message.getType());

        BadgeResponse response = (BadgeResponse) message.getData();
        assertEquals(42L, response.getId());
        assertEquals("d_1000", response.getCode());
        assertEquals("千里马", response.getName());
        assertEquals("icon.png", response.getIcon());
        assertEquals("累计 1000 米", response.getDescription());
        assertEquals("total_distance", response.getRuleType());
        assertEquals(1000, response.getRuleValue());
        assertTrue(response.getEarned(), "earned 应强制为 true");
        assertNull(response.getAwardedAt(), "监听器不设置 awardedAt");
    }

    @Test
    void onAwarded_withNullBadge_throwsNullPointerException() {
        BadgeAwardListener listener = new BadgeAwardListener(sessionManager);

        // 当前实现无 null 保护：badge 为 null 时 badge.getId() 直接抛 NPE。
        // 实际调用链（BadgeServiceImpl.awardEligible）始终传入非 null badge，因此业务上安全。
        assertThrows(NullPointerException.class,
                () -> listener.onAwarded(new BadgeAwardedEvent(7L, null)));
    }
}
