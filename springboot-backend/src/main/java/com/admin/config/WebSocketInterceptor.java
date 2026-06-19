package com.admin.config;


import com.admin.common.utils.JwtUtil;
import com.admin.common.utils.SecureTransportUtil;
import com.admin.entity.Node;
import com.admin.service.NodeService;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.http.server.ServletServerHttpRequest;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.server.support.HttpSessionHandshakeInterceptor;

import javax.annotation.Resource;
import java.net.InetSocketAddress;
import java.util.Map;
import java.util.Objects;


@Configuration
@Slf4j
public class WebSocketInterceptor extends HttpSessionHandshakeInterceptor {

    private static final String NODE_SECRET_HEADER = "X-Flux-Node-Secret";

    @Resource
    NodeService nodeService;

    @Value("${flux.security.force-secure-node-transport:false}")
    private boolean forceSecureNodeTransport;

    @Override
    public void afterHandshake(ServerHttpRequest request, ServerHttpResponse response, WebSocketHandler wsHandler, Exception ex) {

    }

    @Override
    public boolean beforeHandshake(ServerHttpRequest request, ServerHttpResponse response, WebSocketHandler wsHandler, Map<String, Object> attributes) throws Exception {
        ServletServerHttpRequest serverHttpRequest = (ServletServerHttpRequest) request;
        String secret = serverHttpRequest.getServletRequest().getParameter("secret");
        String headerSecret = serverHttpRequest.getServletRequest().getHeader(NODE_SECRET_HEADER);
        String type = serverHttpRequest.getServletRequest().getParameter("type");
        String version = serverHttpRequest.getServletRequest().getParameter("version");
        String http = serverHttpRequest.getServletRequest().getParameter("http");
        String tls = serverHttpRequest.getServletRequest().getParameter("tls");
        String socks = serverHttpRequest.getServletRequest().getParameter("socks");
        if (type == null || type.isBlank()) {
            type = "0";
        }
        if (Objects.equals(type, "1")) {
            if (forceSecureNodeTransport && !SecureTransportUtil.isSecureRequest(serverHttpRequest.getServletRequest())) {
                log.warn("节点握手拒绝：需要 HTTPS/WSS，ip={}", getClientIp(request));
                return false;
            }
            secret = firstNonBlank(headerSecret, secret);
            log.info("节点握手请求：type={}, version={}, ip={}", type, version, getClientIp(request));
            Node node = nodeService.getOne(new QueryWrapper<Node>().eq("secret", secret));
            if (node == null) {
                log.info("节点验证失败：未找到匹配的secret");
                return false;
            }
            attributes.put("id", node.getId());
            attributes.put("nodeSecret", secret);
            attributes.put("nodeVersion", version);
            attributes.put("http",http);
            attributes.put("tls",tls);
            attributes.put("socks",socks);
            log.info("节点 {} 通过验证，版本: {}", node.getId(), version);
            // 不在这里更新状态，等到连接建立后再统一更新
        }else {
            if (secret != null && !secret.isBlank()) {
                boolean b = JwtUtil.validateToken(secret);
                if (!b) return false;
                attributes.put("id", JwtUtil.getUserIdFromToken(secret));
                attributes.put("authenticated", true);
            } else {
                attributes.put("authenticated", false);
            }
        }
        attributes.put("type", type);
        return true;
    }

    public String getClientIp(ServerHttpRequest request) {
        InetSocketAddress remoteAddress = request.getRemoteAddress();
        if (remoteAddress != null) {
            return remoteAddress.getAddress().getHostAddress();
        }
        return null;
    }

    private String firstNonBlank(String first, String second) {
        if (first != null && !first.isBlank()) {
            return first;
        }
        return second;
    }

}
