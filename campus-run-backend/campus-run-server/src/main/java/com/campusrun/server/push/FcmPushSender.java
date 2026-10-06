package com.campusrun.server.push;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Jwts;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Component;

import java.io.InputStream;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Map;

/**
 * Firebase Cloud Messaging 真实推送（HTTP v1 API）。
 *
 * <p>为什么用 HTTP v1：旧的「服务器密钥 + /fcm/send」接口 Google 已于 2024 年停用，
 * 网上多数教程仍是旧版，照抄会直接 404。
 *
 * <p>鉴权流程（v1 必需，比旧版麻烦但无法绕过）：
 * 用服务账号私钥自签一个 JWT → 拿它向 {@code oauth2.googleapis.com} 换 access_token
 * → 带 {@code Authorization: Bearer <token>} 调 {@code /v1/projects/{id}/messages:send}。
 * access_token 有效期 1 小时，这里缓存并提前 5 分钟续期，避免每条消息都换一次。
 *
 * <p>启用方式：把 Firebase 控制台下载的服务账号 JSON 放到
 * {@code app.push.credentials}（默认 {@code classpath:firebase-service-account.json}
 * 或容器内路径），并设 {@code app.push.enabled=true}。
 * **该文件含私钥，必须加进 .gitignore，绝不能提交。**
 */
@Component
@ConditionalOnProperty(name = "app.push.enabled", havingValue = "true")
public class FcmPushSender implements PushSender {

    private static final Logger log = LoggerFactory.getLogger(FcmPushSender.class);

    private static final String TOKEN_URL = "https://oauth2.googleapis.com/token";
    private static final String SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
    private static final Duration HTTP_TIMEOUT = Duration.ofSeconds(10);

    private final ObjectMapper objectMapper;
    private final HttpClient httpClient;
    private final String projectId;
    private final String credentialsLocation;

    /** 缓存的 access_token 及其过期时刻（epoch 秒）。 */
    private volatile String cachedAccessToken;
    private volatile long cachedExpiresAt;
    /** 私钥解析一次即可（JSON 读取 + RSA 解析都不便宜）。 */
    private volatile PrivateKey privateKey;
    private volatile String clientEmail;

    public FcmPushSender(ObjectMapper objectMapper,
                         @Value("${app.push.credentials:}") String credentialsLocation) {
        this.objectMapper = objectMapper;
        this.credentialsLocation = credentialsLocation;
        this.projectId = readProjectIdFromCredentials();
        this.httpClient = HttpClient.newBuilder().connectTimeout(HTTP_TIMEOUT).build();
        log.info("FCM 推送已启用，projectId={}", projectId);
    }

    @Override
    public boolean isConfigured() {
        return projectId != null && !projectId.isBlank();
    }

    @Override
    public Result send(String token, String title, String body, Map<String, String> data) {
        if (!isConfigured()) {
            log.warn("FCM 未正确配置（缺少 project_id / client_email / private_key），跳过推送");
            return Result.NOT_CONFIGURED;
        }
        try {
            String accessToken = accessToken();
            if (accessToken == null) {
                return Result.RETRYABLE_FAILURE;
            }
            String payload = buildPayload(token, title, body, data);
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create("https://fcm.googleapis.com/v1/projects/"
                            + projectId + "/messages:send"))
                    .timeout(HTTP_TIMEOUT)
                    .header("Authorization", "Bearer " + accessToken)
                    .header("Content-Type", "application/json; UTF-8")
                    .POST(HttpRequest.BodyPublishers.ofString(payload, StandardCharsets.UTF_8))
                    .build();

            HttpResponse<String> response = httpClient.send(request,
                    HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));

