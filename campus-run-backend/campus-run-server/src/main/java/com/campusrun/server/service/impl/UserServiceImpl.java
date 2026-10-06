package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.exception.ForbiddenException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.request.ChangePasswordRequest;
import com.campusrun.server.dto.request.UpdateProfileRequest;
import com.campusrun.server.dto.response.ActivitySummaryResponse;
import com.campusrun.server.dto.response.UserBadgeResponse;
import com.campusrun.server.dto.response.UserInfoResponse;
import com.campusrun.server.dto.response.UserProfileResponse;
import com.campusrun.server.entity.User;
import com.campusrun.server.entity.UserStats;
import com.campusrun.server.enums.UserRelation;
import com.campusrun.server.entity.PasswordResetRequest;
import com.campusrun.server.mapper.ChatPreferenceMapper;
import com.campusrun.server.mapper.DeviceTokenMapper;
import com.campusrun.server.mapper.PasswordResetRequestMapper;
import com.campusrun.server.mapper.UserMapper;
import com.campusrun.server.mapper.UserStatsMapper;
import com.campusrun.server.service.ActivityService;
import com.campusrun.server.service.BadgeService;
import com.campusrun.server.service.UserRelationResolver;
import com.campusrun.server.service.UserService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
public class UserServiceImpl implements UserService {

    private static final Logger log = LoggerFactory.getLogger(UserServiceImpl.class);

    private final UserMapper userMapper;
    private final UserStatsMapper userStatsMapper;
    private final UserRelationResolver relationResolver;
    private final ActivityService activityService;
    private final BadgeService badgeService;
    /** 改密需要校验旧密码。为 null 时（部分单测）changePassword 会明确拒绝，而不是 NPE。 */
    private final PasswordEncoder passwordEncoder;
    /**
     * 注销账号时要一并清理的两张表。
     *
     * <p>为 null 时（兼容构造器场景）跳过清理，不影响其它单测。
     */
    private final ChatPreferenceMapper chatPreferenceMapper;
    private final DeviceTokenMapper deviceTokenMapper;
    /** 注销时一并清理的密码重置申请（可能为 null，兼容构造器场景）。 */
    private final PasswordResetRequestMapper passwordResetRequestMapper;

    /** 新密码长度下限，与注册保持一致（两侧规则不同会让用户困惑）。 */
    private static final int MIN_PASSWORD_LENGTH = 8;

    /** Spring 用这个构造器（显式标注，避免与下方兼容构造器歧义）。 */
    @org.springframework.beans.factory.annotation.Autowired
    public UserServiceImpl(UserMapper userMapper, UserStatsMapper userStatsMapper,
                           UserRelationResolver relationResolver,
                           ActivityService activityService, BadgeService badgeService,
                           PasswordEncoder passwordEncoder,
                           ChatPreferenceMapper chatPreferenceMapper,
                           DeviceTokenMapper deviceTokenMapper,
                           PasswordResetRequestMapper passwordResetRequestMapper) {
        this.userMapper = userMapper;
        this.userStatsMapper = userStatsMapper;
        this.relationResolver = relationResolver;
        this.activityService = activityService;
        this.badgeService = badgeService;
        this.passwordEncoder = passwordEncoder;
        this.chatPreferenceMapper = chatPreferenceMapper;
        this.deviceTokenMapper = deviceTokenMapper;
        this.passwordResetRequestMapper = passwordResetRequestMapper;
    }

    /** 兼容构造器：不含注销清理依赖（既有单测用）。 */
    public UserServiceImpl(UserMapper userMapper, UserStatsMapper userStatsMapper,
                           UserRelationResolver relationResolver,
                           ActivityService activityService, BadgeService badgeService,
                           PasswordEncoder passwordEncoder) {
        this(userMapper, userStatsMapper, relationResolver, activityService, badgeService,
                passwordEncoder, null, null, null);
    }

