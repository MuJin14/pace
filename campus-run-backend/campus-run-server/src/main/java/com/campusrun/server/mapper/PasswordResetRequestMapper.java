package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.entity.PasswordResetRequest;
import org.apache.ibatis.annotations.Mapper;

/**
 * 密码重置申请。
 *
 * <p>查询都用 MyBatis-Plus 的条件构造器（`selectPage` / `selectCount`），
 * 不需要自定义 SQL —— 表结构简单，条件也简单。
 */
@Mapper
public interface PasswordResetRequestMapper extends BaseMapper<PasswordResetRequest> {
}
