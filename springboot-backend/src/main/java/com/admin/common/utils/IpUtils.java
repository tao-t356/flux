package com.admin.common.utils;

import javax.servlet.http.HttpServletRequest;

public class IpUtils {

    public static String getIpAddr(HttpServletRequest request) {
        String ipAddress = null;
        try {
            if (SecureTransportUtil.isTrustedProxySource(request)) {
                ipAddress = request.getHeader("x-forwarded-for");
                if (isBlankOrUnknown(ipAddress)) {
                    ipAddress = request.getHeader("Proxy-Client-IP");
                }
                if (isBlankOrUnknown(ipAddress)) {
                    ipAddress = request.getHeader("WL-Proxy-Client-IP");
                }
            }
            if (isBlankOrUnknown(ipAddress)) {
                ipAddress = request.getRemoteAddr();
            }
            if (ipAddress != null && ipAddress.contains(",")) {
                ipAddress = ipAddress.substring(0, ipAddress.indexOf(","));
            }
        } catch (Exception e) {
            ipAddress="";
        }
        return ipAddress;
    }

    private static boolean isBlankOrUnknown(String value) {
        return value == null || value.isBlank() || "unknown".equalsIgnoreCase(value);
    }
}
