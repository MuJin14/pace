package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.entity.CampusFence;
import org.apache.ibatis.annotations.Select;

import java.util.List;

public interface CampusFenceMapper extends BaseMapper<CampusFence> {

    @Select("SELECT * FROM campus_fence WHERE enabled = 1")
    List<CampusFence> selectEnabled();
}
