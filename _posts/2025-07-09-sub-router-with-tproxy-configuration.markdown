---
layout: post
title: "旁路由科学上网配置笔记"
date: 2025-07-09 18:05:36 +0800
categories: 杂
---

之前家里科学上网一直是通过刷了个openwrt的路由装了openclash来上网的，但是受限于openwrt路由器的性能，操作openclash很是不方便，总觉得网速也受到影响，因此准备在家中内网的linux主机上配置一个旁路由用于科学上网。

网络环境：

- 192.168.2.1 路由器
- 192.168.2.2 旁路由 （这里我是**arch系**）
- 192.168.2.100 用户主机

首先是配置clash，当前clash已经改名为mihomo，直接安装

```bash
yay -Sy mihomo
```

实现透明代理有两种方法，一个是tun一个是tproxy，这里我选用tproxy

```yaml
tproxy-port: 7894 # You can choose any available port, e.g., 7894 or 9898 [4, 6]
routing-mark: 255  # 这个值对应 iptables 规则中的 0xff
dns:
  enable: true
  listen: 0.0.0.0:53
  ipv6: false           # 禁止DNS解析IPv6
  enhanced-mode: redir-host  # 使用 redir-host 模式

  # 这些 DNS 用于解析代理服务器域名（重要！）
  default-nameserver:
    - 114.114.114.114
    - 223.5.5.5
    - 1.1.1.1
  nameserver:
    - 114.114.114.114
    - 8.8.8.8
  fallback:  # 防止 DNS 污染
    - 1.1.1.1
    - 8.8.8.8
```

配置关键在于设置这三部分：tproxy-port/routing-mark以及dns

我的主机上已经有了systemd-resolved会运行一个stub listener占用了53端口，因此要先配置systemd-resolved，在`/etc/systemd/resolved.conf`的`[Resolve]`部分禁用stub listener并且设置dns服务器为本地地址

```ini
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
```

另外由于我使用的是manjaro，使用network manager管理网络，我的 `/etc/resolv.conf` 会被network manager自动覆盖，因此还需要配置network manager。

```bash
nmcli connection show --active
# NAME                UUID                                  TYPE      DEVICE          
# Wired connection 1  5d78f62e-5624-313a-a89d-7242ca4a3e3b  ethernet  eno1          

# 把 "Wired connection 1" 替换成你自己的连接名

# 修改 IPv4 DNS
sudo nmcli connection modify "Wired connection 1" ipv4.dns "127.0.0.1"

# 修改 IPv6 DNS (可选，但建议设置为空，避免走 IPv6 DNS)
sudo nmcli connection modify "Wired connection 1" ipv6.dns ""

# 关键一步：设置 DNS 模式为“仅使用手动设置的 DNS”
sudo nmcli connection modify "Wired connection 1" ipv4.ignore-auto-dns yes
sudo nmcli connection modify "Wired connection 1" ipv6.ignore-auto-dns yes

# 重新激活
sudo nmcli connection up "Wired connection 1"
```

把mihomo启动起来，测试一下能否正常代理连接

```bash
curl -x socks5://127.0.0.1:7890 https://www.google.com -v 
```

接下来配置透明代理，直接抄的网上的，但是需要修改网卡名字、tproxy端口以及clash的标记

