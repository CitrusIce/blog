---
layout: post
title: "记一次解决explorer占用cpu过高"
date: 2022-10-19 16:25:58 +0800
categories: debugging
---

占用cpu高的进程是explorer.exe，并非是创建桌面和任务栏的那个explorer，而是有着如下命令行

```
C:\WINDOWS\explorer.exe /factory,{ceff45ee-c862-41de-aee2-a022c81eda92} -Embedding
```

查了一下这个guid，发现是SeparateExplorerFactory，也就是代表这个进程实际上是当我们打开文件夹的时候所创建的进程，这个东西为什么会占用那么高的cpu？



用Luke Stackwalker attach上去，监控程序的调用堆栈，监控一段时间后停止，找到cpu耗时最高的线程看看。

![image-20221019151527668](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20221019151527668.png)



耗时最高的动作是NtUserMsgWaitForMultipleObjectsEx，这个调用这个函数不会引起卡顿，因为实际上它会让线程处于等待状态，不会对性能造成影响。

排名第二的函数是NtQuerySystemInfo

![image-20221019152817440](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20221019152817440.png)

一看调用栈，我已经闻到了垃圾代码的味道。K32EnumProcesses是在遍历系统进程，而发起这个调用的模块是YunShellExtV164.dll(某云，你懂的)，基本上已经确定了罪魁祸首了。接下来用ida看看他到底要干什么吧

![image-20221019153422458](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20221019153422458.png)

看一眼反编译代码，当调用这个函数时，这个模块会遍历所有进程，之后把pid加入一个容器中（set或者map，具体我也看不出来了）。那这个功能什么时候会触发呢？

![image-20221019155237761](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/image-20221019155237761.png)

GetOverlayInfo，这个icon overlay指的是在文件图标的左下角设置一些额外信息，比如当文件是快捷方式时，图标的左下角就会出现一个箭头来代表该文件是快捷方式。也就是说，每当窗口需要展示当前目录下文件的图标是，这个模块都会获取一遍本机当前运行的进程并记录，这不卡就有鬼了。



解决：

卸载或者删除该dll模块