            if (response.statusCode() == 200) {
                return Result.SUCCESS;
            }
            return classifyFailure(response.statusCode(), response.body());
        } catch (Exception e) {
            log.warn("FCM 推送异常: {}", e.getMessage());
            return Result.RETRYABLE_FAILURE;
        }
    }

    /**
     * 区分「令牌失效」与「临时故障」。
     *
     * <p>这个区分很重要：令牌失效要删掉（否则每次都白推），
     * 而临时故障删了会导致用户再也收不到通知。
     */
    private Result classifyFailure(int status, String body) {
        if (status == 404 || status == 400) {
            // UNREGISTERED / INVALID_ARGUMENT：令牌已失效
            if (body != null && (body.contains("UNREGISTERED")
                    || body.contains("INVALID_ARGUMENT")
                    || body.contains("registration-token-not-registered"))) {
                return Result.INVALID_TOKEN;
            }
        }
        if (status == 401 || status == 403) {
            // 凭证问题：access_token 可能刚过期，让缓存失效后由下一次重试
            cachedAccessToken = null;
            cachedExpiresAt = 0;
        }
        if (status == 429 || status >= 500) {
            return Result.RETRYABLE_FAILURE;
        }
        log.warn("FCM 推送失败 HTTP {}: {}", status, body);
        return Result.RETRYABLE_FAILURE;
    }

    private String buildPayload(String token, String title, String body, Map<String, String> data) throws Exception {
        var notification = objectMapper.createObjectNode();
        notification.put("title", title);
        notification.put("body", body);

        var androidNotification = objectMapper.createObjectNode();
        androidNotification.put("channel_id", "messages");
        androidNotification.put("sound", "default");

        var android = objectMapper.createObjectNode();
        android.put("priority", "HIGH");
        android.set("notification", androidNotification);

        var apnsPayload = objectMapper.createObjectNode();
        apnsPayload.put("sound", "default");
        var apnsAps = objectMapper.createObjectNode();
        apnsAps.set("payload", apnsPayload);
        var apns = objectMapper.createObjectNode();
        apns.set("headers", objectMapper.createObjectNode().put("apns-priority", "10"));
        apns.set("payload", apnsAps);

        var message = objectMapper.createObjectNode();
        message.put("token", token);
        message.set("notification", notification);
        if (data != null && !data.isEmpty()) {
            var dataNode = objectMapper.createObjectNode();
            data.forEach(dataNode::put);
            message.set("data", dataNode);
        }
        message.set("android", android);
        message.set("apns", apns);

        var root = objectMapper.createObjectNode();
        root.set("message", message);
        return objectMapper.writeValueAsString(root);
    }

    /**
     * 取 access_token（带缓存）。
     * 用服务账号私钥签一个 JWT，向 Google 换令牌。
     */
    private synchronized String accessToken() {
        long now = Instant.now().getEpochSecond();
        // 提前 5 分钟续期，避免边界上用到刚过期的令牌
        if (cachedAccessToken != null && now < cachedExpiresAt - 300) {
            return cachedAccessToken;
        }
        try {
            ensureKeyLoaded();
            String assertion = Jwts.builder()
                    .issuer(clientEmail)
                    .audience().add(TOKEN_URL).and()
                    .claim("scope", SCOPE)
                    .issuedAt(new java.util.Date(now * 1000))
                    .expiration(new java.util.Date((now + 3600) * 1000))
                    .signWith(privateKey, Jwts.SIG.RS256)
                    .compact();

            String form = "grant_type=" + enc("urn:ietf:params:oauth:grant-type:jwt-bearer")
                    + "&assertion=" + enc(assertion);
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(TOKEN_URL))
                    .timeout(HTTP_TIMEOUT)
                    .header("Content-Type", "application/x-www-form-urlencoded")
                    .POST(HttpRequest.BodyPublishers.ofString(form, StandardCharsets.UTF_8))
                    .build();
            HttpResponse<String> response = httpClient.send(request,
                    HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            if (response.statusCode() != 200) {
                log.warn("获取 FCM access_token 失败 HTTP {}: {}", response.statusCode(), response.body());
                return null;
            }
            JsonNode node = objectMapper.readTree(response.body());
            cachedAccessToken = node.path("access_token").asText(null);
            cachedExpiresAt = now + node.path("expires_in").asLong(3600);
            return cachedAccessToken;
        } catch (Exception e) {
            log.warn("获取 FCM access_token 异常: {}", e.getMessage());
            return null;
        }
    }

    private void ensureKeyLoaded() throws Exception {
        if (privateKey != null && clientEmail != null) {
            return;
        }
        JsonNode creds = readCredentials();
        clientEmail = creds.path("client_email").asText(null);
        String key = creds.path("private_key").asText(null);
        if (clientEmail == null || key == null) {
            throw new IllegalStateException("服务账号 JSON 缺少 client_email / private_key");
        }
        // PEM → PKCS#8 → RSA
        String base64 = key.replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replaceAll("\\s", "");
        byte[] der = Base64.getDecoder().decode(base64);
        privateKey = KeyFactory.getInstance("RSA").generatePrivate(new PKCS8EncodedKeySpec(der));
    }

    private String readProjectIdFromCredentials() {
        try {
            return readCredentials().path("project_id").asText(null);
        } catch (Exception e) {
            log.warn("读取 FCM 凭证失败（推送将不可用）: {}", e.getMessage());
            return null;
        }
    }

    private JsonNode readCredentials() throws Exception {
        if (credentialsLocation == null || credentialsLocation.isBlank()) {
            throw new IllegalStateException(
                    "未配置 app.push.credentials（Firebase 服务账号 JSON 路径）");
        }
        // 支持 classpath: 与容器内绝对路径
        if (credentialsLocation.startsWith("classpath:")) {
            var loader = new org.springframework.core.io.DefaultResourceLoader();
            Resource resource = loader.getResource(credentialsLocation);
            try (InputStream in = resource.getInputStream()) {
                return objectMapper.readTree(in);
            }
        }
        try (InputStream in = java.nio.file.Files.newInputStream(
                java.nio.file.Path.of(credentialsLocation))) {
            return objectMapper.readTree(in);
        }
    }

    private static String enc(String s) {
        return URLEncoder.encode(s, StandardCharsets.UTF_8);
    }
}
