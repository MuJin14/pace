package com.campusrun.server.util;

import com.campusrun.server.model.TrackPoint;

import java.util.List;

public final class GpsUtil {

    private static final double EARTH_RADIUS_METERS = 6_371_000.0;

    private GpsUtil() {
    }

    public static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return EARTH_RADIUS_METERS * c;
    }

    public static double totalDistanceMeters(List<TrackPoint> track) {
        if (track == null || track.size() < 2) {
            return 0.0;
        }
        double total = 0.0;
        for (int i = 1; i < track.size(); i++) {
            TrackPoint prev = track.get(i - 1);
            TrackPoint curr = track.get(i);
            total += distanceMeters(prev.getLatitude(), prev.getLongitude(),
                    curr.getLatitude(), curr.getLongitude());
        }
        return total;
    }
}
