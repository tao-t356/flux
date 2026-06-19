package com.admin.common.security;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.Locale;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class LoginAttemptLimiter {

    private final ConcurrentHashMap<String, AttemptState> attempts = new ConcurrentHashMap<>();

    @Value("${flux.security.login.max-attempts:5}")
    private int maxAttempts;

    @Value("${flux.security.login.window-seconds:300}")
    private long windowSeconds;

    @Value("${flux.security.login.lock-seconds:900}")
    private long lockSeconds;

    public boolean isBlocked(String username, String clientIp) {
        if (maxAttempts <= 0) {
            return false;
        }

        AttemptState state = attempts.get(key(username, clientIp));
        if (state == null) {
            return false;
        }

        long now = System.currentTimeMillis();
        if (state.lockedUntil > now) {
            return true;
        }

        if (isWindowExpired(state, now)) {
            attempts.remove(key(username, clientIp), state);
        }

        return false;
    }

    public long remainingLockSeconds(String username, String clientIp) {
        AttemptState state = attempts.get(key(username, clientIp));
        if (state == null) {
            return 0;
        }
        long remainingMillis = state.lockedUntil - System.currentTimeMillis();
        return Math.max(0, (remainingMillis + 999) / 1000);
    }

    public void recordFailure(String username, String clientIp) {
        if (maxAttempts <= 0) {
            return;
        }

        long now = System.currentTimeMillis();
        attempts.compute(key(username, clientIp), (k, state) -> {
            if (state == null || isWindowExpired(state, now)) {
                state = new AttemptState(now);
            }

            state.failures++;
            if (state.failures >= maxAttempts) {
                state.lockedUntil = now + lockSeconds * 1000;
            }
            return state;
        });
    }

    public void recordSuccess(String username, String clientIp) {
        attempts.remove(key(username, clientIp));
    }

    private boolean isWindowExpired(AttemptState state, long now) {
        return state.firstAttemptAt + windowSeconds * 1000 <= now;
    }

    private String key(String username, String clientIp) {
        String safeUsername = username == null ? "" : username.trim().toLowerCase(Locale.ROOT);
        String safeClientIp = clientIp == null || clientIp.isBlank() ? "unknown" : clientIp.trim();
        return safeUsername + "|" + safeClientIp;
    }

    private static class AttemptState {
        private final long firstAttemptAt;
        private int failures;
        private long lockedUntil;

        private AttemptState(long firstAttemptAt) {
            this.firstAttemptAt = firstAttemptAt;
        }
    }
}
