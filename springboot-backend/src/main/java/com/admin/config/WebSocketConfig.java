package com.admin.config;

import com.admin.common.utils.WebSocketServer;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

import javax.annotation.Resource;
import java.util.Arrays;


@Configuration
@EnableWebSocket
public class WebSocketConfig implements WebSocketConfigurer {

    @Resource
    private WebSocketInterceptor webSocketInterceptor;

    @Value("${cors.allowed-origins:*}")
    private String allowedOrigins;

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry webSocketHandlerRegistry) {
        webSocketHandlerRegistry
                .addHandler(myHandler(), "/system-info")
                .setAllowedOrigins(getAllowedOrigins())
                .addInterceptors(webSocketInterceptor);
    }


    @Bean
    public WebSocketHandler myHandler() {
        return new WebSocketServer();
    }

    private String[] getAllowedOrigins() {
        String configuredOrigins = allowedOrigins == null ? "*" : allowedOrigins;
        return Arrays.stream(configuredOrigins.split(","))
                .map(String::trim)
                .filter(origin -> !origin.isEmpty())
                .toArray(String[]::new);
    }
}