    /** 兼容构造器（既有单测用）：不涉及 relation、统计与他人数据。 */
    public UserServiceImpl(UserMapper userMapper) {
        this(userMapper, null, null, null, null, null);
    }

    /** 供主页相关单测使用。 */
    public UserServiceImpl(UserMapper userMapper, UserStatsMapper userStatsMapper,
                           UserRelationResolver relationResolver) {
        this(userMapper, userStatsMapper, relationResolver, null, null, null);
    }

    /**
     * 供社交数据权限单测使用（不涉及改密，故 passwordEncoder 为 null）。
     *
     * <p>保留这个 5 参构造器是为了不改动既有测试；
     * 生产走 Spring 注入的 6 参构造器，拿到真实的 PasswordEncoder。
     */
    public UserServiceImpl(UserMapper userMapper, UserStatsMapper userStatsMapper,
                           UserRelationResolver relationResolver,
                           ActivityService activityService, BadgeService badgeService) {
        this(userMapper, userStatsMapper, relationResolver, activityService, badgeService, null);
    }

    /** 供改密相关单测使用。 */
    public UserServiceImpl(UserMapper userMapper, PasswordEncoder passwordEncoder) {
        this(userMapper, null, null, null, null, passwordEncoder);
    }

    @Override
    public UserInfoResponse getCurrentUser(Long userId) {
        User user = userMapper.selectById(userId);
        if (user == null) {
            throw new BusinessException(ErrorCode.USER_NOT_FOUND);
        }
        return toInfoResponse(user);
    }

    @Override
    @Transactional
    public UserInfoResponse updateProfile(Long userId, UpdateProfileRequest request) {
        User user = userMapper.selectById(userId);
        if (user == null) {
            throw new BusinessException(ErrorCode.USER_NOT_FOUND);
        }

        // 字段为 null = 不修改，避免客户端只传头像时把昵称清空。
        if (request.getNickname() != null) {
            String nickname = request.getNickname().trim();
            if (nickname.isEmpty()) {
                throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "昵称不能为空");
            }
            user.setNickname(nickname);
        }
        if (request.getAvatarUrl() != null) {
            String avatar = request.getAvatarUrl().trim();
            // 空串视为「清空头像」，回到昵称首字兜底
            user.setAvatarUrl(avatar.isEmpty() ? null : avatar);
        }
        // 性别 / 年龄：null = 不修改（PATCH 语义）。
        // 可见性用 Boolean，所以「传 false」能明确表达「改成不公开」，
        // 不会像 int 那样把「没传」和「传 0」混为一谈。
        if (request.getGender() != null) {
            user.setGender(request.getGender());
        }
        if (request.getAge() != null) {
            user.setAge(request.getAge());
        }
        if (request.getGenderPublic() != null) {
            user.setGenderPublic(request.getGenderPublic() ? 1 : 0);
        }
        if (request.getAgePublic() != null) {
            user.setAgePublic(request.getAgePublic() ? 1 : 0);
        }

