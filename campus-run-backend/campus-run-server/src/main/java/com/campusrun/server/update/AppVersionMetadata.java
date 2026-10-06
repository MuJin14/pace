package com.campusrun.server.update;

/**
 * 从 {@code version.json} 读到的版本元数据。
 *
 * @param latest       服务端最新版本号；空串表示「没有发布任何版本」
 * @param minSupported 低于它的客户端会被强制要求更新；空串表示从不强制
 * @param changelog    更新说明，展示在更新弹窗里
 */
public record AppVersionMetadata(String latest, String minSupported, String changelog) {

    public static final AppVersionMetadata EMPTY = new AppVersionMetadata("", "", "");

    public AppVersionMetadata {
        latest = latest == null ? "" : latest.trim();
        minSupported = minSupported == null ? "" : minSupported.trim();
        changelog = changelog == null ? "" : changelog;
    }

    public boolean isEmpty() {
        return latest.isEmpty();
    }
}
