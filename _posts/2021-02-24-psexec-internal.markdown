---
layout: post
title: "Psexec Internal"
date: 2021-02-24 12:17:31 +0800
categories: reverse-engineering
---

psexec是后渗透的常用工具，拥有一个目标系统的账户后我们可以通过它在目标系统执行命令。但是它是如何工作的？这篇文章将记录我的研究过程。

## psexec的登录过程

https://docs.microsoft.com/en-us/troubleshoot/windows-server/networking/inter-process-communication-share-null-session

使用函数WNetAddConnection2W通过ipc$共享登录到目标计算机

![image-20210224110927413](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20210224110927413.png)

## psexec如何在目标系统上执行命令

psexec自身携带了psexesvc，在登录后会将psexesvc通过admin$共享将psexesvc拷贝过去

![image-20210224111039427](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20210224111039427.png)

​	查看psexec的资源表，可以发现附带的psexecsvc程序

![image-20210224111153742](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20210224111153742.png)

之后打开目标系统上的服务管理器，创建psexesvc的服务并启动。

![image-20210224111351331](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20210224111351331.png)

之后使用命名管道来与psexesvc进行通信，向psexesvc发送指令来执行命令

![image-20210224111747076](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20210224111747076.png)

## psexesvc以什么身份（账户）在目标系统上执行

psexecsvc是以服务的身份启动的，因此如果执行命令，那就是以服务的身份执行。可实际上使用时我们知道，我们是以通过命令行传入psexec的账户的身份执行的

这是如何做到的？

在发送指令的包中，psexec会同时将用户传入的凭据发送给psexesvc

![image-20210224112856530](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20210224112856530.png)

psexecsvc使用LogonUserExExW进行登录，获取一个目标账户的token

![image-20210224113040740](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20210224113040740.png)

接着使用CreateProcessAsUser，通过已获取的token来以目标账户的身份登录

![image-20210224113336005](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20210224113336005.png)

---

- 在学习的时候发现了一个开源版本的psexec https://github.com/poweradminllc/PAExec

- 终于向内网前进了一点
- 还是那句话，想要更好的使用工具或者开发自己的工具就需要深入了解其内部的机制

