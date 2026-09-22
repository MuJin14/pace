package com.campusrun.server.service;

import com.campusrun.server.dto.request.LoginRequest;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.LoginResponse;

public interface AuthService {

    LoginResponse register(RegisterRequest request);

    LoginResponse login(LoginRequest request);
}
