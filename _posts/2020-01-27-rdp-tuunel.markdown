---
layout: post
title: "渗透测试中的rdp隧道"
date: 2020-01-27 20:03:35 +0800
categories: tunnel post-exploition
---
渗透过程中总有一些特殊场景需要使用各种隧道来绕过防火墙的各种规则，而rdp作为windows的远程管理协议往往不在防火墙的考虑范围内。由于防火墙的规则，当只能通过一台windows服务器进入内网情况下，rdp隧道是唯一的选择。

## 编译rdp2tcp

安装mingw32，kali自带

修改server的makefile.mingw32文件，修改cc为i686-w64-mingw32-gcc(根据实际情况修改)

```bash
make client
make server-mingw32
```

得到client/rdp2tcp和server/rdp2tcp.exe

## 编译xfreerdp

kali自带的不支持rdp2tcp，因此自己编译一个

```bash
git clone https://github.com/FreeRDP/FreeRDP.git
cmake .
make
make install
```

![](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image_8.png)

可以看到已经有了rdp2tcp选项

## rdp to tcp

```bash
/usr/local/bin/xfreerdp /v:192.168.157.139:3389 /u:yuzuu_ /rdp2tcp:/root/rdp2tcp/client/rdp2tcp
```

登录服务器，上传rdp2tcp.exe并运行

使用rdp2tcp/tools/rdp2tcp.py来管理tunnel

```bash
python rdp2tcp.py
```

测试：

将本地445端口的流量通过rdp tunnel转发到目标机上

![](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/20200127194853.png)



