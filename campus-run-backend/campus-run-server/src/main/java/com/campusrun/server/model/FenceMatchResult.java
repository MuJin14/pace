package com.campusrun.server.model;

import java.math.BigDecimal;

public record FenceMatchResult(Long fenceId, BigDecimal outsideRatio, boolean invalid) {

    public static FenceMatchResult valid(Long fenceId, BigDecimal outsideRatio) {
        return new FenceMatchResult(fenceId, outsideRatio, false);
    }

    public static FenceMatchResult invalid(BigDecimal outsideRatio) {
        return new FenceMatchResult(null, outsideRatio, true);
    }
}
