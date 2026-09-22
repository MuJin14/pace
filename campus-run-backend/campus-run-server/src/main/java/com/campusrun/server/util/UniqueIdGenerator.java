package com.campusrun.server.util;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.server.entity.User;
import com.campusrun.server.mapper.UserMapper;
import org.springframework.stereotype.Component;

import java.util.concurrent.ThreadLocalRandom;

@Component
public class UniqueIdGenerator {

    private static final int MAX_ATTEMPTS = 5;

    public String generate(UserMapper userMapper) {
        for (int i = 0; i < MAX_ATTEMPTS; i++) {
            long n = ThreadLocalRandom.current().nextLong(100_000_000L);
            String uniqueId = String.format("CR-%08d", n);
            Long count = userMapper.selectCount(
                    new LambdaQueryWrapper<User>().eq(User::getUniqueId, uniqueId));
            if (count == null || count == 0) {
                return uniqueId;
            }
        }
        throw new IllegalStateException("专属 ID 生成失败，请重试");
    }
}
