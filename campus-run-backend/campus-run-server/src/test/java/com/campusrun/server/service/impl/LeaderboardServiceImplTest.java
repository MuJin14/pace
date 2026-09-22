package com.campusrun.server.service.impl;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.request.ActivityCreateRequest;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.request.TrackPointRequest;
import com.campusrun.server.dto.response.ActivityCreateResponse;
import com.campusrun.server.dto.response.LeaderboardEntryResponse;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.dto.response.MyRankResponse;
import com.campusrun.server.entity.Activity;
import com.campusrun.server.entity.LeaderboardStat;
import com.campusrun.server.mapper.ActivityMapper;
import com.campusrun.server.mapper.LeaderboardMapper;
import com.campusrun.server.service.ActivityService;
import com.campusrun.server.service.AuthService;
import com.campusrun.server.service.LeaderboardService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

@SpringBootTest
@ActiveProfiles("test")
@Transactional
class LeaderboardServiceImplTest {

    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private static final long BASE = 1_700_000_000_000L;

    @Autowired
    private LeaderboardService leaderboardService;

    @Autowired
    private AuthService authService;

    @Autowired
    private ActivityService activityService;

    @Autowired
    private LeaderboardMapper leaderboardMapper;

    @Autowired
    private ActivityMapper activityMapper;

    private Long registerUser(String phone) {
        RegisterRequest req = new RegisterRequest();
        req.setPhone(phone);
        req.setPassword("secret123");
        req.setNickname("跑者" + phone.substring(phone.length() - 4));
        LoginResponse resp = authService.register(req);
        return resp.getUserId();
    }

    private void insertActivity(Long userId, int type, int distanceMeters, LocalDateTime startTime) {
        Activity a = new Activity();
        a.setUserId(userId);
        a.setType(type);
        a.setDistanceMeters(distanceMeters);
        a.setDurationSeconds(0);
        a.setStartTime(startTime);
        a.setEndTime(startTime.plusMinutes(1));
        activityMapper.insert(a);
    }

    private void insertStat(Long userId, String scope, String period, int type, int distance) {
        LeaderboardStat s = new LeaderboardStat();
        s.setUserId(userId);
        s.setScope(scope);
        s.setPeriod(period);
        s.setType(type);
        s.setDistanceMeters(distance);
        leaderboardMapper.insert(s);
    }

    private TrackPointRequest point(double lat, double lng, long ts) {
        TrackPointRequest p = new TrackPointRequest();
        p.setLatitude(lat);
        p.setLongitude(lng);
        p.setTimestamp(ts);
        p.setAccuracy(10.0);
        return p;
    }

