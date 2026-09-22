package com.campusrun.server.cache;

import com.campusrun.server.entity.CampusFence;
import com.campusrun.server.mapper.CampusFenceMapper;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
public class FenceCache {

    private final CampusFenceMapper fenceMapper;

    private volatile List<CampusFence> cached;

    public FenceCache(CampusFenceMapper fenceMapper) {
        this.fenceMapper = fenceMapper;
    }

    public List<CampusFence> getEnabledFences() {
        List<CampusFence> result = cached;
        if (result == null) {
            synchronized (this) {
                if (cached == null) {
                    cached = fenceMapper.selectEnabled();
                }
                result = cached;
            }
        }
        return result;
    }

    public void invalidate() {
        cached = null;
    }
}
