package com.campusrun.server.config;

import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.Result;
import com.campusrun.server.filter.AppVersionHeaderFilter;
import com.campusrun.server.security.JwtAuthenticationFilter;
import com.campusrun.server.update.AppVersionMetadata;
import com.campusrun.server.update.AppVersionProvider;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

@Configuration
@EnableWebSecurity
@EnableMethodSecurity
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthenticationFilter;
    private final ObjectMapper objectMapper;
    /**
     * 版本元数据来源。
     *
     * <p>用 {@link ObjectProvider} 而不是直接注入：{@code @WebMvcTest} 切片测试
     * 不加载 {@code AppVersionStore}，直接注入会让 67 个测试
     * {@code ApplicationContext} 加载失败。
     * 取不到时降级为「不发版本头」——对测试毫无影响，生产环境始终能取到。
     */
    private final ObjectProvider<AppVersionProvider> appVersionProvider;

    public SecurityConfig(JwtAuthenticationFilter jwtAuthenticationFilter,
                          ObjectMapper objectMapper,
                          ObjectProvider<AppVersionProvider> appVersionProvider) {
        this.jwtAuthenticationFilter = jwtAuthenticationFilter;
        this.objectMapper = objectMapper;
        this.appVersionProvider = appVersionProvider;
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                .cors(Customizer.withDefaults())
                .csrf(csrf -> csrf.disable())
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        // /uploads/** 必须放行：头像 URL 由 <img> 直接加载，
                        // 浏览器不会带 Authorization 头，要鉴权就全都显示不出来。
                        .requestMatchers("/api/v1/auth/**", "/ws/**", "/uploads/**", "/error").permitAll()
                        // 缩略图接口同理：它替代的正是 /uploads/** 的角色
                        // （列表里加载图片），要鉴权的话聊天图片全变空白。
                        // 安全性由 ThumbnailService 的路径穿越防护保证：
                        // 只能读 uploadRoot 内已存在的文件。
                        .requestMatchers(HttpMethod.GET, "/api/v1/media/**").permitAll()
                        // 提交密码重置申请要放行：用户就是登不上才来申请的。
                        // ⚠️ 必须用「方法 + 精确路径」匹配，不能写成
                        // `/api/v1/password-reset-requests/**` —— 那样连
                        // `/mine`（查看自己的申请状态）也会变成匿名可访问。
                        .requestMatchers(HttpMethod.POST, "/api/v1/password-reset-requests").permitAll()
                        // App 自更新：版本检查与 APK 下载都要在登录前可用
                        // （更新提示应该在启动页就可能出现，不该被登录拦住）。
                        .requestMatchers("/api/v1/app/**").permitAll()
                        .anyRequest().authenticated())
                .exceptionHandling(ex -> ex
                        .authenticationEntryPoint((request, response, authException) -> {
                            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
                            response.setContentType("application/json;charset=UTF-8");
                            response.getWriter().write(objectMapper.writeValueAsString(Result.error(ErrorCode.UNAUTHORIZED)));
                        }))
                .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class)
                // 更新信号：只读请求头、写响应头，与鉴权无先后依赖。
                //
                // ⚠️ 刻意**不做成 Spring Bean**（标 @Component 或声明 @Bean 都不行）：
                //    那样 Spring 就必须能构造它，于是每个 @WebMvcTest 切片测试
                //    都会因为缺少 AppVersionStore 而 ApplicationContext 失败。
                //    直接 new 进过滤器链，并把依赖收窄成可选，切片测试自然降级。
                .addFilterAfter(new AppVersionHeaderFilter(
                                appVersionProvider.getIfAvailable(
                                        () -> () -> AppVersionMetadata.EMPTY)),
                        JwtAuthenticationFilter.class);
        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
