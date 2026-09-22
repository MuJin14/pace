package com.campusrun.server.service.impl;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.request.ActivityCreateRequest;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.request.TrackPointRequest;
import com.campusrun.server.dto.response.ActivityCreateResponse;
import com.campusrun.server.dto.response.ActivityDetailResponse;
import com.campusrun.server.dto.response.ActivitySummaryResponse;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.entity.Activity;
import com.campusrun.server.mapper.ActivityMapper;
import com.campusrun.server.service.ActivityService;
import com.campusrun.server.service.AuthService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
@ActiveProfiles("test")
@Transactional
class ActivityServiceImplTest {

    private static final long BASE = 1_700_000_000_000L;

    @Autowired
    private ActivityService activityService;

    @Autowired
    private AuthService authService;

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
    void create_persistsAndComputesDistance() {
        Long userId = registerUser("13900000001");
        List<TrackPointRequest> track = line(3, BASE, 60_000L);
        ActivityCreateRequest req = request(1, BASE, BASE + 120_000L, track);

        ActivityCreateResponse resp = activityService.create(userId, req);

        assertNotNull(resp.getActivityId());
        assertTrue(resp.getDistanceMeters() > 0);
        assertEquals(120, resp.getDurationSeconds());
        assertNotNull(resp.getAvgSpeed());
        assertTrue(resp.getAvgSpeed().doubleValue() > 0);

        Activity saved = activityMapper.selectById(resp.getActivityId());
        assertNotNull(saved);
        assertEquals(userId, saved.getUserId());
        assertNotNull(saved.getTrackJson());
        assertTrue(saved.getTrackJson().contains("latitude"));
    }

    @Test
    void create_trackTooFewPoints_throws() {
        Long userId = registerUser("13900000002");
        ActivityCreateRequest req = request(1, BASE, BASE + 60_000L,
                List.of(point(39.0, 116.0, BASE)));

        assertThrows(BusinessException.class, () -> activityService.create(userId, req));
    }

    @Test
    void create_endTimeBeforeStart_throws() {
        Long userId = registerUser("13900000003");
        ActivityCreateRequest req = request(1, BASE, BASE - 1L, line(3, BASE, 60_000L));

        assertThrows(BusinessException.class, () -> activityService.create(userId, req));
    }

    @Test
    void create_zeroDistance_throws() {
        Long userId = registerUser("13900000004");
        List<TrackPointRequest> track = List.of(
                point(39.0, 116.0, BASE),
                point(39.0, 116.0, BASE + 60_000L),
                point(39.0, 116.0, BASE + 120_000L));
        ActivityCreateRequest req = request(1, BASE, BASE + 120_000L, track);

        assertThrows(BusinessException.class, () -> activityService.create(userId, req));
    }

    @Test
    void page_returnsOnlyOwnRecords() {
        Long a = registerUser("13900000005");
        Long b = registerUser("13900000006");

        activityService.create(a, request(1, BASE, BASE + 60_000L, line(3, BASE, 30_000L)));
        activityService.create(a, request(1, BASE + 60_000L, BASE + 120_000L, line(3, BASE + 60_000L, 30_000L)));
        activityService.create(b, request(1, BASE, BASE + 60_000L, line(3, BASE, 30_000L)));

        PageResponse<ActivitySummaryResponse> pageA = activityService.page(a, null, 1, 20);
        assertEquals(2, pageA.getTotal());
        assertEquals(2, pageA.getList().size());
    }

    @Test
    void page_filterByType() {
        Long a = registerUser("13900000007");

        activityService.create(a, request(1, BASE, BASE + 60_000L, line(3, BASE, 30_000L)));
        activityService.create(a, request(2, BASE, BASE + 60_000L, line(3, BASE, 30_000L)));

        PageResponse<ActivitySummaryResponse> running = activityService.page(a, 1, 1, 20);
        assertEquals(1, running.getTotal());
        assertEquals(1, running.getList().get(0).getType());
    }

    @Test
    void page_orderByStartTimeDesc() {
        Long a = registerUser("13900000008");

        activityService.create(a, request(1, BASE, BASE + 60_000L, line(3, BASE, 30_000L)));
        activityService.create(a, request(1, BASE + 1_000_000L, BASE + 1_060_000L, line(3, BASE + 1_000_000L, 30_000L)));
        activityService.create(a, request(1, BASE + 2_000_000L, BASE + 2_060_000L, line(3, BASE + 2_000_000L, 30_000L)));

        PageResponse<ActivitySummaryResponse> page = activityService.page(a, null, 1, 20);
        List<ActivitySummaryResponse> list = page.getList();
        assertEquals(3, list.size());
        assertTrue(list.get(0).getStartTime().isAfter(list.get(1).getStartTime()));
        assertTrue(list.get(1).getStartTime().isAfter(list.get(2).getStartTime()));
    }

    @Test
    void page_pagination() {
        Long a = registerUser("13900000009");

        for (int i = 0; i < 25; i++) {
            long s = BASE + i * 1_000_000L;
            activityService.create(a, request(1, s, s + 60_000L, line(3, s, 30_000L)));
        }

        PageResponse<ActivitySummaryResponse> page1 = activityService.page(a, null, 1, 10);
        assertEquals(25, page1.getTotal());
        assertEquals(10, page1.getList().size());

        PageResponse<ActivitySummaryResponse> page3 = activityService.page(a, null, 3, 10);
        assertEquals(25, page3.getTotal());
        assertEquals(5, page3.getList().size());
    }

    @Test
    void getDetail_owner_returnsParsedTrack() {
        Long a = registerUser("13900000010");

        ActivityCreateResponse created =
                activityService.create(a, request(1, BASE, BASE + 120_000L, line(3, BASE, 60_000L)));

        ActivityDetailResponse detail = activityService.getDetail(a, created.getActivityId());
        assertNotNull(detail.getTrack());
        assertEquals(3, detail.getTrack().size());
        assertEquals(created.getDistanceMeters(), detail.getDistanceMeters());
    }

    @Test
    void getDetail_notOwner_throwsForbidden() {
        Long a = registerUser("13900000011");
        Long b = registerUser("13900000012");

        ActivityCreateResponse created =
                activityService.create(a, request(1, BASE, BASE + 60_000L, line(3, BASE, 30_000L)));

        BusinessException e = assertThrows(BusinessException.class,
                () -> activityService.getDetail(b, created.getActivityId()));
        assertEquals(ErrorCode.ACTIVITY_FORBIDDEN.getCode(), e.getCode());
    }

    @Test
    void getDetail_notFound_throws() {
        Long a = registerUser("13900000013");

        BusinessException e = assertThrows(BusinessException.class,
                () -> activityService.getDetail(a, 999_999_999L));
        assertEquals(ErrorCode.ACTIVITY_NOT_FOUND.getCode(), e.getCode());
    }
}
