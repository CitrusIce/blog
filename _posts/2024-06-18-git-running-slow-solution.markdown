---
layout: post
title: "git运行很慢的解决方法"
date: 2024-06-18 15:49:05 +0800
categories: 杂
---

最近发现 git 总是很慢，操作起来卡的不行，于是准备解决一下。网上搜索了一下相关信息再加上跟朋友讨论得出大概两点原因：

- **显卡驱动兼容**：我不懂绘制之类的事情，只是搜到了几个讨论这个 issue。不过我本人在设置了默认用集显后情况确实好了不少。
参考链接：
[Git Bash (mintty) is extremely slow on Windows 10 OS - Stack Overflow](https://stackoverflow.com/questions/42888024/git-bash-mintty-is-extremely-slow-on-windows-10-os)
[git commands running slow as hell · Issue #1129 · git-for-windows/git](https://github.com/git-for-windows/git/issues/1129)
[Git commands have a 2-3 second delay before returning to the prompt · Issue #1070 · git-for-windows/git](https://github.com/git-for-windows/git/issues/1070)

- **杀软原因**：这点解释得挺有道理。Linux 上有 fork 这个功能，是很多程序会**大量**调用的。但是Windows 上没有，为了兼容，在 windows 上都是使用 windows api 来模拟的，本身性能不够好。同时，而很多杀毒软件会在创建进程时对进程进行扫描并注入 DLL 监控行为，这就更卡了。除了卸载杀软之外，还可以使用 Windows 11 的新功能 Dev Driver 来禁用过滤驱动。