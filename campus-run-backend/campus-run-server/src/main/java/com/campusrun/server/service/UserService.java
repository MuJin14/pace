package com.campusrun.server.service;

import com.campusrun.server.dto.response.UserInfoResponse;

public interface UserService {

    /**
     * 查询当前用户信息。
     *
     * @param userId 用户 ID
     * @return 用户信息
     * @throws BusinessException 用户不存在
     */
    UserInfoResponse getCurrentUser(Long userId);
}
