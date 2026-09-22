package com.campusrun.server.util;

import com.campusrun.server.model.TrackPoint;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class GpsUtilTest {

    @Test
    void distanceMeters_samePoint_returnsZero() {
        assertEquals(0.0, GpsUtil.distanceMeters(39.9, 116.4, 39.9, 116.4), 0.001);
    }

    @Test
    void distanceMeters_oneDegreeLatitude_about111km() {
        double d = GpsUtil.distanceMeters(39.0, 116.0, 40.0, 116.0);
        assertEquals(111_195.0, d, 111_195.0 * 0.01);
    }

    @Test
    void totalDistance_emptyOrSingle_returnsZero() {
        assertEquals(0.0, GpsUtil.totalDistanceMeters(null), 0.001);
        assertEquals(0.0, GpsUtil.totalDistanceMeters(List.of()), 0.001);
        assertEquals(0.0, GpsUtil.totalDistanceMeters(
                List.of(new TrackPoint(39.0, 116.0, 1L, 10.0))), 0.001);
    }

    @Test
    void totalDistance_sumOfSegments() {
        List<TrackPoint> track = List.of(
                new TrackPoint(39.0, 116.0, 1L, 10.0),
                new TrackPoint(39.0, 116.001, 2L, 10.0),
                new TrackPoint(39.0, 116.002, 3L, 10.0));

        double seg1 = GpsUtil.distanceMeters(39.0, 116.0, 39.0, 116.001);
        double seg2 = GpsUtil.distanceMeters(39.0, 116.001, 39.0, 116.002);

        assertEquals(seg1 + seg2, GpsUtil.totalDistanceMeters(track), 0.001);
    }
}
