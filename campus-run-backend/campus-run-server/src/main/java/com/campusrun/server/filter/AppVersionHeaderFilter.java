package com.campusrun.server.filter;

import com.campusrun.server.update.AppVersionMetadata;
import com.campusrun.server.update.AppVersionProvider;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * 服务端权威的更新信号：在**每一个** API 响应上附带最新版本信息。
 *
 * <h3>为什么需要它（真实故障）</h3>
 *
 * <p>原来的做法是「客户端启动时主动查一次 {@code /api/v1/app/version}」。
 * 这个模式有一个致命弱点：<b>要不要提示更新，完全取决于客户端记不记得去查</b>。
 * 实际就出了事故 —— 检查被写在登录后的主界面里，于是
 * <b>没登录的用户永远不知道有新版本</b>；而且弹窗那一步还因为 context 用错
 * 抛异常被静默吞掉，最终「更新弹窗从来没出现过」。
 *
 * <p>改成服务端在每个响应上带信号之后：
 * <ul>
 *   <li><b>不依赖客户端主动查询</b> —— 只要 App 还连着服务器（能登录、能刷列表），
 *       它就一定会收到这个头；</li>
 *   <li><b>零额外请求</b> —— 挂在已有请求上，不增加流量与延迟；</li>
 *   <li><b>策略由服务端决定</b> —— 想强推某个版本，改 {@code version.json} 即可，
 *       不用重新发版。</li>
 * </ul>
 *
 * <h3>请求头 X-App-Version</h3>
 *
 * <p>新客户端会带上自己的版本号。带上时，服务端可以：
 * <ul>
 *   <li>在响应头里给出 {@code X-App-Latest}；</li>
 *   <li>若该版本低于 {@code minSupported}，直接返回 <b>426 Upgrade Required</b>，
 *       并附上最新版本与更新说明。</li>
 * </ul>
 *
 * <p>不带该头（旧客户端、浏览器、脚本）时<b>不做任何拦截</b>，
 * 只是照样附上版本头 —— 旧客户端没有读取它的代码，行为与之前完全一致，
 * 所以这个改动对线上是安全的。
 *
 * <h3>为什么用 426</h3>
 *
 * <p>426 Upgrade Required 是 HTTP 标准里语义最贴合的状态码。
 * 不复用 401：那会让客户端走进「刷新令牌」的流程，拿一个假错误去换 token，
 * 反而把问题复杂化。
 *
 * <h3>为什么不用 @Component 自动注册（真实踩坑）</h3>
 *
 * <p>这里踩过两次坑，最终形态是「挂在 Security 过滤器链上 + 依赖收窄成接口」：
 *
 * <ol>
 *   <li>最初标 {@code @Component}：Spring Boot 把它<b>自动注册为 servlet filter</b>，
 *       所有 {@code @WebMvcTest} 都要能构造它，而切片测试不加载
 *       {@code AppVersionStore} —— 67 个测试 {@code ApplicationContext failure}；</li>
 *   <li>改成 {@code SecurityConfig} 里的 {@code @Bean}：同样的问题，
 *      因为 Bean 一样要能被构造；</li>
 *   <li>现在：直接 {@code new} 进 Security 过滤器链（不做 Bean），
 *       并且依赖收窄成 {@link AppVersionProvider} 函数式接口 ——
 *       {@code SecurityConfig} 用 {@code ObjectProvider} 取它，
 *       切片测试取不到就降级为「不发版本头」。</li>
 * </ol>
 *
 * <p>结论：<b>切片测试里取不到的依赖，不要用来构造一个必须存在的 Bean</b>。
 *
 * <h3>为什么只包裹 /api/ 路径</h3>
 *
 * <p>APK 下载（{@code /api/v1/app/download}，54MB）如果被这个
 * {@code OncePerRequestFilter} 包住，响应提交时读 {@code X-App-Version}
 * 等逻辑会落在<strong>大文件传输路径</strong>上，属于没必要的风险。
 * 版本信号对下载请求也没有意义（下载它就是为了更新）。
 */