```
#!/usr/sbin/nft -f

## 清空旧规则
flush ruleset

## 只处理指定网卡的流量，要和ip规则中的接口操持一致
define interface = eno1

## clash的透明代理端口
define tproxy_port = 7894

## clash打的标记（routing-mark）
define clash_mark = 255

## 常规流量标记，ip rule中加的标记，要和ip规则中保持一致，对应 "ip rule add fwmark 1 lookup 100" 中的 "1"
define default_mark = 1

## 本机运行了服务并且需要在公网上访问的tcp端口（本机开放在公网上的端口），仅本地局域网访问的服务端口可不用在此变量中，以半角逗号分隔
define local_tcp_port = {
        3000-4000,
        25565,     
        8000-9000,
        1200,   
}

## 要绕过的局域网内tcp流量经由本机访问的目标端口，也就是允许局域网内其他主机主动设置DNS服务器为其他服务器，而非旁路由
define lan_2_dport_tcp = {
    53     # dns查询
}

## 要绕过的局域网内udp流量经由本机访问的目标端口，也就是允许局域网内其他主机主动设置DNS服务器为其他服务器，而非旁路由；另外也允许局域网内其他主机访问远程的NTP服务器
define lan_2_dport_udp = {
    53,    # dns查询
    123    # ntp端口
}

## 保留ip地址
define private_address = {
    127.0.0.0/8,
    100.64.0.0/10,
    169.254.0.0/16,
    224.0.0.0/4,
    240.0.0.0/4,
    10.0.0.0/8,
    172.16.0.0/12,
    192.168.0.0/16
}

## 大陆ip地址
# include "/var/lib/clash/geoip4_cn.nft"

table ip clash {

    ## 保留ipv4集合
    set private_address_set {
        type ipv4_addr
        flags interval
        elements = $private_address
    }

    ## 大陆ipv4集合
#    set geoip4_cn_set {
#        type ipv4_addr
#        flags interval
#        elements = $geoip4_cn
#    }

    ## prerouting链
    chain prerouting {
        type filter hook prerouting priority filter; policy accept;
        ip protocol { tcp, udp } socket transparent 1 meta mark set $default_mark accept # 绕过已经建立的连接
        meta mark $default_mark goto clash_tproxy                                        # 已经打上default_mark标记的属于本机流量转过来的，直接进入透明代理
        fib daddr type { local, broadcast, anycast, multicast } accept                   # 绕过本地、单播、组播、多播地址
        tcp dport $lan_2_dport_tcp accept                                                # 绕过经由本机到目标端口的tcp流量
        udp dport $lan_2_dport_udp accept                                                # 绕过经由本地到目标端口的udp流量
        ip daddr @private_address_set accept                                             # 绕过目标地址为保留ip的地址
       # ip daddr @geoip4_cn_set accept                                                   # 绕过目标地址为大陆ip的地址
        # ip protocol udp accept                                                         # 绕过全部udp流量（udp不进行透明代理）
        goto clash_tproxy                                                                # 其他流量透明代理到clash
    }

    ## 透明代理
    chain clash_tproxy {
        ip protocol { tcp, udp } tproxy to :$tproxy_port meta mark set $default_mark
    }

    ## output链 (优化后)
    chain output {
        type route hook output priority filter; policy accept;

        # -----------------------------------------------------------------
        # 核心修改：将最关键的绕过规则放在最顶端，确保它们最先被匹配
        # -----------------------------------------------------------------

        # 1. 绝对优先放行：目标是本地回环地址的流量 (修复你遇到的问题)
        #    这是最明确、最可靠的规则，用于防止本机服务（如DNS）被代理。
        ip daddr 127.0.0.1/32 accept

        # 2. 其次放行：Clash 自身发出的、已经打上标记的流量 (防止循环代理)
        meta mark $clash_mark accept

        # 3. 再次放行：目标地址是保留地址/内网地址的流量
        #    这条规则包含了 127.0.0.1，但放在这里作为双重保险，并处理其他内网IP。
        ip daddr @private_address_set accept

        # 4. 放行本机上其他服务的流量
        #    例如，如果你在本机运行了需要公网访问的SSH或Web服务。
        tcp sport $local_tcp_port accept
        
        # -----------------------------------------------------------------
        # 经过以上关键过滤后，剩下的流量才考虑是否需要代理
        # -----------------------------------------------------------------

        # 5. 将剩余的所有TCP/UDP流量标记，准备重路由到 prerouting 链
        ip protocol { tcp, udp } meta mark set $default_mark
    }

}
```

配置我稍微调整了一下，让大陆ip也走mihomo，然后通过mihomo内部规则再进行分流。

文件保存成`mynftables.nft`，启用tproxy还要结合路由规则设置

```bash
# 配置透明代理
ip route add local default dev eno1 table 100
ip rule add fwmark 1 lookup 100
nft -f mynftables.nft
# 启用mihomo
mihomo -f config.yaml
# 测试一下是否生效
curl ipinfo.io
```

生效后就可以配置成服务了，创建文件`/etc/systemd/system/mihomo.service`

```ini
[Unit]
Description = Mihomo tproxy daemon.
Wants       = network-online.target subconverter.service
After       = network-online.target

[Service]
Environment   = PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Type          = simple
Restart       = always
LimitNPROC    = 500
LimitNOFILE   = 1000000
ExecStartPre  = sleep 1s
ExecStart     = mihomo -f /etc/mihomo/config.yaml

# 启动前先尝试清理，忽略可能的失败 (注意-号的用法)
ExecStartPost = -ip route del local default dev eno1 table 100
ExecStartPost = -ip rule del fwmark 1 lookup 100

# 再执行添加操作
ExecStartPost = ip route add local default dev eno1 table 100
ExecStartPost = ip rule add fwmark 1 lookup 100
ExecStartPost = nft -f <mynftables.nft path>

# 停止时，确保每个清理步骤都被尝试执行
ExecStop      = -nft flush ruleset
ExecStop      = -ip route del local default dev eno1 table 100
ExecStop      = -ip rule del fwmark 1 lookup 100

[Install]
WantedBy = multi-user.target
```

启用服务

```bash
sudo systemctl daemon-reload
sudo systemctl enable mihomo.service
sudo systemctl start mihomo.service
```

至此这个主机已经可以作为旁路由了，将其他主机的网关手动指向它就可以实现科学上网。在此基础上，我们还可以继续配置路由器的dhcp服务，让dhcp服务自动配置网关到该路由器。

首先需要将旁路由设置成静态ip，不然路由器的dhcp服务修改后我们的网关会指向自己

```bash
nmcli connection show
sudo nmcli connection modify "Wired connection 1" ipv4.method manual
sudo nmcli connection modify "Wired connection 1" ipv4.method manual ipv4.addresses 192.168.2.2/24 ipv4.gateway 192.168.2.1 
sudo nmcli connection up "Wired connection 1"
```

我的路由器是openwrt，配置dhcp直接在lan口的dhcp服务中添加：

```
3,192.168.2.2 # 配置网关
6,192.168.2.2 # 配置dns服务器
```

至此配置结束