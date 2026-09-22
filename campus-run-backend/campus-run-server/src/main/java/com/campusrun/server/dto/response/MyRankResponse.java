package com.campusrun.server.dto.response;

public class MyRankResponse {

    private Long rank;
    private Long distanceMeters;
    private Long total;

    public MyRankResponse() {
    }

    public MyRankResponse(Long rank, Long distanceMeters, Long total) {
        this.rank = rank;
        this.distanceMeters = distanceMeters;
        this.total = total;
    }

    public Long getRank() {
        return rank;
    }

    public void setRank(Long rank) {
        this.rank = rank;
    }

    public Long getDistanceMeters() {
        return distanceMeters;
    }

    public void setDistanceMeters(Long distanceMeters) {
        this.distanceMeters = distanceMeters;
    }

    public Long getTotal() {
        return total;
    }

    public void setTotal(Long total) {
        this.total = total;
    }
}
