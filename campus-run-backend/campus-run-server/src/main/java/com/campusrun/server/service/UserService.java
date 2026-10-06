package com.campusrun.server.service;

import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.request.ChangePasswordRequest;
import com.campusrun.server.dto.request.UpdateProfileRequest;
import com.campusrun.server.dto.response.ActivitySummaryResponse;
import com.campusrun.server.dto.response.UserBadgeResponse;
import com.campusrun.server.dto.response.UserInfoResponse;
import com.campusrun.server.dto.response.UserProfileResponse;

import java.util.List;

public interface UserService {

    /**
     * 查询当前用户信息。
     *
     * @param userId 用户 ID
     * @return 用户信息
     * @throws BusinessException 用户不存在
     */
    UserInfoResponse getCurrentUser(Long userId);

    /**
     * 查询任意用户的公开主页（类似微信的个人资料页）。
     *
     * <p>刻意不返回手机号：手机号只在「我的」页对自己可见，
     * 不应因为能搜到某个人就把它暴露出来。
     *
     * @param me     当前登录用户（用于计算 relation）
     * @param target 目标用户
     * @return 主页信息，含与 {@code me} 的关系
     * @throws BusinessException 目标用户不存在
     */
    UserProfileResponse getProfile(Long me, Long target);

    /**
     * 更新自己的资料（昵称 / 头像）。字段为 null 表示不修改。
     *
     * @param userId  当前登录用户
     * @param request 待更新字段
     * @return 更新后的自己的信息
     * @throws BusinessException 昵称非法或用户不存在
     */
    UserInfoResponse updateProfile(Long userId, UpdateProfileRequest request);

    /**
     * 查看某人的运动记录。
     *
     * <p>**仅好友可见**：不是好友抛 403 而不是返回空列表 —— 空列表会让调用方
     * 分不清「没权限」和「对方没记录」，也会让前端误显示空态。
     *
     * @param me     当前登录用户
     * @param target 目标用户
     * @throws BusinessException 目标不存在，或双方不是好友
     */
    PageResponse<ActivitySummaryResponse> listUserActivities(Long me, Long target,
                                                             Integer type, long page, long size);

    /**
     * 查看某人的勋章墙。**仅好友可见**（同 {@link #listUserActivities}）。
     *
     * @param me     当前登录用户
     * @param target 目标用户
     * @throws BusinessException 目标不存在，或双方不是好友
     */
    List<UserBadgeResponse> listUserBadges(Long me, Long target);

    /**
     * 注销账号：级联删除该用户的全部业务数据（运动记录、好友关系、消息、
     * 榜单数据、目标、勋章、统计），最后删除用户行。
     *
     * <p>这是合规要求（《个人信息保护法》赋予用户的删除权），也是应用商店审核项。
     * 删除不可恢复，故调用方（前端）必须做二次确认。
     *
     * @param userId 用户 ID
     * @throws BusinessException 用户不存在
     */
    void deleteAccount(Long userId);

    /**
     * 修改密码（需验证旧密码）。
     *
     * <p>成功后会写入 {@code token_invalid_before = now()}，使**此前签发的所有
     * refresh token 立即失效** —— 否则改密挡不住已经拿到长效令牌的人，
     * 也就等于没改。这同时也实现了「改密即踢下线」。
     *
     * @param userId  当前登录用户
     * @param request 旧密码 + 新密码
     * @throws BusinessException 旧密码错误 / 新密码与旧密码相同 / 用户不存在
     */
    void changePassword(Long userId, ChangePasswordRequest request);
}
