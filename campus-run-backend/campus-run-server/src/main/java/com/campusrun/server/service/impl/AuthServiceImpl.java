package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.server.dto.request.LoginRequest;
import com.campusrun.server.dto.request.RefreshTokenRequest;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.entity.User;
import com.campusrun.server.enums.UserRole;
import com.campusrun.server.mapper.UserMapper;
import com.campusrun.server.security.JwtTokenProvider;
import com.campusrun.server.security.RateLimiter;
import com.campusrun.server.service.AuthService;
import com.campusrun.server.util.UniqueIdGenerator;
import io.jsonwebtoken.Claims;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.Date;

/**
 * 鉴权服务。
 *
 * <p>两层防护：
 * <ol>
 *   <li><b>限流</b>：登录/注册/刷新三个入口做滑动窗口限流，同时按「手机号」和「IP」两个维度计数。
 *       只按 IP 挡不住分布式撞库，只按手机号挡不住批量注册刷不同号，两者叠加才有效。</li>
 *   <li><b>双令牌</b>：access 短命 + refresh 长命，避免用户每天被强制登出，
 *       同时把 access 泄露的可用窗口压到 {@code jwt.expiration}。</li>
 * </ol>
 */
@Service
public class AuthServiceImpl implements AuthService {

    private static final Logger log = LoggerFactory.getLogger(AuthServiceImpl.class);

    /** 同一手机号在窗口内允许的失败尝试次数。 */
    private static final int PHONE_LIMIT = 10;
    /** 同一 IP 在窗口内允许的登录/注册次数。 */
    private static final int IP_LIMIT = 30;
    /** 限流窗口（秒）。 */
    private static final long WINDOW_SECONDS = 300L;

    /** 业务时区，与排行榜/目标推导保持一致（改密吊销的时间比较也用它）。 */
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    private final UserMapper userMapper;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenProvider jwtTokenProvider;
    private final UniqueIdGenerator uniqueIdGenerator;
    private final RateLimiter rateLimiter;

    /**
     * 主构造器。显式标注 {@code @Autowired}：本类另有一个兼容构造器，
     * 若不指定，Spring 无法在多个候选构造器之间做出选择（会尝试找默认构造器并失败）。
     */
    @org.springframework.beans.factory.annotation.Autowired
    public AuthServiceImpl(UserMapper userMapper, PasswordEncoder passwordEncoder,
                           JwtTokenProvider jwtTokenProvider, UniqueIdGenerator uniqueIdGenerator,
                           RateLimiter rateLimiter) {
        this.userMapper = userMapper;
        this.passwordEncoder = passwordEncoder;
        this.jwtTokenProvider = jwtTokenProvider;
        this.uniqueIdGenerator = uniqueIdGenerator;
        this.rateLimiter = rateLimiter;
    }

    /**
     * 兼容构造器：用于只关心鉴权逻辑、不关心限流的场景（既有单测）。
     * 内部使用独立的限流器实例，避免与全局限流状态互相干扰。
     */
    public AuthServiceImpl(UserMapper userMapper, PasswordEncoder passwordEncoder,
                           JwtTokenProvider jwtTokenProvider, UniqueIdGenerator uniqueIdGenerator) {
        this(userMapper, passwordEncoder, jwtTokenProvider, uniqueIdGenerator, new RateLimiter());
    }

    @Override
    @Transactional
    public LoginResponse register(RegisterRequest request, String clientIp) {
        enforceRateLimit("register", request.getPhone(), clientIp);

        Long existing = userMapper.selectCount(
                new LambdaQueryWrapper<User>().eq(User::getPhone, request.getPhone()));
        if (existing != null && existing > 0) {
            throw new BusinessException(ErrorCode.PHONE_EXISTS);
        }

        User user = new User();
        user.setUniqueId(uniqueIdGenerator.generate(userMapper));
        user.setPhone(request.getPhone());
        user.setPasswordHash(passwordEncoder.encode(request.getPassword()));
        user.setNickname(request.getNickname());
        user.setRole(UserRole.USER.getCode());
        userMapper.insert(user);

        log.info("注册成功，userId={}, uniqueId={}", user.getId(), user.getUniqueId());
        return buildLoginResponse(user);
    }

    @Override
    public LoginResponse login(LoginRequest request, String clientIp) {
        enforceRateLimit("login", request.getPhone(), clientIp);

        User user = userMapper.selectOne(
                new LambdaQueryWrapper<User>().eq(User::getPhone, request.getPhone()));
        if (user == null) {
            throw new BusinessException(ErrorCode.USER_NOT_FOUND);
        }
        if (!passwordEncoder.matches(request.getPassword(), user.getPasswordHash())) {
            throw new BusinessException(ErrorCode.PASSWORD_ERROR);
        }

        applySingleDeviceLogin(user, request.getDeviceId());
        return buildLoginResponse(user);
    }

