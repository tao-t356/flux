package com.admin.service.impl;

import cn.hutool.core.util.IdUtil;
import cn.hutool.core.util.StrUtil;
import com.admin.common.dto.GostDto;
import com.admin.common.dto.NodeDto;
import com.admin.common.dto.NodeUpdateDto;
import com.admin.common.lang.R;
import com.admin.common.utils.SecureTransportUtil;
import com.admin.common.utils.WebSocketServer;
import com.admin.entity.*;
import com.admin.mapper.NodeMapper;
import com.admin.mapper.TunnelMapper;
import com.admin.service.*;
import com.alibaba.fastjson.JSONObject;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import org.springframework.beans.BeanUtils;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.util.List;
import java.util.Objects;
import java.util.regex.Pattern;

import org.springframework.beans.factory.annotation.Value;

@Service
public class NodeServiceImpl extends ServiceImpl<NodeMapper, Node> implements NodeService {


    @Resource
    @Lazy
    private TunnelService tunnelService;

    @Resource
    ViteConfigService viteConfigService;

    @Resource
    ChainTunnelService chainTunnelService;

    @Value("${flux.release-version:2.0.9-beta}")
    private String releaseVersion;

    @Value("${flux.release-repo:tao-t356/flux}")
    private String releaseRepo;

    @Value("${flux.github-proxy:}")
    private String githubProxy;

    @Value("${flux.security.force-secure-node-transport:false}")
    private boolean forceSecureNodeTransport;

    @Value("${flux.panel.access-host:}")
    private String panelAccessHost;

    @Value("${flux.panel.backend-port:6365}")
    private String panelBackendPort;


    @Override
    public R createNode(NodeDto nodeDto) {
        validatePortRange(nodeDto.getPort());
        Node node = new Node();
        node.setSecret(IdUtil.simpleUUID());
        node.setStatus(0);
        node.setPort(nodeDto.getPort());
        node.setName(nodeDto.getName());
        node.setServerIp(nodeDto.getServerIp());
        long currentTime = System.currentTimeMillis();
        node.setCreatedTime(currentTime);
        node.setUpdatedTime(currentTime);
        node.setInterfaceName(nodeDto.getInterfaceName());
        this.save(node);
        return R.ok();
    }

    @Override
    public R getAllNodes() {
        List<Node> nodeList = this.list(new QueryWrapper<Node>().orderByDesc("status"));
        nodeList.forEach(node -> node.setSecret(null));
        return R.ok(nodeList);
    }

    @Override
    public R updateNode(NodeUpdateDto nodeUpdateDto) {
        Node node = this.getById(nodeUpdateDto.getId());
        if (node == null) {
            return R.err("节点不存在");
        }

        boolean online = node.getStatus() != null && node.getStatus() == 1;
        Integer newHttp = nodeUpdateDto.getHttp();
        Integer newTls = nodeUpdateDto.getTls();
        Integer newSocks = nodeUpdateDto.getSocks();

        boolean httpChanged = newHttp != null && !newHttp.equals(node.getHttp());
        boolean tlsChanged = newTls != null && !newTls.equals(node.getTls());
        boolean socksChanged = newSocks != null && !newSocks.equals(node.getSocks());

        if (online && (httpChanged || tlsChanged || socksChanged)) {
            JSONObject req = new JSONObject();
            req.put("http", newHttp);
            req.put("tls", newTls);
            req.put("socks", newSocks);

            GostDto gostResult = WebSocketServer.send_msg(node.getId(), req, "SetProtocol");
            if (!Objects.equals(gostResult.getMsg(), "OK")){
                return R.err(gostResult.getMsg());
            }
        }



        Node updateNode = buildUpdateNode(nodeUpdateDto);
        this.updateById(updateNode);
        return R.ok();
    }

    @Override
    public R deleteNode(Long id) {
        Node node = this.getById(id);
        if (node == null) {
            return R.err("节点不存在");
        }

        List<ChainTunnel> list = chainTunnelService.list(new QueryWrapper<ChainTunnel>().eq("node_id", id).groupBy("tunnel_id"));
        for (ChainTunnel tunnel : list) {
            tunnelService.deleteTunnel(tunnel.getTunnelId());
        }
        this.removeById(id);
        return R.ok();
    }


