---
layout: post
title: "自动化信息收集框架：设计数据库"
date: 2020-03-06 11:20:33 +0800
categories: information-gathering
---

对于渗透来说，信息收集的完整度决定了最后渗透的成功与否。当对一个大型目标进行渗透的过程中，信息收集的工作便变得繁重。尽管现在有诸多自动化工具为我们完成信息收集方方面面的工作，但是如何将这些工具串联起来？输入一个域名后就能自动进行各方面的收集（包括子域名，端口探测，web指纹，web路径等等），这是我所期望的效果。因此我想要实现一个框架，将各种工具组合到一起进行全自动的信息收集。

# 数据存储与数据库范式

在信息收集之后，我们应该如何存储这些收集来的数据？长久以来我都是对每一个项目单开一个文件夹，将扫描结果以文本的形式零散的存放进去。这样做既不便于整理也不便于查找。因此我产生了使用数据库的念头（事实上数据库不就是干这个用的嘛）。随之而来的问题是如何设计？我们知道数据库由库、表组成，表中是按照列名存储的一行一行数据，怎样的设计才能让我们的数据是简洁、结构清晰同时还方便查找，这时候就需要用到数据库范式。

> 数据库的设计范式是数据库设计所需要满足的规范，满足这些规范的数据库是简洁的、结构明晰的，同时，不会发生插入（insert）、删除（delete）和更新（update）操作异常。反之则是乱七八糟，不仅给数据库的编程人员制造麻烦，而且面目可憎，可能存储了大量不需要的冗余信息。

下面只对4个范式进行简单回顾。

## 1NF

> 1NF是对属性的**原子性**，要求属性具有原子性，不可再分解；

举个例子，假设一个表中有一列叫出生年月日，每人的这列数据都分为3个格子（年、月、日），那这种数据库就不符合1NF。而事实上1NF是关系型数据库的基本要求，这也代表着如果你这么设计数据表的话那这种操作一定是不会成功的。

## 2NF

> 2NF是对记录的**惟一性**，要求记录有惟一标识，即实体的惟一性，即不存在部分依赖；

2NF在1NF的基础上消除了非主属性对于码的部分函数依赖，简单来讲就是非主键字段必须完全依赖主键。假设一张表主键为（学号，课号），那么对于属性姓名来讲，只有学号才决定姓名而与课号无关，因此属性姓名对于主键为部分依赖，因此不符合2NF

## 3NF

> 3NF是对字段的**冗余性**，要求任何字段不能由其他字段派生出来，它要求字段没有冗余，即不存在传递依赖；

3NF在2NF的基础之上，消除了非主属性对于码的传递函数依赖。如果一张表学号为主键，有属性学院名和学院主任，学号决定所属学院，所属学院决定学院主任。因此学院主任这个属性对主属性学号为传递依赖，不符合3NF

## BCNF

> 若关系模式R属于3NF，且关系模式中每一个决定因素都包含候选键，则为BCNF。

BCNF不允许存在**主属性**对于码的部分函数依赖与传递函数依赖。（实在想不出该怎么解释）

当我们设计的数据库达到了BCNF范式的要求，那么这个设计可以说是相当不错的，虽然之后还有4NF、5NF，但是我们不作考虑。（不会）

# 设计

首先要确定要存什么样的内容

- 项目属性

  - project_name：项目名称
  - domain：目标所有的域名
- 对于域名
  - ip_address:指向的ip
  - use_CDN:是否使用cdn
- 对于每台服务器
  - ip_address：目标所有的ip地址
  - open_port_id：目标ip开放的端口
  - port_service：目标ip端口上运行的服务
- 对于web服务
  - url：不用多说
  - web_fingerprint：目标web服务的指纹
  - title：web服务网页的标题
  - screenshot_path：web服务的截屏的存储路径
  - available_path：扫描出的web服务的路径
- 对于web服务的每个路径
  - state_code：各个路径的状态码
  - content-length：返回的内容长度
  - redirect：如果有重定向，重定向的位置

确定这些数据的关系（X -> Y 代表存在函数依赖且X函数决定Y）

- domain -> project_name
- domain -> ip_address
- domain -> use_CDN
- ip_address, open_port_id -> port_service
- url -> web_fingerprint（考虑到会有虚拟主机所以加上domain）
- url -> title
- url -> screenshot_path
- url, available_path -> state_code
- url, available_path -> content-length
- url, available_path -> redirect

根据关系来设计数据表

- project_assets( domain [primary key ], project_name, ip_address, use_CDN)
- server_information( ip_address [primary key ], open_port_id [primary_key ], port_service)
- web_service( url [primary key ], web_fingerprint, title ,screenshot_path)
- web_path_information( url [primary key ], available_path [primary_key ], state_code, content-length, redirect)

# 一些参考资料

<https://www.cnblogs.com/ybwang/archive/2010/06/04/1751279.html>

<https://segmentfault.com/a/1190000013695030>