    /**
     * 单设备登录：换了一台设备就把旧设备的令牌全部作废。
     *
     * <h3>为什么需要</h3>
     *
     * <p>在此之前凭据是纯 JWT，服务端不留记录，同一个账号可以在任意多台设备上
     * 同时登录，并牵连出一串问题（WebSocket 连接互相顶掉、已读回执串台、
     * 两台设备各记一条轨迹、手机丢了无法远程下线……）。
     *
     * <h3>规则</h3>
     *
     * <ul>
     *   <li>设备标识**相同**（或客户端没上报）→ 不动版本。
     *       同一台手机重复登录不该把自己踢下线 —— 那是最正常的操作；
     *       没上报的老客户端则退化成「每次都踢」，可接受（见 LoginRequest 说明）。</li>
     *   <li>设备标识**不同** → {@code tokenVersion + 1}，
     *       旧设备手上的 access/refresh token 立即失效（校验见 JwtAuthenticationFilter），
     *       客户端会收到 {@code code=4011} 并被引导回登录页。</li>
     * </ul>
     *
     * <p>为什么用版本号而不是复用 {@code tokenInvalidBefore}：后者的比较必须放宽成
     * {@code isBefore}（JWT 的 iat 只有秒级精度），于是「同一秒内签发的旧令牌」
     * 会有约 1 秒存活窗口；单设备登录要求的是**精确**失效。
     */
    private void applySingleDeviceLogin(User user, String rawDeviceId) {
        String deviceId = rawDeviceId == null ? null : rawDeviceId.trim();
        if (deviceId != null && deviceId.length() > 64) {
            deviceId = deviceId.substring(0, 64);
        }

        String previous = user.getDeviceId();
        boolean sameDevice = previous != null && previous.equals(deviceId);

        if (sameDevice) {
            return;
        }

        int nextVersion = user.getTokenVersion() + 1;
        user.setTokenVersion(nextVersion);
        user.setDeviceId(deviceId);

        // 只更新这两列：用 updateById 会把整个实体写回去，
        // 而这里不该碰到密码、昵称等字段（并发登录时尤其危险）。
        //
        // 用字符串列名的 UpdateWrapper 而不是 LambdaUpdateWrapper：
        // 后者需要在 MyBatis 容器里注册过实体元数据，纯单测（Mockito）跑不起来
        // —— 会被迫把这条逻辑挪进 @SpringBootTest，测试变慢且更难定位。
        // 代价是列名变成了字面量，所以**必须与迁移里的列名保持一致**
        // （docs/migrations/005_single_device_login.sql），下面有测试断言这一点。
        userMapper.update(null,
                new UpdateWrapper<User>()
                        .eq("id", user.getId())
                        .set("token_version", nextVersion)
                        .set("device_id", deviceId));

        if (previous != null) {
            log.info("检测到换设备登录，已作废旧令牌: userId={}, version={} -> {}",
                    user.getId(), nextVersion - 1, nextVersion);
        }
    }