public class AppVersionHeaderFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(AppVersionHeaderFilter.class);

    /** 客户端上报自身版本的请求头。 */
    public static final String HEADER_CLIENT_VERSION = "X-App-Version";

    /** 服务端下发的最新版本。 */
    public static final String HEADER_LATEST = "X-App-Latest";

    /** 服务端下发的强制更新下限。 */
    public static final String HEADER_MIN_SUPPORTED = "X-App-Min-Supported";

    /** 是否需要强制更新（{@code true} 时客户端应阻止继续使用）。 */
    public static final String HEADER_UPDATE_REQUIRED = "X-App-Update-Required";

    /** 426 Upgrade Required（RFC 7231）。jakarta.servlet 没有提供该常量。 */
    private static final int UPGRADE_REQUIRED = 426;

    /** 暴露给浏览器 JS（同源请求其实不需要，但便于排查）。 */
    private static final String EXPOSE_HEADERS =
            HEADER_LATEST + ", " + HEADER_MIN_SUPPORTED + ", " + HEADER_UPDATE_REQUIRED;

    private final AppVersionProvider store;

    public AppVersionHeaderFilter(AppVersionProvider store) {
        this.store = store;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String uri = request.getRequestURI();
        if (uri == null || !uri.startsWith("/api/")) {
            return true;
        }
        // 下载接口不拦截：54MB 的流不该被额外逻辑包裹
        return uri.startsWith("/api/v1/app/download");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        AppVersionMetadata meta = store.current();

        // 版本元数据没配好（文件缺失/损坏）时不干预任何请求，
        // 只记一次日志 —— 发版元数据坏掉不该让所有接口异常。
        if (meta == null || meta.latest().isEmpty()) {
            chain.doFilter(request, response);
            return;
        }

        String clientVersion = trim(request.getHeader(HEADER_CLIENT_VERSION));

        response.setHeader(HEADER_LATEST, meta.latest());
        response.setHeader("Access-Control-Expose-Headers", EXPOSE_HEADERS);

        if (clientVersion.isEmpty()) {
            // 旧客户端：不拦截，行为与改动前完全一致
            chain.doFilter(request, response);
            return;
        }

        if (!meta.minSupported().isEmpty()) {
            response.setHeader(HEADER_MIN_SUPPORTED, meta.minSupported());

            if (isOlderThan(clientVersion, meta.minSupported())) {
                response.setHeader(HEADER_UPDATE_REQUIRED, "true");
                // jakarta.servlet 没有 SC_UPGRADE_REQUIRED 常量，写 RFC 7231 定义的字面量
                response.setStatus(UPGRADE_REQUIRED);
                response.setContentType("application/json;charset=UTF-8");
                response.getWriter().write(forceUpdateBody(meta));
                log.info("拒绝 {} 的请求：版本 {} 低于强制更新下限 {}",
                        request.getRequestURI(), clientVersion, meta.minSupported());
                return;
            }
        }

        chain.doFilter(request, response);
    }

    /** 强制更新的响应体，沿用项目统一的 {@code Result} 结构，客户端无需特殊解析。 */
    private static String forceUpdateBody(AppVersionMetadata meta) {
        return "{\"code\":426,\"message\":\"当前版本过低，请更新后再使用\",\"data\":{"
                + "\"latest\":\"" + escape(meta.latest()) + "\","
                + "\"minSupported\":\"" + escape(meta.minSupported()) + "\","
                + "\"updateRequired\":true,"
                + "\"changelog\":\"" + escape(meta.changelog()) + "\"}}";
    }

    private static String escape(String s) {
        if (s == null) {
            return "";
        }
        StringBuilder sb = new StringBuilder(s.length() + 16);
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> {
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
                }
            }
        }
        return sb.toString();
    }

    private static String trim(String s) {
        return s == null ? "" : s.trim();
    }

    /**
     * {@code candidate} 是否比 {@code base} 旧。
     *
     * <p>与客户端 {@code isVersionNewer} 保持同一套规则：按 {@code .} 切分逐段比数字，
     * 缺失段按 0，非数字段按 0（这样 {@code 1.0.0+3} 这类 Flutter 构建后缀不会崩）。
     * 两边规则不一致会导致「服务端认为该强推、客户端认为自己够新」的死循环。
     */
    static boolean isOlderThan(String candidate, String base) {
        int len = Math.max(candidate.split("\\.").length, base.split("\\.").length);
        for (int i = 0; i < len; i++) {
            int a = segment(candidate, i);
            int b = segment(base, i);
            if (a < b) {
                return true;
            }
            if (a > b) {
                return false;
            }
        }
        return false;
    }

    private static int segment(String version, int index) {
        String[] parts = version.split("\\.");
        if (index >= parts.length) {
            return 0;
        }
        String p = parts[index].trim();
        int end = 0;
        while (end < p.length() && Character.isDigit(p.charAt(end))) {
            end++;
        }
        if (end == 0) {
            return 0;
        }
        try {
            return Integer.parseInt(p.substring(0, end));
        } catch (NumberFormatException e) {
            return 0;
        }
    }
}
