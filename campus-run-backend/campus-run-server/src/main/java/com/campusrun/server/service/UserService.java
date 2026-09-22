package com.campusrun.server.service;

import com.campusrun.server.dto.response.UserInfoResponse;

public interface UserService {

    UserInfoResponse getCurrentUser(Long userId);
}
