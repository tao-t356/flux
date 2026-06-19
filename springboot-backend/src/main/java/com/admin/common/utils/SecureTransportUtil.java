package com.admin.common.utils;

import cn.hutool.core.util.StrUtil;

import javax.servlet.http.HttpServletRequest;
import java.util.Locale;

public final class SecureTransportUtil {

    private SecureTransportUtil() {
    }

    public static String normalizePanelHttpAddress(String rawAddress, boolean forceSecure) {
        if (StrUtil.isBlank(rawAddress)) {
            throw new IllegalArgumentException("服务器地址不能为空");
        }

        String address = rawAddress.trim().replaceAll("/+$", "");
        String lowerAddress = address.toLowerCase(Locale.ROOT);

        if (lowerAddress.startsWith("ws://") || lowerAddress.startsWith("wss://")) {
            throw new IllegalArgumentException("节点安装地址请填写 HTTP/HTTPS 地址，不要填写 WebSocket 地址");
        }

        if (lowerAddress.startsWith("http://")) {
            if (forceSecure) {
                throw new IllegalArgumentException("节点通信已强制 HTTPS/WSS，请在网站配置中使用 https:// 地址");
            }
            return address;
        }

        if (lowerAddress.startsWith("https://")) {
            return address;
        }

        String hostPort = GostUtil.processServerAddress(address);
        return forceSecure ? "https://" + hostPort : hostPort;
    }

    public static boolean isSecureRequest(HttpServletRequest request) {
        if (request == null) {
            return false;
        }

        if (request.isSecure() || isSecureScheme(request.getScheme())) {
            return true;
        }

        return isSecureHeader(request.getHeader("X-Forwarded-Proto"))
                || isSecureHeader(request.getHeader("X-Forwarded-Protocol"))
                || isSecureHeader(request.getHeader("X-Url-Scheme"))
                || isEnabledHeader(request.getHeader("X-Forwarded-Ssl"))
                || isEnabledHeader(request.getHeader("Front-End-Https"));
    }

    private static boolean isSecureHeader(String value) {
        if (value == null) {
            return false;
        }
        String firstValue = value.split(",")[0].trim();
        return isSecureScheme(firstValue);
    }

    private static boolean isSecureScheme(String scheme) {
        if (scheme == null) {
            return false;
        }
        String normalized = scheme.toLowerCase(Locale.ROOT);
        return "https".equals(normalized) || "wss".equals(normalized);
    }

    private static boolean isEnabledHeader(String value) {
        if (value == null) {
            return false;
        }
        String normalized = value.trim().toLowerCase(Locale.ROOT);
        return "on".equals(normalized) || "1".equals(normalized) || "true".equals(normalized);
    }
}
