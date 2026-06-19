package main

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"strings"
)

// Config 配置结构体
type Config struct {
	Addr   string `json:"addr"`
	Secret string `json:"secret"`
	Http   int    `json:"http"`
	Tls    int    `json:"tls"`
	Socks  int    `json:"socks"`
}

// LoadConfig 加载配置文件
func LoadConfig(configPath string) (*Config, error) {
	// 检查文件是否存在
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("配置文件不存在: %s", configPath)
	}

	// 读取文件内容
	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("读取配置文件失败: %v", err)
	}

	// 解析JSON
	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("解析配置文件失败: %v", err)
	}

	// 验证必要的配置项
	if config.Addr == "" {
		return nil, fmt.Errorf("服务器地址不能为空")
	}
	if config.Secret == "" {
		return nil, fmt.Errorf("节点密钥不能为空")
	}
	if err := validateServerAddr(config.Addr); err != nil {
		return nil, err
	}

	return &config, nil
}

func validateServerAddr(addr string) error {
	raw := strings.TrimSpace(addr)
	if raw == "" {
		return fmt.Errorf("服务器地址不能为空")
	}

	if !strings.Contains(raw, "://") {
		raw = "https://" + raw
	}

	u, err := url.Parse(raw)
	if err != nil {
		return fmt.Errorf("解析服务器地址失败: %w", err)
	}
	if u.Host == "" {
		return fmt.Errorf("服务器地址缺少主机名")
	}

	switch strings.ToLower(u.Scheme) {
	case "https":
		return nil
	case "http":
		if allowInsecureNodeTransport() {
			return nil
		}
		return fmt.Errorf("节点通信默认强制 HTTPS/WSS，请使用 https:// 地址；如确需明文测试，请设置 FLUX_ALLOW_INSECURE_NODE_TRANSPORT=1")
	default:
		return fmt.Errorf("服务器地址仅支持 http 或 https 协议")
	}
}

func allowInsecureNodeTransport() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("FLUX_ALLOW_INSECURE_NODE_TRANSPORT"))) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}
