package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.entity.DeviceToken;
import org.apache.ibatis.annotations.Delete;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;

public interface DeviceTokenMapper extends BaseMapper<DeviceToken> {

    /**
     * 注册（或改归属）一个设备令牌。
     *
     * <p>用 ON DUPLICATE KEY UPDATE 而不是先查后插：
     * <ol>
     *   <li>并发下「先查后插」会撞唯一键；</li>
     *   <li>令牌复用是真实存在的（同一个人换账号登录同一台手机，
     *       FCM 令牌不变），必须把归属改到新用户，否则通知会推错人。</li>
     * </ol>
     */
    @Insert("""
            INSERT INTO device_token (user_id, token, platform, created_at, updated_at)
            VALUES (#{userId}, #{token}, #{platform}, NOW(), NOW())
            ON DUPLICATE KEY UPDATE
                user_id = VALUES(user_id),
                platform = VALUES(platform),
                updated_at = NOW()
            """)
    int upsert(@Param("userId") long userId,
               @Param("token") String token,
               @Param("platform") String platform);

    @Select("SELECT * FROM device_token WHERE user_id = #{userId}")
    List<DeviceToken> selectByUserId(@Param("userId") long userId);

    /** 推送失败（令牌失效）时清理，避免每次都白推一遍。 */
    @Delete("DELETE FROM device_token WHERE token = #{token}")
    int deleteByToken(@Param("token") String token);

    @Delete("DELETE FROM device_token WHERE user_id = #{userId}")
    int deleteByUserId(@Param("userId") long userId);
}
