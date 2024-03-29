---
layout: post
title: "《Kernel Attacks through User-Mode Callbacks》的一些笔记"
date: 2022-09-02 12:59:04 +0800
categories: pwn
---

读《Kernel Attacks through User-Mode Callbacks》这篇论文做的一些笔记，主要是摘录和翻译。



“win32k calls win32k!xxxInitProcessInfo to initialize the per-process W32PROCESS/PROCESSINFO2 structure” (Mandt, p. 4)

win32k!xxxInitProcessInfo 初始化W32PROCESS/PROCESSINFO

该结构包含进程gui相关信息，如桌面句柄、windows station句柄以及gdi句柄等。

“Additionally, win32k also initializes a per-thread W32THREAD/THREADINFO structure for all threads that are converted to GUI threads. This structure holds thread specific information related to the GUI subsystem such as information on the thread message queues, registered windows hooks, owner desktop, menu state, and so on. Here, W32pThreadCallout calls win32k!AllocateW32Thread to allocate the structure, followed by GdiThreadCallout and UserThreadCallout to initialize information peculiar to the GDI and USER subsystems respectively.” (Mandt, p. 4)

W32THREAD/THREADINFO包含线程gui信息，如线程消息队列，注册的窗口钩子，所属的desktop，菜单状态等。

“win32k!AllocateW32Thread” (Mandt, p. 4)

“USER32!_fnDWORD” (Mandt, p. 8) fnDWORD用于dispatch message

(Mandt, p. 11) 如果一个usermode callback在执行过程中修改了某些窗口属性，而在callback之后返回到内核中时内核没有做相应的检查，则可能会会导致一些安全问题

“Functions prefixed xxx will in most cases leave the critical section and invoke a user-mode callback.” (Mandt, p. 11)

“Functions prefixed zzz invoke asynchronous or deferred callbacks.” (Mandt, p. 11)



## User Object Locking

“Window Object Use-After-Free (CVE-2011-1237)” (Mandt, p. 13) 当程序设置了CBT HOOK的时候，可以接收打HCBT_CREATEWND 消息，这个消息中程序可以使用一个已存在的窗口句柄来设置新创建窗口z轴上的位置（操作系统使用hwndInsertAfter实现），在设置了这个z轴位置的属性后，操作系统将使用这个句柄将将要创建的窗口加入到z轴的链表里去。然而操作系统并没有在回调函数设置窗口位置后将用于设置窗口位置的窗口句柄锁定，因此在之后攻击者可以将该窗口句柄指向的窗口销毁，从而使操作系统操作一块被释放的内存，造成uaf。

“Keyboard Layout Object Use-After-Free (CVE-2011-1241)” (Mandt, p. 14) LoadKeyboardLayoutEx 函数需要传入一个键盘布局的句柄，而该函数在接收到句柄后没有锁定该句柄指向的对象，导致攻击者可以在callback中卸载该对象，从而触发uaf

## Object State Validation

“DDE Conversation State Vulnerabilities” (Mandt, p. 16) 双方使用dde通讯的时候，攻击者（其中一方）可以在用户回调中结束通讯，导致对方的通讯对象被释放，当对方再次使用通讯对象时，由于没有对其进行安全验证，继续使用该指针，导致安全问题。

“Menu State Handling Vulnerabilities” (Mandt, p. 17) 在处理多种菜单消息时，win32k在usercallback之后没有验证菜单的状态，导致安全问题

## Buffer Reallocation

许多对象都使用array来存放一些东西，array会随着元素的增加或减少而改变大小。重要的是任何可以在usercallback中被修改的array需要在调用结束后进行检查，否则将导致安全问题。

“Menu Item Array Use-After-Free” (Mandt, p. 19) 菜单对象定义了一个指向数组菜单item的指针，可以用使用InsertMenuItem或DeleteMenu函数操作该数组，同时有一个cItems变量来存储数组元素的个数。一些win32k中的函数没有在用户回调之后校验菜单数组，并且由于数组不存在锁的机制，所以任何一个用户回调函数都可以修改该数组。如果一块用户数组的内存在用户回调中被重新分配内存，而之后的代码没有进行校验，则会导致之后都的代码操作在一块被释放的内存上。“SetMenuInfo” (Mandt, p. 19) 允许应用为菜单设置属性。在设置MIM_APPLYTOSUBMENUS flag后，win32开会更新所有子菜单的属性。其内部实现为xxxSetMenuInfo 函数。xxxSetMenuInfo 在递归更新子菜单属性前首先将菜单items的数量以及指向该数组的指针存在栈中。一旦xxxSetMenuInfo 递归找到最底层的菜单，递归停止，并且这时有可能会在xxxMNUpdateShownMenu中调用用户回调，因此此时可以在用户回调中修改菜单item 数组的大小。并且，在xxxMNUpdateShownMenu返回后，上层函数(xxxSetMenuInfo )并没有校验菜单数组指针和菜单item数量的正确性。因此当攻击者在回调中修改了数组时，xxxSetMenuInfo将有可能操作一块空的内存。

“SetWindowPos Array Use-After-Free” (Mandt, p. 21) 大同小异，懒得写了

“Use-After-Free Exploitation” (Mandt, p. 24) 为了利用uaf漏洞，攻击者需要重新分配那块已经被释放的内存并且能在一定程度上控制该内存。对于desktop heap的uaf，可以使用SetWindowTextW去强制分配一个特定大小的堆内存；对于session pool的uaf，则可以使用SetClassLongPtr并且指定GCLP_MENUNAME来达到效果。win32k中一些对象会包含指向永久锁的指针，当被uaf影响的对象再次被释放后，win32k会将该对象中永久锁的的引用减一，这就实现了一个任意地址减一的操作。使用这个任意地址减一的操作，可以将窗口对象的类型(bType)设置为0，当该窗口对象销毁时，这回引起free type为0的销毁函数被调用，而该函数是未被定义的（指向该函数的函数指针为null），因此用户可以通过映射0页导致内核代码执行。

“Null Pointer Exploitation” (Mandt, p. 25) 通过调用NtAllocateVirtualMemory，用户可以在0页分配内存，进而导致攻击者可以在0页创建一个假的对象然后触发任意内存写或者控制函数指针指向的内容。

## 缓解措施

win32k中的uaf关键在于攻击者有能力在回调中释放对象并且在win32k重新使用该对象的时候重新分配内存。因此可以通过隔离某一些资源的分配（如字符串），使它们从不同的资源内配内存来减少内核pool以及heap的可预测性。

由于系统可以知道何时回调处于激活状态，因此可以使用延时释放内存。这将组织攻击者立刻重用被释放的内存空间。然而这种方式对于那些在uaf触发前有多个回调被调用的漏洞无效。

---

文章和笔记都是六月份弄的，回首一下这两三个月，感觉确实在随机漫步，搞一些杂七杂八的东西。不过也无所谓，就相当于休息了。之前代码写得实在太投入，等到写完才感觉到好累。