package com.campusrun.server.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * 把上传目录挂成静态资源，供浏览器直接访问头像。
 *
 * <p>两个容易踩的点：
 * <ol>
 *   <li>location 必须以 {@code file:} 开头且**同时以 {@code /} 结尾**，
 *       否则 Spring 会把它当成单个文件，表现为「上传成功但图片 404」。</li>
 *   <li>不能直接用 {@code Path.toUri().toString()}：Windows 上会得到
 *       {@code file:///C:/...}，Spring 的 {@code ResourceUtils.toURL} 期望的是
 *       {@code file:/C:/...}，前者会导致资源找不到。这里手工拼成绝对路径 +
 *       正斜杠，跨平台都稳定。</li>
 * </ol>
 */
@Configuration
public class WebMvcConfig implements WebMvcConfigurer {

    private static final Logger log = LoggerFactory.getLogger(WebMvcConfig.class);

    private final String location;

    public WebMvcConfig(@Value("${app.upload-dir:uploads}") String uploadDir) {
        Path base = Paths.get(uploadDir).toAbsolutePath().normalize();
        // toAbsolutePath 之后统一成正斜杠；Windows 上 C:\a\b → C:/a/b
        String path = base.toString().replace('\\', '/');
        this.location = "file:" + path + "/";
        log.info("静态资源映射 /uploads/** -> {}", this.location);
    }

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/uploads/**").addResourceLocations(location);
    }
}
