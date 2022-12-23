---
layout: post
title: "Job, Session, and CreateProcessAsUser"
date: 2022-12-23 15:05:27 +0800
categories: 调试 windows
---

起因是因为要实现一个在 Session0 启动进程的功能（注意是在 Session0 启动，不是从 Session0 启动），本以为没什么难度，却没想到还是踩坑了。

流程很简单：

1. 获取一个 session0 的 token（应该也可以设置 token 为 session0，但我是从别的进程获取的）
2. Impersonate
3. CreateProcessAsUser

结果给的报错是 `ACCESS_DENIED` (5)。在确认了不是权限的问题之后，我发现这个问题并不简单。如果要想知道到底是什么引起了错误，最直接也是最有效的办法就是操起调试器开始调。于是我打开内核调试，拿起 windbg 在 `NtCreateUserProcess` 下断。

经过几轮 trace，最终得到了设置错误的位置，以下是调用栈

```
1: kd> k
 # Child-SP          RetAddr               Call Site
00 ffffa287`2443bc58 fffff800`7da0f8bd     nt!PspConvertJobToMixed
01 ffffa287`2443bc60 fffff800`7d86d16b     nt!PspBindProcessSessionToJob+0x1a22e5
02 ffffa287`2443bc90 fffff800`7d86dadc     nt!PspEstablishJobHierarchy+0x47
03 ffffa287`2443bd00 fffff800`7d82c118     nt!PspImplicitAssignProcessToJob+0x10c
04 ffffa287`2443bd40 fffff800`7d829725     nt!PspInsertProcess+0x7c
05 ffffa287`2443bdc0 fffff800`7d61cbb5     nt!NtCreateUserProcess+0xd85
```

通过符号名可以看出来是个 job 有关，google 了一下这几个函数也没找到其他人对这几个函数的分析，看来只能自己动手逆一下了。

要搞清楚函数是要干什么的，主要是要搞清楚什么东西输入了这个函数（参数、全局变量），然后这个函数做了什么。trace 出的这个调用链有点长，不太好梳理，找了一下函数的引用，发现了这样一条调用路径 `NtSetInformationJobObject -> PspBindProcessSessionToJob -> PspConvertJobToMixed` ，接着通过 NtSetInformationJobObject 的 signature 很快就逆出来传入 PspBindProcessSessionToJob 的参数是 `EJOB` 和 `EPROCESS`， `PspConvertJobToMixed` 的参数是 EJOB 和 0，再修改修改变量名逻辑就很清晰了。

```cpp
__int64 __fastcall PspBindProcessSessionToJob(PEJOB job, PEPROCESS process)
{
  PEJOB job_1; // r8
  signed __int32 sessionid; // er9
  int job_SessionId; // er10
  __int64 result; // rax
  signed __int32 v6; // eax

  sessionid = MmGetSessionId((__int64)process);
  if ( job_SessionId == sessionid
    || job_SessionId == -1
    && ((v6 = _InterlockedCompareExchange((volatile signed __int32 *)&job_1->SessionId, sessionid, -1), v6 == -1)
     || v6 == sessionid) )
  {
    result = 0i64;
  }
  else
  {
    result = PspConvertJobToMixed((__int64)job_1, 0);
  }
  return result;
}
__int64 __fastcall PspConvertJobToMixed(PEJOB job, int a2)
{
  unsigned int jobFlags; // eax

  if ( job->SessionId == -2 )
    return 0i64;
  jobFlags = job->JobFlags;
  if ( (jobFlags & 0x10) == 0
    && (_bittest((const int *)&jobFlags, 0x1Eu)
     || (((unsigned __int64)job->PartitionObject + 1) & 0xFFFFFFFFFFFFFFFEui64) != 0
     || a2) )
  {
    job->SessionId = -2;
    return 0i64;
  }
  return 0xC0000022i64;
}
```

大概逻辑就是首先找到新创建进程所属的 session，如果所属的 session 跟 job 的 session 不一致，则调用 PspConvertJobToMixed 将 job 转换为混合 session 的 job。在 PspConvertJobToMixed 中，检查 job 的 JobFlags，要求没有 `JOB_OBJECT_LIMIT_AFFINITY` (0x10) 并且第 30 位为 1（不知道是啥），要么  `(((unsigned __int64) job->PartitionObject + 1) & 0xFFFFFFFFFFFFFFFEui64) != 0`，我也不知道是什么。

根据逻辑可以看出，当 job 的 session id 为 -2 时，代表这个 job 是跨 session 的，而要想让这个 job 跨 session 那么就需要 job 满足一些条件。同时我们还知道，处于 job 下的进程创建的子进程会被自动继承父进程的 job，这导致内核会试图将子进程加入父进程的 job 中，由于我是在 session1 往 session0 创建进程，而 session1 的进程所属的 job 不满足这个条件，这导致内核无法将 job 转换为 mix job，因此导致创建进程失败。

那么父进程为什么会有个 job 呢？简单看了一下，我的程序是一个 cui 程序，启动的时候会启动一个 conhost，我发现所有带 conhost 的进程都会有个 job 附加（cmd、powershell 等），看来这个 job 似乎跟 conhost 有关，具体我没有深究了，主要也没搜索到什么信息，如果有了解的欢迎联系我交流！

解决：只要在创建进程的时候让子进程摆脱父进程的 job 就可以成功创建进程了。这需要在创建进程时传入 `CREATE_BREAKAWAY_FROM_JOB` 并且该 job 具有 `JOB_OBJECT_LIMIT_BREAKAWAY_OK` 或 `JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK` 的 flag（发现 job 是有 `JOB_OBJECT_LIMIT_BREAKAWAY_OK` flag 的）。

---

最近有尝试在用 vscode+cmake 构建工程，调试的话主要是靠 windbg，有时候会用到 cdb，毕竟直接在命令行里调也还是蛮方便的（gdb 或者 lldb 感觉都不太好用，windows 上还是得用 windows 的东西）。相比于 gui 的 windbg 把任何能展示的都直接展示出来，用 cdb 的时候往往需要去认真的想“我想要什么样的信息才能解决这个问题”，因为每个信息都需要靠命令敲出来，无形中增加了成本。但我觉得“知道自己想要什么”是一种很重要的能力。