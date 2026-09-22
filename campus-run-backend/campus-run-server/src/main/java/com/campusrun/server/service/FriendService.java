package com.campusrun.server.service;

import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.FriendItemResponse;
import com.campusrun.server.dto.response.FriendRequestResponse;
import com.campusrun.server.dto.response.UserBriefResponse;

import java.util.List;

public interface FriendService {

    /**
     * 按唯一 ID 或昵称搜索用户。
     *
     * @param userId  当前用户 ID
     * @param keyword 搜索关键词
     * @param page    页码（从 1 起）
     * @param size    每页条数
     * @return 用户分页列表
     * @throws BusinessException 关键词为空
     */
    PageResponse<UserBriefResponse> search(Long userId, String keyword, long page, long size);

    /**
     * 发送好友申请；若对方已向你发起 PENDING 申请则自动接受，双方成为好友。
     *
     * @param userId       发起用户 ID
     * @param targetUserId 目标用户 ID
     * @throws BusinessException 不能添加自己、目标不存在或申请已存在
     */
    void sendRequest(Long userId, Long targetUserId);

    /**
     * 接受好友申请，建立双向好友关系。
     *
     * @param userId    当前用户 ID（须为被申请人）
     * @param requestId 好友申请 ID
     * @throws BusinessException 申请不存在
     */
    void acceptRequest(Long userId, Long requestId);

    /**
     * 拒绝好友申请，删除 PENDING 记录。
     *
     * @param userId    当前用户 ID（须为被申请人）
     * @param requestId 好友申请 ID
     * @throws BusinessException 申请不存在
     */
    void rejectRequest(Long userId, Long requestId);

    /**
     * 查询收到的待处理好友申请。
     *
     * @param userId 当前用户 ID
     * @return 待处理申请列表
     */
    List<FriendRequestResponse> incomingRequests(Long userId);

    /**
     * 查询好友列表。
     *
     * @param userId 当前用户 ID
     * @return 好友列表
     */
    List<FriendItemResponse> friendList(Long userId);

    /**
     * 删除好友，移除双向关系。
     *
     * @param userId   当前用户 ID
     * @param friendId 好友用户 ID
     * @throws BusinessException 对方不是好友
     */
    void deleteFriend(Long userId, Long friendId);
}