    @Override
    public R getInstallCommand(Long id) {
        Node node = this.getById(id);
        if (node == null) {
            return R.err("节点不存在");
        }
        String panelBackendAddress = resolvePanelBackendAddress();
        if (StrUtil.isBlank(panelBackendAddress)) {
            return R.err("未检测到面板后端地址，请重新运行面板更新脚本");
        }
        StringBuilder command = new StringBuilder();
        command.append("curl -fL --retry 3 ")
                .append(shellQuote(buildInstallScriptUrl()))
                .append(" -o ./install.sh && chmod +x ./install.sh && ");
        String processedServerAddr;
        try {
            processedServerAddr = SecureTransportUtil.normalizePanelHttpAddress(panelBackendAddress, forceSecureNodeTransport);
        } catch (IllegalArgumentException e) {
            return R.err(e.getMessage());
        }
        if (processedServerAddr.toLowerCase().startsWith("http://")) {
            command.append("FLUX_ALLOW_INSECURE_NODE_TRANSPORT=1 ");
        }
        command.append("./install.sh")
                .append(" -a ").append(shellQuote(processedServerAddr))  // 服务器地址
                .append(" -s ").append(shellQuote(node.getSecret()));    // 节点密钥
        return R.ok(command);

    }

    private String resolvePanelBackendAddress() {
        ViteConfig viteConfig = viteConfigService.getOne(new QueryWrapper<ViteConfig>().eq("name", "ip"));
        if (viteConfig != null && StrUtil.isNotBlank(viteConfig.getValue())) {
            return viteConfig.getValue();
        }
        return buildDefaultPanelBackendAddress();
    }

    private String buildDefaultPanelBackendAddress() {
        if (StrUtil.isBlank(panelAccessHost)) {
            return "";
        }

        String host = panelAccessHost.trim()
                .replaceFirst("(?i)^https?://", "")
                .replaceAll("/.*$", "");
        if (StrUtil.isBlank(host)) {
            return "";
        }
        if (hasExplicitPort(host)) {
            return host;
        }
        return host + ":" + StrUtil.blankToDefault(panelBackendPort, "6365");
    }

    private boolean hasExplicitPort(String host) {
        if (host.startsWith("[")) {
            return host.matches("^\\[[^]]+]:\\d+$");
        }
        int firstColon = host.indexOf(':');
        int lastColon = host.lastIndexOf(':');
        return firstColon > -1 && firstColon == lastColon && lastColon < host.length() - 1;
    }


    private Node buildUpdateNode(NodeUpdateDto nodeUpdateDto) {
        validatePortRange(nodeUpdateDto.getPort());
        Node node = new Node();
        node.setId(nodeUpdateDto.getId());
        node.setName(nodeUpdateDto.getName());
        node.setServerIp(nodeUpdateDto.getServerIp());
        node.setPort(nodeUpdateDto.getPort());
        node.setHttp(nodeUpdateDto.getHttp());
        node.setTls(nodeUpdateDto.getTls());
        node.setSocks(nodeUpdateDto.getSocks());
        node.setUpdatedTime(System.currentTimeMillis());
        node.setInterfaceName(nodeUpdateDto.getInterfaceName());
        node.setTcpListenAddr(nodeUpdateDto.getTcpListenAddr());
        node.setUdpListenAddr(nodeUpdateDto.getUdpListenAddr());
        return node;
    }

    private String buildInstallScriptUrl() {
        String url = "https://github.com/" + releaseRepo + "/releases/download/" + releaseVersion + "/install.sh";
        if (StrUtil.isNotBlank(githubProxy)) {
            return githubProxy.replaceAll("/+$", "") + "/" + url;
        }
        return url;
    }

    private String shellQuote(String value) {
        if (value == null) {
            return "''";
        }
        return "'" + value.replace("'", "'\"'\"'") + "'";
    }


    private void validatePortRange(String port) {
        Pattern PORT_PATTERN = Pattern.compile(   "([0-9]{1,5})(-([0-9]{1,5}))?");
        if (port == null || port.isEmpty()) {
            throw new RuntimeException("可用端口不合法");
        }
        String[] parts = port.split(",");
        for (String part : parts) {
            part = part.trim();
            if (!PORT_PATTERN.matcher(part).matches()) {
                throw new RuntimeException("可用端口不合法");
            }
            if (part.contains("-")) {
                String[] range = part.split("-");
                int start = Integer.parseInt(range[0]);
                int end = Integer.parseInt(range[1]);
                if (start < 0 || end < 0 || end > 65535 || start > end) {
                    throw new RuntimeException("可用端口不合法");
                }
            } else {
                int ports = Integer.parseInt(part);
                if (ports < 0 || ports > 65535) {
                    throw new RuntimeException("可用端口不合法");
                }
            }
        }
    }




}
