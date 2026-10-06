package com.campusrun.server.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * App 自更新接口。
 *
 * <p>重点验证那条**很容易写错、又很难在真机上发现**的规则：
 * 「版本号声明了，但 APK 还没放好」时不能提示更新 ——
 * 否则用户点了下载拿到 404，比不提示更糟。
 *
 * <p>版本元数据从 {@code <apk 目录>/version.json} 读取（不是配置项），
 * 所以这里用临时目录验证真实读写路径。
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties = "app-version.apk-path=${java.io.tmpdir}/campus-run-apk-test/app.apk")
class AppVersionControllerTest {

    private static final Path APK_DIR =
            Path.of(System.getProperty("java.io.tmpdir"), "campus-run-apk-test");
    private static final Path APK = APK_DIR.resolve("app.apk");
    private static final Path META = APK_DIR.resolve("version.json");

    @Autowired
    private MockMvc mockMvc;
    @Autowired
    private ObjectMapper objectMapper;

    @BeforeEach
    void setUp() throws IOException {
        Files.createDirectories(APK_DIR);
        Files.deleteIfExists(APK);
        Files.deleteIfExists(META);
    }

    @AfterEach
    void tearDown() throws IOException {
        Files.deleteIfExists(APK);
        Files.deleteIfExists(META);
    }

    private JsonNode fetchVersion() throws Exception {
        var response = mockMvc.perform(get("/api/v1/app/version"))
                .andExpect(status().isOk())
                .andReturn().getResponse();
        // ⚠️ 必须显式指定 UTF-8：MockMvc 的 getContentAsString() 默认按
        // ISO-8859-1 解码，中文 changelog 会被解成乱码，
        // 于是「包含 管理后台」这类断言会假失败（真实响应本身没坏）。
        return objectMapper.readTree(response.getContentAsString(StandardCharsets.UTF_8));
    }

    private void writeMeta(String latest, String minSupported, String changelog)
            throws IOException {
        String json = objectMapper.writeValueAsString(java.util.Map.of(
                "latest", latest, "minSupported", minSupported, "changelog", changelog));
        Files.writeString(META, json);
    }

    private void writeApk(byte[] content) throws IOException {
        Files.write(APK, content);
    }

    @Test
    void noApkNoMeta_reportsNothingToUpdate() throws Exception {
        JsonNode root = fetchVersion();
        assertEquals(0, root.get("code").asInt());
        JsonNode data = root.get("data");
        // 结构必须完整：客户端不该为了「没配置」写分支
        assertEquals("", data.get("latest").asText());
        assertEquals("", data.get("minSupported").asText());
        assertEquals("", data.get("changelog").asText());
        assertFalse(data.get("apkReady").asBoolean());
        assertTrue(data.get("apkUrl").isNull());
    }

    @Test
    void metaWithoutApk_doesNotAdvertiseUpdate() throws Exception {
        // 这是最关键的一条：**声明了新版本但包还没上传**
        writeMeta("9.9.9", "1.0.0", "还没传包");

        JsonNode data = fetchVersion().get("data");
        assertEquals("9.9.9", data.get("latest").asText(), "版本号应当如实返回");
        assertFalse(data.get("apkReady").asBoolean(),
                "APK 不存在时必须 apkReady=false");
        assertTrue(data.get("apkUrl").isNull(),
                "没有可下载的包就不该给下载地址 —— 否则用户点下载拿到 404");
    }

    @Test
    void apkWithoutMeta_reportsApkReadyButNoVersion() throws Exception {
        writeApk(new byte[]{1, 2, 3});

        JsonNode data = fetchVersion().get("data");
        assertTrue(data.get("apkReady").asBoolean());
        // 版本号为空 → 客户端会跳过提示（没有「新版本」可谈）
        assertEquals("", data.get("latest").asText());
    }

    @Test
    void apkAndMeta_reportsFullInfo() throws Exception {
        writeApk(new byte[1024]);
        writeMeta("1.2.0", "1.0.0", "1. 修复距离\n2. 新增管理后台");

        JsonNode data = fetchVersion().get("data");
        assertEquals("1.2.0", data.get("latest").asText());
        assertEquals("1.0.0", data.get("minSupported").asText());
        assertTrue(data.get("changelog").asText().contains("管理后台"));
        assertTrue(data.get("apkReady").asBoolean());
        assertTrue(data.get("apkUrl").asText().endsWith("/api/v1/app/download"));
        assertEquals(1024, data.get("apkSizeBytes").asInt());
    }

    @Test
    void brokenMetaJson_degradesToNoUpdateInsteadOf500() throws Exception {
        writeApk(new byte[]{1, 2, 3});
        Files.writeString(META, "{ this is not valid json");

        // 发版元数据写坏了不该让版本接口 500 ——
        // 那会让**所有**客户端在启动时看到异常
        JsonNode root = fetchVersion();
        assertEquals(0, root.get("code").asInt());
        assertEquals("", root.get("data").get("latest").asText());
    }

    @Test
    void download_servesApkWithInstallableContentType() throws Exception {
        byte[] content = new byte[]{0x50, 0x4B, 0x03, 0x04}; // zip magic (APK 是 zip)
        writeApk(content);

        mockMvc.perform(get("/api/v1/app/download"))
                .andExpect(status().isOk())
                .andExpect(header().string("Content-Type",
                        "application/vnd.android.package-archive"))
                .andExpect(header().string("Content-Length", String.valueOf(content.length)));
    }

    @Test
    void download_withoutApk_returns404NotServerError() throws Exception {
        // 客户端把 404 当「暂时没有更新」，比当「服务器故障」合理
        mockMvc.perform(get("/api/v1/app/download"))
                .andExpect(status().isNotFound());
    }
}
