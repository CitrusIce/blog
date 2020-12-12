---
layout: post
title: "wdigest逆向"
date: 2020-12-11 17:28:20 +0800
categories: reverse-engineering
---

逆向从wdigest的SpAcceptCredentials开始，当使用windows账户凭据做认证时lsass将会调用这个函数。

![image-20201211161323616](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20201211161323616.png)

第二个参数是用户名，第三个结构是一个指向未知结构体的指针，其中包含用户名，主机名，以及明文的密码

![image-20201211161700795](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20201211161700795.png)

之后会根据传入的参数，开辟一块buffer，将数据写入，实际上这里是一个未公开的结构

![image-20201211162019658](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20201211162019658.png)

可以看到写入了用户名、主机名等信息

![image-20201211162321781](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20201211162321781.png)

将刚刚的结构体放入了l_LogSessList双向链表中



wdigest同样也会将密码写入这个buffer，以加密形式存储。这意味着我们可以通过获取密钥的方式来解密这块内存来获得wdigest中存储的密码。

![image-20201211162435396](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20201211162435396.png)

经过调试发现使用的加密函数是位于lsasrv.dll中的LsaProtectMemory

![image-20201211162648348](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20201211162648348.png)

可以看出根据输入的密钥长度不同，LsaEncryptMemory会使用aes加密或3des加密，最终调用的函数都是BCrypt

因此只要找到lsasrv.dll存储于内存中的key我们就能够解密出wdigest中存储的用户密码



想要更好的使用工具或者开发自己的工具就需要深入了解其内部的机制