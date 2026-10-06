package com.campusrun.server.filter;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 版本比较规则。
 *
 * <p><b>为什么值得单独测</b>：这段逻辑决定「服务端认不认为客户端该强制更新」。
 * 判错的后果是两个方向的死循环：
 * <ul>
 *   <li>误判「客户端太旧」→ 用户被挡在 426 外面，却又因为已经是最新版而无法更新；</li>
 *   <li>误判「客户端够新」→ 强制更新形同虚设。</li>
 * </ul>
 *
 * <p>更关键的是：<b>它必须与客户端 {@code isVersionNewer} 的规则完全一致</b>。
 * 两边规则不同就会出现「服务端要求更新、客户端认为自己已经最新」的僵局。
 * 客户端那份在 {@code test/app_version_test.dart} 里有对应用例。
 */
class AppVersionHeaderFilterTest {

    @Test
    @DisplayName("主版本更低 -> 需要强制更新")
    void olderMajor() {
        assertTrue(AppVersionHeaderFilter.isOlderThan("1.0.0", "2.0.0"));
    }

    @Test
    @DisplayName("次版本更低 -> 需要强制更新")
    void olderMinor() {
        assertTrue(AppVersionHeaderFilter.isOlderThan("1.2.0", "1.3.0"));
    }

    @Test
    @DisplayName("补丁更低 -> 需要强制更新")
    void olderPatch() {
        assertTrue(AppVersionHeaderFilter.isOlderThan("1.0.0", "1.0.1"));
    }

    @Test
    @DisplayName("相同 -> 不强制")
    void same() {
        assertFalse(AppVersionHeaderFilter.isOlderThan("1.0.0", "1.0.0"));
    }

    @Test
    @DisplayName("更高 -> 不强制")
    void newer() {
        assertFalse(AppVersionHeaderFilter.isOlderThan("1.1.0", "1.0.0"));
        assertFalse(AppVersionHeaderFilter.isOlderThan("2.0.0", "1.9.9"));
    }

    @Test
    @DisplayName("段数不同：1.1 与 1.1.0 视为相同")
    void differentSegmentCount() {
        assertFalse(AppVersionHeaderFilter.isOlderThan("1.1", "1.1.0"));
        assertFalse(AppVersionHeaderFilter.isOlderThan("1.1.0", "1.1"));
    }

    @Test
    @DisplayName("段数不同但确实更旧：1.1 低于 1.1.1")
    void differentSegmentCountOlder() {
        assertTrue(AppVersionHeaderFilter.isOlderThan("1.1", "1.1.1"));
    }

    @Test
    @DisplayName("按数值比较而不是字典序（1.10 > 1.9）")
    void numericNotLexicographic() {
        // 字典序会把 "10" 判成小于 "9"，这是最容易踩的坑
        assertFalse(AppVersionHeaderFilter.isOlderThan("1.10.0", "1.9.0"));
        assertTrue(AppVersionHeaderFilter.isOlderThan("1.9.0", "1.10.0"));
    }

    @Test
    @DisplayName("带 build 后缀（1.0.0+3）不崩")
    void buildSuffix() {
        assertFalse(AppVersionHeaderFilter.isOlderThan("1.0.0+3", "1.0.0"));
        assertFalse(AppVersionHeaderFilter.isOlderThan("1.1.0+1", "1.0.0+9"));
    }

    @Test
    @DisplayName("非数字段按 0 处理，不抛异常")
    void nonNumericSegment() {
        assertFalse(AppVersionHeaderFilter.isOlderThan("abc", "abc"));
        assertTrue(AppVersionHeaderFilter.isOlderThan("abc", "1"));
        assertFalse(AppVersionHeaderFilter.isOlderThan("1", "abc"));
    }

    @Test
    @DisplayName("空串按 0 处理，不抛异常")
    void empty() {
        assertFalse(AppVersionHeaderFilter.isOlderThan("", ""));
        assertTrue(AppVersionHeaderFilter.isOlderThan("", "1.0.0"));
        assertFalse(AppVersionHeaderFilter.isOlderThan("1.0.0", ""));
    }

    @Test
    @DisplayName("真实场景：1.7.2 相对 1.7.3 应当被强制更新")
    void realWorldCase() {
        assertTrue(AppVersionHeaderFilter.isOlderThan("1.7.2", "1.7.3"));
        assertFalse(AppVersionHeaderFilter.isOlderThan("1.7.3", "1.7.3"));
        assertFalse(AppVersionHeaderFilter.isOlderThan("1.8.0", "1.7.3"));
    }

    @Test
    @DisplayName("令牌版本缓存必须远短于角色缓存 —— 否则第一次换设备踢不掉旧设备")
    void tokenVersionCacheMustBeMuchShorterThanRoleCache() {
        // 真实故障：曾经把「令牌版本」和「角色」一起缓存 60 秒。
        // 换设备登录后数据库版本 +1，但旧设备的令牌里也是旧版本，
        // 与缓存里的旧版本**相等**，于是版本校验通过 ——
        // 第一次换设备踢不掉旧设备，第二次才生效（那时缓存刚好过期）。
        // 实测：A→B 时 A 仍能用，B→A 时 B 才被踢。
        //
        // 这里钉住「版本缓存必须显著更短」，避免以后有人为了省查询把它调回去。
        long role = com.campusrun.server.security.JwtAuthenticationFilter.ROLE_CACHE_TTL_MS;
        long version =
                com.campusrun.server.security.JwtAuthenticationFilter.TOKEN_VERSION_CACHE_TTL_MS;

        assertTrue(version < role,
                "版本缓存必须比角色缓存短，实际 version=" + version + " role=" + role);
        assertTrue(version <= 10_000L,
                "版本缓存超过 10 秒的话，「在另一台设备登录」的用户会感觉旧设备没被踢下线，"
                        + "实际=" + version + "ms");
    }
}
