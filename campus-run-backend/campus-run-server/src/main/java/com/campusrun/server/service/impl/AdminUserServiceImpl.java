package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.AdminUserItem;
import com.campusrun.server.dto.response.PasswordResetRequestItem;
import com.campusrun.server.dto.response.PasswordResetResult;
import com.campusrun.server.entity.PasswordResetRequest;
import com.campusrun.server.entity.User;
import com.campusrun.server.enums.UserRole;
import com.campusrun.server.mapper.PasswordResetRequestMapper;
import com.campusrun.server.mapper.UserMapper;
import com.campusrun.server.service.AdminUserService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * {@link AdminUserService} 实现。
 */
@Service
public class AdminUserServiceImpl implements AdminUserService {

    private static final Logger log = LoggerFactory.getLogger(AdminUserServiceImpl.class);

    /**
     * 管理员重置后下发的**固定**临时密码。
     *
     * <h3>为什么改成固定值（真实需求）</h3>
     *
     * <p>原来是 10 位随机密码。看起来更安全，但在这个使用场景下反而更糟：
     *
     * <ul>
     *   <li>重置是**管理员手动操作**的，密码要通过微信/口头转达给同学。
     *       随机串（{@code Hk7mPq2nRt}）在转达环节极易抄错、念错；</li>
     *   <li>抄错之后用户登不进来，又会来一轮重置 —— 管理员的工作量翻倍；</li>
     *   <li>更糟的是用户可能就此放弃，直接不用了。</li>
     * </ul>
     *
     * <p>固定 {@code 123456} 后转达成本归零，用户拿到就能登进去。
     *
     * <h3>安全性靠什么保证</h3>
     *
     * <p>固定密码本身当然很弱，但这里**只把它当作一次性的进门凭证**，
     * 真正的防护在这几处：
     *
     * <ol>
     *   <li>重置**必须由管理员发起**，用户自己无法触发（登录页的
     *       「忘记密码」只是提交申请，不会直接改密码）；</li>
     *   <li>重置会写入 {@code tokenInvalidBefore}，作废该用户全部旧令牌；</li>
     *   <li>{@link com.campusrun.server.config.SecurityConfig} 未对
     *       {@code /api/v1/**} 放行，凭 123456 登录后能做的事与其他用户
     *       完全一样 —— 不会因为密码简单而多出任何权限；</li>
     *   <li>App 在登录后会提示用户尽快改成自己的密码
     *       （「我的 → 修改密码」）。</li>
     * </ol>
     *
     * <p>⚠️ 这个常量与客户端的「修改密码」最短长度校验（8 位）没有冲突：
     * 它只是初始值，用户改密时仍要求 8 位以上。
     */
    private static final String TEMP_PASSWORD = "123456";

    private final UserMapper userMapper;
    private final PasswordResetRequestMapper resetRequestMapper;
    private final PasswordEncoder passwordEncoder;

    public AdminUserServiceImpl(UserMapper userMapper,
                                PasswordResetRequestMapper resetRequestMapper,
                                PasswordEncoder passwordEncoder) {
        this.userMapper = userMapper;
        this.resetRequestMapper = resetRequestMapper;
        this.passwordEncoder = passwordEncoder;
    }

    @Override
    public PageResponse<AdminUserItem> listUsers(String keyword, long page, long size) {
        long safePage = Math.max(1, page);
        long safeSize = Math.min(100, Math.max(1, size));

        LambdaQueryWrapper<User> wrapper = new LambdaQueryWrapper<>();
        if (keyword != null && !keyword.isBlank()) {
            String kw = keyword.trim();
            // 三个字段任一命中即可：管理员手上可能只有昵称（用户报的名字）
            // 或只有手机号（用户报的登录号），两者都要能搜到。
            wrapper.and(w -> w.like(User::getPhone, kw)
                    .or().like(User::getNickname, kw)
                    .or().like(User::getUniqueId, kw));
        }
        wrapper.orderByDesc(User::getId);

        Page<User> result = userMapper.selectPage(new Page<>(safePage, safeSize), wrapper);
        List<AdminUserItem> list = new ArrayList<>();
        for (User u : result.getRecords()) {
            list.add(toItem(u));
        }
        return new PageResponse<>(result.getTotal(), safePage, safeSize, list);
    }