        userMapper.updateById(user);
        log.info("资料已更新，userId={}, nickname={}, hasAvatar={}, gender={}, age={}, "
                        + "genderPublic={}, agePublic={}",
                userId, user.getNickname(), user.getAvatarUrl() != null,
                user.getGender(), user.getAge(), user.getGenderPublic(), user.getAgePublic());
        return toInfoResponse(user);
    }

    @Override
    @Transactional
    public void changePassword(Long userId, ChangePasswordRequest request) {
        if (passwordEncoder == null) {
            // 只可能出现在没装配 PasswordEncoder 的单测里。明确报错而不是 NPE。
            throw new BusinessException(ErrorCode.INTERNAL_ERROR.getCode(), "密码服务不可用");
        }

        User user = userMapper.selectById(userId);
        if (user == null) {
            throw new BusinessException(ErrorCode.USER_NOT_FOUND);
        }

        // 必须校验旧密码：只凭 access token 就能改密的话，token 泄露（日志/代理）
        // 等于账号被锁死。失败一律回报 1003「密码错误」，不区分
        // 「旧密码错」与「用户不存在」—— 后者会变成账号枚举接口。
        if (!passwordEncoder.matches(request.getOldPassword(), user.getPasswordHash())) {
            log.warn("修改密码失败：旧密码不正确，userId={}", userId);
            throw new BusinessException(ErrorCode.PASSWORD_ERROR.getCode(), "当前密码不正确");
        }

        String newPassword = request.getNewPassword();
        if (newPassword.length() < MIN_PASSWORD_LENGTH) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(),
                    "新密码长度不能少于 " + MIN_PASSWORD_LENGTH + " 位");
        }
        if (passwordEncoder.matches(newPassword, user.getPasswordHash())) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "新密码不能与当前密码相同");
        }

        user.setPasswordHash(passwordEncoder.encode(newPassword));
        // 关键：让此前签发的 refresh token 全部失效。
        // 不写这个字段的话，改密只拦住「用新密码登录」，
        // 而别人手里 30 天有效的 refresh token 仍能换到新 access token。
        user.setTokenInvalidBefore(LocalDateTime.now());
        userMapper.updateById(user);

        log.info("密码已修改并吊销旧令牌，userId={}, invalidBefore={}",
                userId, user.getTokenInvalidBefore());
    }

    @Override
    public PageResponse<ActivitySummaryResponse> listUserActivities(Long me, Long target,
                                                                   Integer type, long page, long size) {
        requireFriend(me, target);
        // 仅展示有效记录：无效（反作弊命中）记录不该出现在别人的视角里
        return activityService.page(target, type, page, size);
    }

    @Override
    public List<UserBadgeResponse> listUserBadges(Long me, Long target) {
        requireFriend(me, target);
        return badgeService.listMine(target);
    }

    /**
     * 要求 me 与 target 是好友（自己看自己始终允许）。
     *
     * @throws BusinessException 目标不存在，或不是好友
     */
    private void requireFriend(Long me, Long target) {
        if (userMapper.selectById(target) == null) {
            throw new BusinessException(ErrorCode.USER_NOT_FOUND);
        }
        UserRelation relation = relationResolver == null
                ? UserRelation.NONE
                : relationResolver.resolve(me, target);
        if (relation != UserRelation.FRIEND && relation != UserRelation.SELF) {
            // 用 ForbiddenException 而不是 BusinessException：
            // 前者被全局处理器映射成 HTTP 403，调用方仅凭状态码就能区分
            // 「没权限」与「对方没数据」，前端不会把 403 渲染成空态。
            throw new ForbiddenException("对方还不是你的好友，无法查看 TA 的运动数据");
        }
    }

    private UserInfoResponse toInfoResponse(User user) {
        UserInfoResponse response = new UserInfoResponse();
        response.setUserId(user.getId());
        response.setUniqueId(user.getUniqueId());
        response.setNickname(user.getNickname());
        response.setPhone(user.getPhone());
        response.setAvatarUrl(user.getAvatarUrl());
        response.setCreatedAt(user.getCreatedAt());
        // 这是「自己看自己」，性别/年龄及其开关都要返回，设置页需要回显
        response.setGender(user.getGender());
        response.setAge(user.getAge());
        response.setGenderPublic(isPublic(user.getGenderPublic()));
        response.setAgePublic(isPublic(user.getAgePublic()));
        // 角色：前端据此决定是否显示「管理后台」入口。
        // 只是 UI 提示，**真正的权限校验在服务端**（@PreAuthorize），
        // 前端改这个值也拿不到管理员接口。
        response.setRole(user.getRole());
        return response;
    }

    /** 可见性字段在库里是 0/1，对前端统一暴露成布尔，避免两边口径不一致。 */
    private static boolean isPublic(Integer flag) {
        return flag != null && flag == 1;
    }

    @Override
    public UserProfileResponse getProfile(Long me, Long target) {
        User user = userMapper.selectById(target);
        if (user == null) {
            throw new BusinessException(ErrorCode.USER_NOT_FOUND);
        }

        UserProfileResponse response = new UserProfileResponse();
        response.setUserId(user.getId());
        response.setUniqueId(user.getUniqueId());
        response.setNickname(user.getNickname());
        response.setAvatarUrl(user.getAvatarUrl());
        response.setCreatedAt(user.getCreatedAt());
        // 刻意不设置 phone：主页对他人可见，手机号不在其中。

        boolean isSelf = me != null && me.equals(target);
        if (relationResolver != null) {
            response.setRelation(relationResolver.resolve(me, target).getCode());
        }

        // 性别 / 年龄按可见性返回。
        // 关键设计：**不公开时字段保持 null，而不是返回 0 或占位值** ——
        // 这样协议层就不存在这个信息，客户端无法从任何字段反推出来。
        // 本人访问时不设限制，否则自己的设置页无法回显真实值。
        if (isSelf || isPublic(user.getGenderPublic())) {
            response.setGender(user.getGender());
        }
        if (isSelf || isPublic(user.getAgePublic())) {
            response.setAge(user.getAge());
        }

        // 运动汇总用于展示「TA 的跑量」，缺失时前端显示 0 而不是报错。
        if (userStatsMapper != null) {
            UserStats stats = userStatsMapper.selectById(target);
            if (stats != null) {
                response.setTotalDistanceMeters(stats.getTotalDistanceMeters());
                response.setTotalActivityCount(stats.getTotalActivityCount());
                response.setStreakDays(stats.getStreakDays());
            }
        }
        return response;
    }

    @Override
    @Transactional
    public void deleteAccount(Long userId) {
        User user = userMapper.selectById(userId);
        if (user == null) {
            throw new BusinessException(ErrorCode.USER_NOT_FOUND);
        }

        // 顺序无关（都在同一事务里），但先删子表再删主表更符合直觉。
        int activities = userMapper.deleteActivities(userId);
        int friendships = userMapper.deleteFriendships(userId);
        int messages = userMapper.deleteMessages(userId);
        int leaderboard = userMapper.deleteLeaderboardStats(userId);
        int goals = userMapper.deleteGoals(userId);
        int badges = userMapper.deleteUserBadges(userId);
        int stats = userMapper.deleteUserStats(userId);
        // 会话偏好（免打扰）与推送令牌：早期版本漏了这两张表。
        // 漏掉 device_token 的后果最严重 —— 账号已注销，令牌仍指向该用户 id，
        // 推送就会继续往这台已经换人的手机发通知（隐私问题）。
        // 依赖为 null 时（兼容构造器场景）跳过，不影响其它单测。
        int chatPrefs = chatPreferenceMapper == null ? 0 : chatPreferenceMapper.deleteByUser(userId);
        int deviceTokens = deviceTokenMapper == null ? 0 : deviceTokenMapper.deleteByUserId(userId);
        // 密码重置申请同样要清：账号都没了，还挂着一条「待处理」的申请
        // 会让管理员以为有人等着处理。
        int resetRequests = passwordResetRequestMapper == null
                ? 0
                : passwordResetRequestMapper.delete(
                        new LambdaQueryWrapper<PasswordResetRequest>()
                                .eq(PasswordResetRequest::getUserId, userId));
        userMapper.deleteById(userId);

        log.info("账号已注销，userId={}, 清理: activity={}, friendship={}, message={}, "
                        + "leaderboard={}, goal={}, badge={}, stats={}, chatPref={}, "
                        + "deviceToken={}, resetRequest={}",
                userId, activities, friendships, messages, leaderboard, goals, badges, stats,
                chatPrefs, deviceTokens, resetRequests);
    }
}
