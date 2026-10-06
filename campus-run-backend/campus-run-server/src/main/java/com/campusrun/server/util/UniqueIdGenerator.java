package com.campusrun.server.util;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.server.entity.User;
import com.campusrun.server.mapper.UserMapper;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * 专属 ID 生成器：**从 0 开始递增**，与数据库主键 id 保持一致。
 *
 * <p>格式为 8 位纯数字（左侧补零），例如 {@code 00000000}、{@code 00000027}。
 *
 * <h3>历史</h3>
 *
 * <p>最早是 {@code CR-XXXXXXXX}（带字母前缀），后来改成 8 位**随机数**。
 * 随机的两个问题在实际使用中都暴露了：
 *
 * <ul>
 *   <li>用户之间看不出注册先后 —— 编号本身不携带任何信息；</li>
 *   <li>让用户「把 ID 念给别人听」时，随机数字很难记、也很难念对
 *       （{@code 76911262} 与 {@code 79611262} 听上去差不多）。</li>
 * </ul>
 *
 * <p>现在改为**递增**：编号即序号，一是有序、二是短且好念。
 * 迁移 {@code 006_sequential_ids.sql} 已把老用户的 ID 重排到这个规则上。
 *
 * <h3>与主键 id 的关系</h3>
 *
 * <p>约定为 {@code unique_id = LPAD(id, 8, '0')} —— 两者数值相同，
 * 只是展示形式不同。这里**不直接读 id 自增**，而是取现有 unique_id 的
 * 最大值 +1：插入时 id 还没生成，而 unique_id 有唯一索引可以兜底。
 *
 * <h3>并发安全</h3>
 *
 * <p>两个用户同时注册时可能算出同一个号。靠两层防护：
 * <ol>
 *   <li>数据库对 unique_id 有唯一索引，撞了会插入失败；</li>
 *   <li>本方法捕获后重试（最多 {@link #MAX_ATTEMPTS} 次），
 *       重试时会重新取最大值，因此下一次必然拿到新的号。</li>
 * </ol>
 *
 * <p>⚠️ 8 位数字的上限是 {@code 99,999,999}（约一亿）。
 * 校园场景远达不到，但真逼近上限时需要改成更宽的格式，
 * 所以那里显式抛异常而不是静默溢出。
 */
@Component
public class UniqueIdGenerator {

    private static final int MAX_ATTEMPTS = 5;

    /** 格式宽度：不足左侧补零，保证长度恒定、便于念读。 */
    private static final int WIDTH = 8;

    /** 8 位数字的上限。 */
    private static final long UPPER_BOUND = 100_000_000L;

    /**
     * 生成下一个专属 ID。
     *
     * <p>先查当前最大值再 +1。老数据里可能残留 {@code CR-} 前缀的号，
     * 解析失败时按 -1 处理（它们不参与递增序列）。
     */
    public String generate(UserMapper userMapper) {
        for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
            long next = nextNumber(userMapper);
            if (next >= UPPER_BOUND) {
                throw new IllegalStateException("专属 ID 已用尽，请改用更宽的格式");
            }
            String uniqueId = String.format("%0" + WIDTH + "d", next);
            Long count = userMapper.selectCount(
                    new LambdaQueryWrapper<User>().eq(User::getUniqueId, uniqueId));
            if (count == null || count == 0) {
                return uniqueId;
            }
            // 撞号（并发注册）：下一轮会重新取最大值，必然前进
        }
        throw new IllegalStateException("专属 ID 生成失败，请重试");
    }

    /**
     * 当前最大的序号 + 1。
     *
     * <p>只 select unique_id 列而不是整行：用户表可能有几万行，
     * 两者传输量差别很大。
     */
    private long nextNumber(UserMapper userMapper) {
        List<Object> ids = userMapper.selectObjs(
                new LambdaQueryWrapper<User>().select(User::getUniqueId));
        long max = -1;
        if (ids != null) {
            for (Object raw : ids) {
                long n = parse(raw);
                if (n > max) {
                    max = n;
                }
            }
        }
        return max + 1;
    }

    private static long parse(Object raw) {
        if (raw == null) {
            return -1;
        }
        // 兼容历史的 CR-XXXXXXXX：剥掉前缀再解析
        String s = String.valueOf(raw).trim();
        int dash = s.lastIndexOf('-');
        if (dash >= 0) {
            s = s.substring(dash + 1);
        }
        try {
            return Long.parseLong(s);
        } catch (NumberFormatException e) {
            return -1;
        }
    }
}
