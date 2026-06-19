package transport

import (
	"fmt"
	"net/url"
	"os"
	"strings"
)

func AllowInsecure() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("FLUX_ALLOW_INSECURE_NODE_TRANSPORT"))) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}

func HTTPBaseURL(addr string) (*url.URL, error) {
	raw := strings.TrimSpace(addr)
	if raw == "" {
		return nil, fmt.Errorf("服务器地址不能为空")
	}

	if !strings.Contains(raw, "://") {
		raw = "https://" + raw
	}

	u, err := url.Parse(raw)
	if err != nil {
		return nil, fmt.Errorf("解析服务器地址失败: %w", err)
	}
	if u.Host == "" {
		return nil, fmt.Errorf("服务器地址缺少主机名")
	}

	switch strings.ToLower(u.Scheme) {
	case "https":
	case "http":
		if !AllowInsecure() {
			return nil, fmt.Errorf("节点通信默认强制 HTTPS/WSS，请使用 https:// 地址；如确需明文测试，请设置 FLUX_ALLOW_INSECURE_NODE_TRANSPORT=1")
		}
	default:
		return nil, fmt.Errorf("服务器地址仅支持 http 或 https 协议")
	}

	u.RawQuery = ""
	u.Fragment = ""
	u.Path = strings.TrimRight(u.Path, "/")
	return u, nil
}

func HTTPURL(addr string, path string, query url.Values) (string, error) {
	u, err := HTTPBaseURL(addr)
	if err != nil {
		return "", err
	}

	u.Path = joinPath(u.Path, path)
	u.RawQuery = query.Encode()
	return u.String(), nil
}

func WebSocketURL(addr string, path string, query url.Values) (string, error) {
	u, err := HTTPBaseURL(addr)
	if err != nil {
		return "", err
	}

	if strings.EqualFold(u.Scheme, "https") {
		u.Scheme = "wss"
	} else {
		u.Scheme = "ws"
	}

	u.Path = joinPath(u.Path, path)
	u.RawQuery = query.Encode()
	return u.String(), nil
}

func joinPath(basePath string, path string) string {
	cleanBase := strings.TrimRight(basePath, "/")
	cleanPath := strings.TrimLeft(path, "/")
	if cleanPath == "" {
		if cleanBase == "" {
			return "/"
		}
		return cleanBase
	}
	return cleanBase + "/" + cleanPath
}