    private List<TrackPointRequest> line(int count, long startTs, long stepMs) {
        List<TrackPointRequest> track = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            track.add(point(39.0, 116.0 + i * 0.001, startTs + i * stepMs));
        }
        return track;
    }

    private ActivityCreateRequest request(Integer type, long start, long end, List<TrackPointRequest> track) {
        ActivityCreateRequest r = new ActivityCreateRequest();
        r.setType(type);
        r.setStartTime(start);
        r.setEndTime(end);
        r.setTrack(track);
        return r;
    }

    @Test
    void recordActivity_writesThreeScopes() {
        Long userId = registerUser("13910000001");
        LocalDateTime t = LocalDateTime.of(2026, 9, 22, 8, 0);
        String weekly = t.toLocalDate().with(DayOfWeek.MONDAY).toString();

        leaderboardService.recordActivity(userId, 5000, t, 1);

        assertEquals(1, leaderboardMapper.countBoard("daily", "2026-09-22", 1));
        assertEquals(1, leaderboardMapper.countBoard("weekly", weekly, 1));
        assertEquals(1, leaderboardMapper.countBoard("monthly", "2026-09", 1));
        assertEquals(0, leaderboardMapper.countBoard("daily", "2026-09-22", 2));
        assertEquals(5000, leaderboardMapper.selectDistance("daily", "2026-09-22", 1, userId));
    }

    @Test
    void recordActivity_accumulatesSameDay() {
        Long userId = registerUser("13910000002");
        LocalDateTime t = LocalDateTime.of(2026, 9, 22, 8, 0);

        leaderboardService.recordActivity(userId, 3000, t, 1);
        leaderboardService.recordActivity(userId, 2000, t, 1);

        assertEquals(1, leaderboardMapper.countBoard("daily", "2026-09-22", 1));
        assertEquals(5000, leaderboardMapper.selectDistance("daily", "2026-09-22", 1, userId));
    }

    @Test
    void recordActivity_separatesByPeriod() {
        Long userId = registerUser("13910000003");
        LocalDateTime sep1 = LocalDateTime.of(2026, 9, 1, 8, 0);
        LocalDateTime oct5 = LocalDateTime.of(2026, 10, 5, 8, 0);

        leaderboardService.recordActivity(userId, 1000, sep1, 1);
        leaderboardService.recordActivity(userId, 2000, oct5, 1);

        assertEquals(1000, leaderboardMapper.selectDistance("daily", "2026-09-01", 1, userId));
        assertEquals(2000, leaderboardMapper.selectDistance("daily", "2026-10-05", 1, userId));
        assertEquals(1000, leaderboardMapper.selectDistance("monthly", "2026-09", 1, userId));
        assertEquals(2000, leaderboardMapper.selectDistance("monthly", "2026-10", 1, userId));

        String weekSep = sep1.toLocalDate().with(DayOfWeek.MONDAY).toString();
        String weekOct = oct5.toLocalDate().with(DayOfWeek.MONDAY).toString();
        assertNotEquals(weekSep, weekOct);
        assertEquals(1000, leaderboardMapper.selectDistance("weekly", weekSep, 1, userId));
        assertEquals(2000, leaderboardMapper.selectDistance("weekly", weekOct, 1, userId));
    }

    @Test
    void recordActivity_separatesByType() {
        Long userId = registerUser("13910000004");
        LocalDateTime t = LocalDateTime.of(2026, 9, 22, 8, 0);

        leaderboardService.recordActivity(userId, 1000, t, 1);
        leaderboardService.recordActivity(userId, 2000, t, 2);

        assertEquals(1000, leaderboardMapper.selectDistance("daily", "2026-09-22", 1, userId));
        assertEquals(2000, leaderboardMapper.selectDistance("daily", "2026-09-22", 2, userId));
        assertEquals(1, leaderboardMapper.countBoard("daily", "2026-09-22", 1));
        assertEquals(1, leaderboardMapper.countBoard("daily", "2026-09-22", 2));
    }

    @Test
    void create_activityUpdatesLeaderboard() {
        Long userId = registerUser("13910000005");
        List<TrackPointRequest> track = line(3, BASE, 60_000L);
        ActivityCreateResponse resp = activityService.create(userId, request(1, BASE, BASE + 120_000L, track));

        String dailyPeriod = resp.getStartTime().toLocalDate().toString();
        String weeklyPeriod = resp.getStartTime().toLocalDate().with(DayOfWeek.MONDAY).toString();

        assertEquals(resp.getDistanceMeters(), leaderboardMapper.selectDistance("daily", dailyPeriod, 1, userId));
        assertEquals(resp.getDistanceMeters(), leaderboardMapper.selectDistance("weekly", weeklyPeriod, 1, userId));
    }

    @Test
    void getBoard_ordersByDistanceDescWithRank() {
        Long a = registerUser("13910000006");
        Long b = registerUser("13910000007");
        Long c = registerUser("13910000008");
        LocalDateTime t = LocalDateTime.of(2026, 9, 22, 8, 0);

        leaderboardService.recordActivity(a, 1000, t, 1);
        leaderboardService.recordActivity(b, 3000, t, 1);
        leaderboardService.recordActivity(c, 2000, t, 1);

        PageResponse<LeaderboardEntryResponse> board =
                leaderboardService.getBoard("daily", "2026-09-22", 1, 1, 20);
        List<LeaderboardEntryResponse> list = board.getList();
        assertEquals(3, board.getTotal());
        assertEquals(3, list.size());
        assertEquals(1L, list.get(0).getRank());
        assertEquals(b, list.get(0).getUserId());
        assertEquals(3000, list.get(0).getDistanceMeters());
        assertEquals(2L, list.get(1).getRank());
        assertEquals(c, list.get(1).getUserId());
        assertEquals(3L, list.get(2).getRank());
        assertEquals(a, list.get(2).getUserId());
        assertNotNull(list.get(0).getNickname());
        assertNotNull(list.get(0).getUniqueId());
    }

    @Test
    void getBoard_paginationWithRankOffset() {
        LocalDateTime t = LocalDateTime.of(2026, 9, 22, 8, 0);
        for (int i = 1; i <= 25; i++) {
            Long u = registerUser(String.format("1392%07d", i));
            leaderboardService.recordActivity(u, i * 1000, t, 1);
        }

        PageResponse<LeaderboardEntryResponse> page2 =
                leaderboardService.getBoard("daily", "2026-09-22", 1, 2, 10);
        assertEquals(25, page2.getTotal());
        assertEquals(10, page2.getList().size());
        assertEquals(11L, page2.getList().get(0).getRank());
        assertEquals(15000, page2.getList().get(0).getDistanceMeters());
        assertEquals(20L, page2.getList().get(9).getRank());
        assertEquals(6000, page2.getList().get(9).getDistanceMeters());
    }

    @Test
    void getBoard_invalidScope_throws() {
        BusinessException e = assertThrows(BusinessException.class,
                () -> leaderboardService.getBoard("bogus", null, 1, 1, 20));
        assertEquals(ErrorCode.PARAM_ERROR.getCode(), e.getCode());
    }

    @Test
    void getBoard_invalidType_throws() {
        assertThrows(BusinessException.class,
                () -> leaderboardService.getBoard("daily", "2026-09-22", 3, 1, 20));
        assertThrows(BusinessException.class,
                () -> leaderboardService.getBoard("daily", "2026-09-22", null, 1, 20));
    }

    @Test
    void getBoard_defaultPeriod_resolvesCurrent() {
        Long u = registerUser("13930000001");
        LocalDate today = LocalDate.now(ZONE);
        leaderboardService.recordActivity(u, 1000, today.atTime(8, 0), 1);

        assertEquals(1, leaderboardService.getBoard("daily", null, 1, 1, 20).getTotal());
        assertEquals(1, leaderboardService.getBoard("weekly", null, 1, 1, 20).getTotal());
        assertEquals(1, leaderboardService.getBoard("monthly", null, 1, 1, 20).getTotal());
    }

    @Test
    void getMyRank_returnsCorrectRank() {
        Long a = registerUser("13910000009");
        Long b = registerUser("13910000010");
        Long c = registerUser("13910000011");
        LocalDateTime t = LocalDateTime.of(2026, 9, 22, 8, 0);

        leaderboardService.recordActivity(a, 1000, t, 1);
        leaderboardService.recordActivity(b, 3000, t, 1);
        leaderboardService.recordActivity(c, 2000, t, 1);

        MyRankResponse my = leaderboardService.getMyRank("daily", "2026-09-22", 1, b);
        assertEquals(1L, my.getRank());
        assertEquals(3000L, my.getDistanceMeters());
        assertEquals(3L, my.getTotal());
    }

    @Test
    void getMyRank_notOnBoard_returnsNullRank() {
        Long a = registerUser("13910000012");
        Long b = registerUser("13910000013");
        LocalDateTime t = LocalDateTime.of(2026, 9, 22, 8, 0);

        leaderboardService.recordActivity(a, 1000, t, 1);

        MyRankResponse my = leaderboardService.getMyRank("daily", "2026-09-22", 1, b);
        assertNull(my.getRank());
        assertEquals(0L, my.getDistanceMeters());
        assertEquals(1L, my.getTotal());
    }

    @Test
    void rebuildRolling30d_sumsOnlyLast30Days() {
        LocalDate today = LocalDate.now(ZONE);
        Long recentUser = registerUser("13940000001");
        Long oldUser = registerUser("13940000002");

        insertActivity(recentUser, 1, 5000, today.minusDays(5).atTime(8, 0));
        insertActivity(recentUser, 1, 3000, today.minusDays(2).atTime(8, 0));
        insertActivity(oldUser, 1, 9999, today.minusDays(40).atTime(8, 0));

        leaderboardService.rebuildRolling30d();

        PageResponse<LeaderboardEntryResponse> board =
                leaderboardService.getBoard("rolling30d", null, 1, 1, 20);
        assertEquals(1, board.getTotal());
        LeaderboardEntryResponse entry = board.getList().get(0);
        assertEquals(recentUser, entry.getUserId());
        assertEquals(8000, entry.getDistanceMeters());
    }

    @Test
    void cleanupExpired_removesOldRows() {
        LocalDate today = LocalDate.now(ZONE);
        Long u = registerUser("13940000003");

        String weekStart = today.with(DayOfWeek.MONDAY).toString();
        String oldWeek = today.minusWeeks(20).with(DayOfWeek.MONDAY).toString();
        String thisMonth = YearMonth.now(ZONE).toString();
        String oldMonth = YearMonth.now(ZONE).minusMonths(20).toString();

        insertStat(u, "daily", today.toString(), 1, 1000);
        insertStat(u, "daily", today.minusDays(40).toString(), 1, 2000);
        insertStat(u, "weekly", weekStart, 1, 3000);
        insertStat(u, "weekly", oldWeek, 1, 4000);
        insertStat(u, "monthly", thisMonth, 1, 5000);
        insertStat(u, "monthly", oldMonth, 1, 6000);

        leaderboardService.cleanupExpired();

        assertEquals(1, leaderboardMapper.countBoard("daily", today.toString(), 1));
        assertEquals(0, leaderboardMapper.countBoard("daily", today.minusDays(40).toString(), 1));
        assertEquals(1, leaderboardMapper.countBoard("weekly", weekStart, 1));
        assertEquals(0, leaderboardMapper.countBoard("weekly", oldWeek, 1));
        assertEquals(1, leaderboardMapper.countBoard("monthly", thisMonth, 1));
        assertEquals(0, leaderboardMapper.countBoard("monthly", oldMonth, 1));
    }
}
