package com.campusrun.server.update;

/**
 * 提供当前版本元数据。
 *
 * <p><b>为什么单独抽一个接口（真实踩坑）</b>：{@code AppVersionHeaderFilter}
 * 需要读版本号，而它挂在 Spring Security 的过滤器链上 —— 于是
 * {@code SecurityConfig} 就依赖了 {@link AppVersionStore}。
 *
 * <p>但项目里的 {@code @WebMvcTest} 切片测试只加载控制器与安全配置，
 * <b>不会加载</b> {@code @Component} 的 {@code AppVersionStore}，
 * 结果 67 个测试因为 {@code ApplicationContext} 加载失败而报错。
 *
 * <p>把依赖收窄到这个只有一个方法的接口后：
 * <ul>
 *   <li>{@code SecurityConfig} 可以用 {@code ObjectProvider} 取它，
 *       切片测试里取不到就降级为「不发版本头」——<b>一个测试都不用改</b>；</li>
 *   <li>生产环境注入的是真正的 {@link AppVersionStore}，行为不变；</li>
 *   <li>单测可以直接传一个 lambda，不必构造整个文件读取链路。</li>
 * </ul>
 */
@FunctionalInterface
public interface AppVersionProvider {

    /** 当前的版本元数据；没有配置时返回 {@link AppVersionMetadata#EMPTY}，绝不返回 null。 */
    AppVersionMetadata current();
}