    @Override
    public LoginResponse refresh(RefreshTokenRequest request, String clientIp) {
        enforceRateLimit("refresh", null, clientIp);

        Claims claims;
        try {
            // parseRefreshToken 会校验签名、过期时间以及 typ=refresh，
            // 因此 access token 不能拿来刷新（反之亦然）。
            claims = jwtTokenProvider.parseRefreshToken(request.getRefreshToken());
        } catch (Exception e) {
            log.debug("刷新令牌校验失败: {}", e.getMessage());
            throw new BusinessException(ErrorCode.INVALID_REFRESH_TOKEN);
        }

        Long userId;
        try {
            userId = Long.valueOf(claims.getSubject());
        } catch (NumberFormatException e) {
            throw new BusinessException(ErrorCode.INVALID_REFRESH_TOKEN);
        }

        // 重新查库：用户被删除/封禁后，旧的 refresh token 不应继续可用。
        User user = userMapper.selectById(userId);
        if (user == null) {
            throw new BusinessException(ErrorCode.INVALID_REFRESH_TOKEN);
        }

        // 单设备登录：版本不符说明该用户已在别的设备登录过，这枚 refresh 已作废。
        // 不校验的话，被踢下线的设备能靠刷新无限续命 —— 整个机制就白做了。
        int tokenVersion = jwtTokenProvider.tokenVersionOf(claims);
        if (tokenVersion != user.getTokenVersion()) {
            log.info("刷新被拒：令牌版本不符（已在其他设备登录）userId={}, tokenVer={}, dbVer={}",
                    userId, tokenVersion, user.getTokenVersion());
            throw new BusinessException(ErrorCode.INVALID_REFRESH_TOKEN);
        }

        // 改密吊销：签发时间早于 tokenInvalidBefore 的 refresh token 一律拒绝。
        //
        // 比较用 isBefore 而不是 !isAfter —— JWT 的 iat 只有**秒级精度**，
        // 而 tokenInvalidBefore 带毫秒。若用 !isAfter，在「改密后同一秒内立刻刷新」
        // 这个正常场景下，iat（截断到秒）会等于 invalidBefore（带毫秒），
        // 新令牌会被误杀，用户表现为「改完密码立刻被登出」。
        // 用 isBefore 只拒绝严格更早的令牌，代价是同一秒内的旧令牌仍有效 —— 
        // 可接受，因为这一秒窗口内的旧令牌本来就极难被利用。
        LocalDateTime invalidBefore = user.getTokenInvalidBefore();
        if (invalidBefore != null) {
            Date issuedAt = claims.getIssuedAt();
            if (issuedAt != null
                    && issuedAt.toInstant()
                    .isBefore(invalidBefore.atZone(ZONE).toInstant())) {
                log.info("刷新被拒：令牌签发于改密之前，userId={}, iat={}, invalidBefore={}",
                        userId, issuedAt, invalidBefore);
                throw new BusinessException(ErrorCode.INVALID_REFRESH_TOKEN);
            }
        }

        LoginResponse response = buildLoginResponse(user);
        // 轮换：refresh token 原样返回，保持 30 天滑动有效期不变；
        // 若将来要做「一次性 refresh」（检测令牌重放），在此处改为签发新 refresh 并登记旧的为已用。
        response.setRefreshToken(request.getRefreshToken());
        return response;
    }

    /**
     * 按手机号 + IP 双维度限流。
     *
     * <p>IP 维度只在调用方确实提供了 IP 时才计数（HTTP 入口一定提供）。
     * 若把「未提供 IP」也归入同一个 {@code unknown} 桶，所有不带 IP 的调用
     * （例如内部调用、集成测试）会共享一份配额并互相误伤。
     *
     * @param action   动作名（login / register / refresh），用于隔离不同入口的配额
     * @param phone    手机号；为空时跳过手机号维度
     * @param clientIp 客户端 IP；为空时跳过 IP 维度
     */
    private void enforceRateLimit(String action, String phone, String clientIp) {
        if (phone != null && !phone.isBlank()
                && !rateLimiter.tryAcquire(action + ":phone:" + phone, PHONE_LIMIT, WINDOW_SECONDS)) {
            log.warn("限流命中（手机号维度），action={}", action);
            throw new BusinessException(ErrorCode.TOO_MANY_REQUESTS);
        }
        if (clientIp != null && !clientIp.isBlank()
                && !rateLimiter.tryAcquire(action + ":ip:" + clientIp, IP_LIMIT, WINDOW_SECONDS)) {
            log.warn("限流命中（IP 维度），action={}, ip={}", action, clientIp);
            throw new BusinessException(ErrorCode.TOO_MANY_REQUESTS);
        }
    }

    private LoginResponse buildLoginResponse(User user) {
        LoginResponse response = new LoginResponse();
        // 版本号必须写进令牌：它决定这枚令牌何时被判定为「已在其他设备登录」。
        int tokenVersion = user.getTokenVersion();
        response.setToken(jwtTokenProvider.generateAccessToken(
                user.getId(), user.getUniqueId(), user.getRole(), tokenVersion));
        response.setRefreshToken(jwtTokenProvider.generateRefreshToken(
                user.getId(), user.getUniqueId(), user.getRole(), tokenVersion));
        response.setUserId(user.getId());
        response.setUniqueId(user.getUniqueId());
        response.setNickname(user.getNickname());
        response.setPhone(user.getPhone());
        response.setAvatarUrl(user.getAvatarUrl());
        // 角色必须一起返回。
        //
        // 不返回会怎样：App 的 `User.fromJson` 是 `role: json['role'] ?? 0`，
        // 登录响应里没有 role 就等于把所有人都当成普通用户 ——
        // 管理员登录后看不到「管理后台」入口，必须等 `/me` 回来才补上，
        // 而刷新/重启期间那段窗口里入口是消失的（用户看到的就是这个）。
        //
        // 注意：前端把入口藏起来只是 UI 便利，真正的权限校验在后端
        // `ROLE_ADMIN` 上，所以这里多返回一个 role 不构成越权。
        response.setRole(user.getRole());
        return response;
    }
}
