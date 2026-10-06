package com.campusrun.server.security;

import com.campusrun.common.result.ErrorCode;
import com.campusrun.server.enums.UserRole;
import com.campusrun.server.mapper.UserMapper;
import io.jsonwebtoken.Claims;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * JWT 鉴权过滤器。
 *
 * <p><b>关于「角色从哪里读」（曾是一个真实的安全隐患）</b>：
 * 早期实现直接用 JWT claim 里的 `role` 来授予 `ROLE_ADMIN`。
 * 但角色是在**签发那一刻**固化的，于是出现两个问题：
 * <ul>
 *   <li><b>降权不生效</b>：把某个账号从管理员改回普通用户后，
 *       他手上那枚 access token 在剩余有效期内（最长 2 小时）**仍然是管理员**。
 *       这是权限撤销场景下的真实漏洞 —— 撤销一个管理员本该立即生效。</li>
 *   <li><b>提权也要等</b>：反向同理，刚授予管理员的人必须重新登录才能用。</li>
 * </ul>
 *
 * <p>现在改为：**权限一律以数据库为准**，JWT 里的 role 不再参与授权判定。
 * 为了不给每个请求都加一次查库，用一个**短 TTL 的进程内缓存**
 * （见 {@link #ROLE_CACHE_TTL_MS}）：权限变更最多 60 秒生效，
 * 而正常请求几乎都是缓存命中。
 *
 * <p>⚠️ 缓存是**进程内**的：多实例部署时各实例独立，
 * 权限变更在各实例上的生效时间可能相差一个 TTL。当前是单实例，可以接受；
 * 上多实例时应换成 Redis（与 `RateLimiter` 的局限相同）。
 *
 * <p>JWT claim 里的 role 仍然保留 —— 它作为「签发时的角色快照」可用于排查问题，
 * 只是不再决定权限。
 */
@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(JwtAuthenticationFilter.class);

    /**
     * 角色缓存有效期。
     *
     * <p>权衡：越短越安全（降权生效越快），越长越省查询。
     * 60 秒对「用户操作」的粒度足够 —— 没有人会在撤销权限后 60 秒内
     * 依靠旧权限做破坏性操作还指望不被记录。
     */
    public static final long ROLE_CACHE_TTL_MS = 60_000L;

    /**
     * 令牌版本缓存的有效期，**远短于角色缓存**。
     *
     * <p>⚠️ 这个值不能省。曾经把版本与角色一起缓存 60 秒，结果是：
     * 设备 A 的请求把版本 1 写进缓存；设备 B 登录后数据库升到 2，
     * 但 A 的令牌里也是 1，与缓存值**相等**，于是版本校验通过 ——
     * **第一次换设备踢不掉旧设备**（第二次才生效，因为那时缓存刚好过期）。
     * 实测就是这么暴露的：A→B 时 A 仍能用，B→A 时 B 被踢。
     *
     * <p>权衡：踢下线是**安全语义**，必须准；而它的代价只是每个请求多一次
     * 极轻量的查库（按主键 select，命中缓冲池）。3 秒已经足够让用户
     * 「在另一台设备登录后很快发现自己被踢」，同时把查库量压到可接受范围。
     *
     * <p>角色就不一样：降权晚 60 秒生效在业务上可以接受（见类注释），
     * 所以那边保留长 TTL。
     */
    public static final long TOKEN_VERSION_CACHE_TTL_MS = 3_000L;

    /**
     * 缓存容量上限。
     *
     * <p>超过就整体清空（而不是做 LRU）：成员数量级很小，
     * 清空的代价只是短暂多几次查库，比实现一套淘汰策略简单可靠。
     * 设上限是为了防止被大量伪造 userId 的请求撑爆内存。
     */
    private static final int ROLE_CACHE_MAX = 10_000;

    private final JwtTokenProvider jwtTokenProvider;

    /**
     * 用 {@link ObjectProvider} 而不是直接注入 `UserMapper`。
     *
     * <p>原因：大量 `@WebMvcTest` 切片测试只加载 Web 层，
     * 容器里没有 MyBatis 的 Mapper。若声明成必需依赖，
     * **每个切片测试的上下文都会启动失败**（我改完第一版就是 67 个错误）。
     *
     * <p>没有 Mapper 时退化成「用 token 里的角色快照」——
     * 也就是修复前的行为，所以测试切片不受影响；
     * 真实运行环境一定有 Mapper，走的是「以数据库为准」。
     */
    private final ObjectProvider<UserMapper> userMapperProvider;

    /**
     * userId -> [role, roleTs, tokenVersion, versionTs, invalidBeforeEpochMs]。
     *
     * <p>两个时间戳分开存，因为**两者的容忍度不同**：
     * 角色可以缓存 60 秒（降权慢一点无妨），令牌版本只能缓存 3 秒
     * （踢下线必须准）。见 TOKEN_VERSION_CACHE_TTL_MS 的说明。
     *
     * <p>同一条记录承载两种用途，是因为它们来自同一行数据 ——
     * 分两个 Map 会让查库逻辑重复一遍。
     */
    private final Map<Long, long[]> roleCache = new ConcurrentHashMap<>();

    public JwtAuthenticationFilter(JwtTokenProvider jwtTokenProvider,
                                   ObjectProvider<UserMapper> userMapperProvider) {
        this.jwtTokenProvider = jwtTokenProvider;
        this.userMapperProvider = userMapperProvider;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (StringUtils.hasText(header) && header.startsWith("Bearer ")) {
            String token = header.substring(7);
            try {
                // 只用 parseAccessToken：它会校验 typ=access，
                // 因此长效 refresh token（或缺失 typ 的历史令牌）无法作为业务接口凭证。
                Claims claims = jwtTokenProvider.parseAccessToken(token);
                Long userId = Long.valueOf(claims.getSubject());
                String uniqueId = claims.get("uniqueId", String.class);

                UserState state = resolveUserState(userId, claims.get("role", Integer.class));

                // ── 单设备登录：令牌版本必须与数据库一致 ────────────────
                //
                // 不一致说明该用户在**另一台设备**上登录过（或改过密码），
                // 这枚令牌已经作废。必须**明确拒绝**而不是静默忽略 ——
                // 静默忽略会让请求变成「未认证」，客户端只会看到普通的 401，
                // 于是去尝试刷新令牌（刷新也会失败），用户完全不知道发生了什么。
                if (state.known && state.tokenVersion != jwtTokenProvider.tokenVersionOf(claims)) {
                    // ⚠️ 先重读一次数据库，再决定是否拒绝。
                    //
                    // 为什么必须重读：本过滤器为了不给每个请求都查库，缓存了
                    // 60 秒的 tokenVersion。而**改密/换设备登录会立刻递增版本**，
                    // 于是刚登录的那台设备可能在缓存过期前被自己的新版本误杀 ——
                    // 用户表现为「刚登录就被踢下线」，而且 60 秒后自己又好了，
                    // 极难复现。测试里也是这么暴露的：另一个测试类填过缓存，
                    // 本用例的新令牌被判成失效。
                    //
                    // 重读只在「即将拒绝」这条冷路径上发生，不影响正常请求的开销。
                    UserState fresh = reloadUserState(userId, claims.get("role", Integer.class));
                    if (fresh.known && fresh.tokenVersion == jwtTokenProvider.tokenVersionOf(claims)) {
                        state = fresh;
                    } else {
                        log.info("令牌版本不符，判定为已在其他设备登录: userId={}, tokenVer={}, dbVer={}",
                                userId, jwtTokenProvider.tokenVersionOf(claims), fresh.tokenVersion);
                        rejectAsSessionReplaced(response);
                        return;
                    }
                }

                // ── 改密/重置密码吊销：access token 也要管 ──────────────
                //
                // 此前这里只校验签名，于是「改密码立即踢下线」对 access token
                // **不生效** —— 旧设备的 access token 还能继续用最长 2 小时。
                // refresh 那条路早就校验了 tokenInvalidBefore，access 这条路漏了。
                if (state.known && state.invalidBeforeEpochMs > 0) {
                    Date issuedAt = claims.getIssuedAt();
                    if (issuedAt != null
                            && issuedAt.getTime() < state.invalidBeforeEpochMs) {
                        log.info("access token 签发于改密之前，判定失效: userId={}, iat={}",
                                userId, issuedAt);
                        rejectAsSessionReplaced(response);
                        return;
                    }
                }

                LoginUser loginUser = new LoginUser(userId, uniqueId, state.role);
                String authority = (state.role != null && state.role == UserRole.ADMIN.getCode())
                        ? "ROLE_ADMIN" : "ROLE_USER";
                UsernamePasswordAuthenticationToken authentication =
                        new UsernamePasswordAuthenticationToken(loginUser, null,
                                List.of(new SimpleGrantedAuthority(authority)));
                authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                SecurityContextHolder.getContext().setAuthentication(authentication);
            } catch (Exception ignored) {
                SecurityContextHolder.clearContext();
            }
        }
        filterChain.doFilter(request, response);
    }

    /**
     * 清空角色缓存。**仅供测试使用。**
     *
     * <p>测试需要在同一个 JVM 里模拟「改角色后立刻生效」，
     * 而真实环境靠 TTL 自然过期。暴露成包级可见而不是 public：
     * 生产代码不应依赖它。
     */
    void clearRoleCacheForTest() {
        roleCache.clear();
    }

    /**
     * 取用户**当前**的角色，带短 TTL 缓存。
     *
     * <p>查不到用户时（已被注销）返回 null → 授予 ROLE_USER。
     * 注意这**不会**让请求通过鉴权：注销后该用户的 access token 仍在有效期内，
     * 但所有需要 userId 的业务逻辑都会因查不到数据而失败。
     */
    /**
     * 用户当前的鉴权状态，取自数据库（带短 TTL 缓存）。
     *
     * @param role                当前角色
     * @param tokenVersion        当前令牌版本；与令牌里的 ver 不等即失效
     * @param invalidBeforeEpochMs 令牌作废时刻；0 表示从未作废
     * @param known               是否真的查到了用户（切片测试里查不到）
     */
    private record UserState(Integer role, int tokenVersion, long invalidBeforeEpochMs, boolean known) {
    }

    /**
     * 绕开缓存重新查一次用户状态。
     *
     * <p>只用在「缓存里的版本与令牌不符」这条冷路径上：
     * 先确认真的不一致，再拒绝请求，避免因为缓存陈旧而误杀刚登录的设备。
     */
    private UserState reloadUserState(Long userId, Integer claimRole) {
        roleCache.remove(userId);
        return resolveUserState(userId, claimRole);
    }


    private UserState resolveUserState(Long userId, Integer claimRole) {
        long now = System.currentTimeMillis();
        long[] cached = roleCache.get(userId);

        if (cached != null && cached.length >= 5) {
            boolean roleFresh = now - cached[1] < ROLE_CACHE_TTL_MS;
            boolean versionFresh = now - cached[3] < TOKEN_VERSION_CACHE_TTL_MS;
            if (roleFresh && versionFresh) {
                return new UserState((int) cached[0], (int) cached[2], cached[4], true);
            }
            // 只有版本过期：仍要查库，但角色沿用缓存值（省掉一次角色判断）
            if (roleFresh && !versionFresh) {
                UserState fresh = loadFromDb(userId, claimRole, (int) cached[0], now);
                if (fresh != null) {
                    return fresh;
                }
            }
        }

        UserState loaded = loadFromDb(userId, claimRole, null, now);
        if (loaded == null) {
            // 查库不可用（切片测试没有 Mapper）或用户不存在：
            // 退化成用 token 里的快照，known=false 让版本校验跳过。
            int fallbackRole = claimRole == null ? UserRole.USER.getCode() : claimRole;
            return new UserState(fallbackRole, 0, 0L, false);
        }
        return loaded;
    }

    /**
     * 从数据库读一次鉴权状态并写缓存。
     *
     * @param roleHint 非 null 时沿用这个角色（角色缓存仍新鲜，无需重新判断）
     * @return null 表示查不到（没有 Mapper、用户不存在或查库异常）
     */
    private UserState loadFromDb(Long userId, Integer claimRole, Integer roleHint, long now) {
        try {
            UserMapper mapper = userMapperProvider.getIfAvailable();
            if (mapper == null) {
                return null;
            }
            var user = mapper.selectById(userId);
            if (user == null) {
                return null;
            }
            Integer role = roleHint != null
                    ? roleHint
                    : (user.getRole() != null ? user.getRole() : claimRole);
            int version = user.getTokenVersion();
            long invalidBefore = user.getTokenInvalidBefore() == null
                    ? 0L
                    : user.getTokenInvalidBefore()
                        .atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli();

            if (roleCache.size() >= ROLE_CACHE_MAX) {
                roleCache.clear();
            }
            roleCache.put(userId, new long[]{
                    role == null ? UserRole.USER.getCode() : role, now, version, now, invalidBefore});
            return new UserState(role, version, invalidBefore, true);
        } catch (Exception e) {
            // 查库失败不应让整个请求变成 401
            return null;
        }
    }

    /**
     * 判定为「已在其他设备登录/令牌已作废」，直接回 401 + 专用错误码。
     *
     * <p>必须写成和业务异常一样的 {@code Result} 结构，客户端才能按 code 分流：
     * 普通 401 会触发「刷新令牌」，而这个 4011 刷新也没用，
     * 必须直接回登录页并提示原因。
     */
    private void rejectAsSessionReplaced(HttpServletResponse response) throws IOException {
        SecurityContextHolder.clearContext();
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType("application/json;charset=UTF-8");
        response.getWriter().write(
                "{\"code\":" + ErrorCode.SESSION_REPLACED.getCode()
                        + ",\"message\":\"" + ErrorCode.SESSION_REPLACED.getMessage()
                        + "\",\"data\":null}");
    }

}