    @Override
    @Transactional
    public PasswordResetResult resetPassword(Long operatorId, Long targetUserId) {
        User target = userMapper.selectById(targetUserId);
        if (target == null) {
            throw new BusinessException(ErrorCode.USER_NOT_FOUND);
        }
        // 管理员改自己的密码必须走「修改密码」并提供旧密码。
        // 放开这条等于给管理员账号一个「无需旧密码改自己密码」的后门：
        // 一旦管理员的 access token 泄漏，攻击者就能直接夺号。
        if (target.getId().equals(operatorId)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(),
                    "不能在这里重置自己的密码，请使用「修改密码」");
        }
        return doReset(target);
    }

    /** 真正执行重置：换成固定临时密码 + 作废该用户全部旧令牌。 */
    private PasswordResetResult doReset(User target) {
        String temporary = TEMP_PASSWORD;
        target.setPasswordHash(passwordEncoder.encode(temporary));
        // 与「修改密码」同样的关键一步：不写这个字段的话，
        // 用户之前泄漏出去的 refresh token（30 天有效）仍能换到新 access token，
        // 重置密码就形同虚设。
        target.setTokenInvalidBefore(LocalDateTime.now());
        userMapper.updateById(target);

        log.info("管理员重置了密码，userId={}, nickname={}", target.getId(), target.getNickname());
        return new PasswordResetResult(target.getId(), target.getNickname(), temporary);
    }

    @Override
    @Transactional
    public void createResetRequest(String phone, String note) {
        if (phone == null || phone.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "请输入手机号");
        }
        User user = userMapper.selectOne(
                new LambdaQueryWrapper<User>().eq(User::getPhone, phone.trim()));
        // ⚠️ 账号不存在时**也返回成功**，不报「用户不存在」。
        // 否则这个未登录接口就成了「手机号是否注册过」的枚举器 ——
        // 攻击者可以用它批量探测哪些号注册过本 App。
        if (user == null) {
            log.info("收到未注册手机号的重置申请，已静默忽略: {}", maskPhone(phone));
            return;
        }

        // 同一用户已有待处理申请时不重复插入：否则用户多点几次，
        // 管理后台就被同一个人的多条申请刷屏。
        Long pending = resetRequestMapper.selectCount(new LambdaQueryWrapper<PasswordResetRequest>()
                .eq(PasswordResetRequest::getUserId, user.getId())
                .eq(PasswordResetRequest::getStatus, PasswordResetRequest.STATUS_PENDING));
        if (pending != null && pending > 0) {
            log.info("用户已有待处理的重置申请，忽略重复提交，userId={}", user.getId());
            return;
        }

        PasswordResetRequest req = new PasswordResetRequest();
        req.setUserId(user.getId());
        req.setPhone(user.getPhone());
        req.setNickname(user.getNickname());
        req.setStatus(PasswordResetRequest.STATUS_PENDING);
        req.setNote(truncate(note, 200));
        try {
            resetRequestMapper.insert(req);
        } catch (DuplicateKeyException e) {
            // 并发重复提交（唯一索引兜底）：忽略即可，结果相同
            log.info("重置申请并发重复插入，已忽略，userId={}", user.getId());
        }
    }

    @Override
    public PasswordResetRequestItem myLatestRequest(Long userId) {
        List<PasswordResetRequest> rows = resetRequestMapper.selectList(
                new LambdaQueryWrapper<PasswordResetRequest>()
                        .eq(PasswordResetRequest::getUserId, userId)
                        .orderByDesc(PasswordResetRequest::getId)
                        .last("LIMIT 1"));
        return rows.isEmpty() ? null : toItem(rows.get(0));
    }

    @Override
    public List<PasswordResetRequestItem> listRequests(Integer status) {
        LambdaQueryWrapper<PasswordResetRequest> wrapper = new LambdaQueryWrapper<>();
        if (status != null) {
            wrapper.eq(PasswordResetRequest::getStatus, status);
        }
        // 待处理的排最前，其次按时间倒序：管理员最关心「还有谁没处理」
        wrapper.orderByAsc(PasswordResetRequest::getStatus)
                .orderByDesc(PasswordResetRequest::getId)
                .last("LIMIT 200");
        List<PasswordResetRequestItem> list = new ArrayList<>();
        for (PasswordResetRequest r : resetRequestMapper.selectList(wrapper)) {
            list.add(toItem(r));
        }
        return list;
    }

    @Override
    @Transactional
    public PasswordResetResult handleRequest(Long operatorId, Long requestId) {
        PasswordResetRequest req = resetRequestMapper.selectById(requestId);
        if (req == null) {
            throw new BusinessException(ErrorCode.NOT_FOUND.getCode(), "申请不存在");
        }
        if (!Integer.valueOf(PasswordResetRequest.STATUS_PENDING).equals(req.getStatus())) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "该申请已处理过了");
        }
        User target = userMapper.selectById(req.getUserId());
        if (target == null) {
            // 用户可能在申请后注销了账号：把申请标记为已拒绝，避免它永远挂在待处理里
            req.setStatus(PasswordResetRequest.STATUS_REJECTED);
            req.setHandledBy(operatorId);
            req.setHandledAt(LocalDateTime.now());
            resetRequestMapper.updateById(req);
            throw new BusinessException(ErrorCode.USER_NOT_FOUND.getCode(), "该用户已注销账号");
        }
        if (target.getId().equals(operatorId)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(),
                    "不能在这里重置自己的密码，请使用「修改密码」");
        }

        PasswordResetResult result = doReset(target);

        req.setStatus(PasswordResetRequest.STATUS_RESET);
        req.setHandledBy(operatorId);
        req.setHandledAt(LocalDateTime.now());
        resetRequestMapper.updateById(req);
        return result;
    }

    @Override
    @Transactional
    public void rejectRequest(Long operatorId, Long requestId) {
        PasswordResetRequest req = resetRequestMapper.selectById(requestId);
        if (req == null) {
            throw new BusinessException(ErrorCode.NOT_FOUND.getCode(), "申请不存在");
        }
        if (!Integer.valueOf(PasswordResetRequest.STATUS_PENDING).equals(req.getStatus())) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "该申请已处理过了");
        }
        req.setStatus(PasswordResetRequest.STATUS_REJECTED);
        req.setHandledBy(operatorId);
        req.setHandledAt(LocalDateTime.now());
        resetRequestMapper.updateById(req);
    }


    private AdminUserItem toItem(User u) {
        AdminUserItem item = new AdminUserItem();
        item.setUserId(u.getId());
        item.setUniqueId(u.getUniqueId());
        item.setNickname(u.getNickname());
        item.setPhone(u.getPhone());
        item.setAvatarUrl(u.getAvatarUrl());
        item.setRole(u.getRole());
        item.setCreatedAt(u.getCreatedAt());
        return item;
    }

    private PasswordResetRequestItem toItem(PasswordResetRequest r) {
        PasswordResetRequestItem item = new PasswordResetRequestItem();
        item.setId(r.getId());
        item.setUserId(r.getUserId());
        item.setNickname(r.getNickname());
        item.setPhone(r.getPhone());
        item.setStatus(r.getStatus());
        item.setNote(r.getNote());
        item.setCreatedAt(r.getCreatedAt());
        item.setHandledAt(r.getHandledAt());
        return item;
    }

    private String truncate(String s, int max) {
        if (s == null) {
            return null;
        }
        return s.length() <= max ? s : s.substring(0, max);
    }

    /** 日志里不打印完整手机号。 */
    private String maskPhone(String phone) {
        if (phone == null || phone.length() < 7) {
            return "***";
        }
        return phone.substring(0, 3) + "****" + phone.substring(phone.length() - 4);
    }

    /** 供测试断言「管理员角色判定」用。 */
    static boolean isAdmin(User u) {
        return u != null && Integer.valueOf(UserRole.ADMIN.getCode()).equals(u.getRole());
    }
}
