package com.campusrun.server.service;

import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.AdminUserItem;
import com.campusrun.server.dto.response.PasswordResetRequestItem;
import com.campusrun.server.dto.response.PasswordResetResult;

import java.util.List;

/**
 * 管理员后台：用户查询与密码协助重置。
 *
 * <p><b>为什么需要它</b>：App 没有邮箱字段、也没有短信服务，用户忘记密码后
 * 没有任何自助找回的途径。与其硬上短信（要实名、要备案、要按条付费），
 * 不如给少量受信任账号开管理员权限，由管理员协助 —— 传播范围小的时候这是
 * 成本最低、能立刻可用的方案。
 *
 * <p><b>安全边界</b>（都有测试固化）：
 * <ul>
 *   <li>所有写操作都要求 `ROLE_ADMIN`（在 Controller 上 `@PreAuthorize`）；</li>
 *   <li>重置密码<b>不需要旧密码</b>（用户就是忘了才来的），但会
 *       <b>作废该用户全部 refresh token</b>，防止旧会话继续可用；</li>
 *   <li>管理员<b>不能</b>重置自己的密码走这条路径 —— 他应该用「修改密码」
 *       并提供旧密码，避免管理员账号被滥用为「无需旧密码改自己密码」的通道；</li>
 *   <li>临时密码随机生成，且只在响应里返回一次（库里只存 BCrypt 哈希）。</li>
 * </ul>
 */
public interface AdminUserService {

    /** 分页查询用户。{@code keyword} 可匹配手机号 / 昵称 / 专属 ID（空则不筛）。 */
    PageResponse<AdminUserItem> listUsers(String keyword, long page, long size);

    /**
     * 直接为指定用户重置密码（管理员主动发起，无需对方申请）。
     *
     * @return 含一次性临时密码
     */
    PasswordResetResult resetPassword(Long operatorId, Long targetUserId);

    /** 用户自助发起重置申请（登录前也能调用，用手机号定位账号）。 */
    void createResetRequest(String phone, String note);

    /** 用户查看自己最近一次申请的状态（登录后调用）。 */
    PasswordResetRequestItem myLatestRequest(Long userId);

    /** 管理员查看申请列表；{@code status} 为 null 时返回全部。 */
    List<PasswordResetRequestItem> listRequests(Integer status);

    /** 管理员处理申请：重置密码并把申请标记为已处理。 */
    PasswordResetResult handleRequest(Long operatorId, Long requestId);

    /** 管理员拒绝申请（例如申请人无法证明账号归属）。 */
    void rejectRequest(Long operatorId, Long requestId);
}
