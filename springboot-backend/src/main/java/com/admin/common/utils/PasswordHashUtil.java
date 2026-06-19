package com.admin.common.utils;

import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.Locale;
import java.util.regex.Pattern;

public final class PasswordHashUtil {

    private static final Pattern LEGACY_MD5_PATTERN = Pattern.compile("^[a-fA-F0-9]{32}$");
    private static final PasswordEncoder PASSWORD_ENCODER = new BCryptPasswordEncoder(12);

    private PasswordHashUtil() {
    }

    public static String hash(String rawPassword) {
        return PASSWORD_ENCODER.encode(rawPassword);
    }

    public static boolean matches(String rawPassword, String storedPassword) {
        if (rawPassword == null || storedPassword == null || storedPassword.isBlank()) {
            return false;
        }

        if (isBcrypt(storedPassword)) {
            try {
                return PASSWORD_ENCODER.matches(rawPassword, storedPassword);
            } catch (IllegalArgumentException e) {
                return false;
            }
        }

        if (isLegacyMd5(storedPassword)) {
            return storedPassword.equalsIgnoreCase(Md5Util.md5(rawPassword));
        }

        return false;
    }

    public static boolean needsRehash(String storedPassword) {
        return storedPassword == null || !isBcrypt(storedPassword);
    }

    private static boolean isLegacyMd5(String storedPassword) {
        return LEGACY_MD5_PATTERN.matcher(storedPassword).matches();
    }

    private static boolean isBcrypt(String storedPassword) {
        if (storedPassword == null) {
            return false;
        }
        String normalized = storedPassword.toLowerCase(Locale.ROOT);
        return normalized.startsWith("$2a$")
                || normalized.startsWith("$2b$")
                || normalized.startsWith("$2y$");
    }
}
