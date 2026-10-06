package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.entity.Activity;
import org.apache.ibatis.annotations.Select;

import java.util.List;

public interface ActivityMapper extends BaseMapper<Activity> {

    /** 全部「有过有效运动」的用户 id，用于重算连续打卡天数等聚合值。 */
    @Select("""
            SELECT DISTINCT user_id FROM activity
            WHERE invalid = 0 AND start_time IS NOT NULL
            """)
    List<Long> selectDistinctUserIdsWithValidActivity();
}
