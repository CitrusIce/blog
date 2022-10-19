---
layout: post
title: "The Story of GDI Abusing"
date: 2022-10-19 12:24:32 +0800
categories: pwn
---

真正开始要写利用了才发现我对利用这块一无所知，要说 win32k 我还稍微具备点前置知识，什么窗口过程用户回调巴拉巴拉，但利用是一点没有接触过，所以还是先补补漏洞利用手法，这篇是关于利用 gdi 对象实现任意内存写原语的。

# Bitmap Abuse

在 peb 中有一个指向 GdiSharedHandleTable 的指针，这个表是 Win32k! gpentHmgr 的映射，他是个数组结构，存放一个进程可用的 gdi 对象。

每个元素的结构长这样：

```cpp
typedef struct { 
  PVOID64 pKernelAddress; // 0x00 
  USHORT wProcessId; // 0x08 
  USHORT wCount; // 0x0a 
  USHORT wUpper; // 0x0c 
  USHORT wType; // 0x0e 
  PVOID64 pUserAddress; // 0x10 
} GDICELL64; // sizeof = 0x18
```

pKernelAddress 是该句柄引用的对象在内核中的地址，因此当我们有一个 gdi 对象句柄时，我们就可以通过这个句柄找到该对象的地址。

每个对象对象头长这样：

```cpp
typedef struct {
  ULONG64 hHmgr;
  ULONG32 ulShareCount;
  WORD cExclusiveLock;
  WORD BaseFlags;
  ULONG64 Tid;
} BASEOBJECT64; // sizeof = 0x18
```

对象头后面就跟的是真正的对象内容

接下来让我们看一下 SetBitmapBits 里真正起作用的函数 bDoGetSetBitmapBits：

```cpp
BOOL bDoGetSetBitmapBits(SURFOBJ *psoDst, SURFOBJ *psoSrc, BOOL bGetBits)
{
    //...
    //set bitmap 部分
        PSURFACE pSurfDst = SURFOBJ_TO_SURFACE(psoDst);

        {
            PDEVOBJ po(psoDst->hdev);
            po.vSync(psoDst,NULL,0);
        }

        //
        // Initialize temporaries.
        //

        PBYTE pjBuffer = (PBYTE) psoSrc->pvBits;
        PBYTE pjBitmap = (PBYTE) psoDst->pvScan0;
        LONG lDeltaBitmap = psoDst->lDelta;
        ULONG cjScanBitmap = pSurfDst->cjScan();

        //
        // Get the WORD aligned width of the input scanlines.
        //

        ULONG cjScanInput = ((((gaulConvert[psoDst->iBitmapFormat] * psoDst->sizlBitmap.cx) + 15) >> 4) << 1);
        ULONG cjMaxLength = cjScanInput * psoDst->sizlBitmap.cy;
        LONG lInitOffset = psoSrc->lDelta;
        ULONG cjTotal = psoSrc->cjBits;

        //
        // Check for invalid initial offset.
        //

        if ((lInitOffset < 0) || ((ULONG)lInitOffset >= cjMaxLength))
        {
            psoSrc->cjBits = 0;
            return(TRUE);
        }

        //
        // Make cjTotal valid range.
        //

        if (lInitOffset + cjTotal > cjMaxLength)
        {
            cjTotal = cjMaxLength - lInitOffset;
        }

        //
        // Fill in our return values, we know them already.
        //

        psoSrc->cjBits = cjTotal;

        //
        // Move pointer to current scanline in bitmap.
        //

        pjBitmap += ((lInitOffset / cjScanInput) * lDeltaBitmap);

        ULONG ulTemp,ulCopy;

        //
        // Move partial scan if necesary.
        //

        ulTemp = (lInitOffset % cjScanInput);

        if (ulTemp)
        {
            ulCopy = MIN((cjScanInput - ulTemp), cjTotal);

            RtlCopyMemory((PVOID) (pjBitmap + ulTemp), (PVOID) pjBuffer, (unsigned int) ulCopy);

            pjBuffer += ulCopy;
            pjBitmap += lDeltaBitmap;
            cjTotal  -= ulCopy;
        }

        //
        // Move as many scans that fit.
        //

        ulTemp = cjTotal / cjScanInput;
        cjTotal -= (ulTemp * cjScanInput);

        while (ulTemp--)
        {
            RtlCopyMemory((PVOID) pjBitmap, (PVOID) pjBuffer, (unsigned int) cjScanInput);

            pjBuffer += cjScanInput;
            pjBitmap += lDeltaBitmap;
        }

        //
        // Move as much of partial scan as possible.
        //

        if (cjTotal)
        {
            RtlCopyMemory((PVOID) pjBitmap, (PVOID) pjBuffer, (unsigned int) cjTotal);
        }
            //...
}
```

可以看到 pvScan0 是一个关键字段，bDoGetSetBitmapBits 会取一个 surfobj 的 pvScan0 作为 dst，另一个 surobj 的 pvBits 作为 src 进行拷贝，如果我们可以影响这个字段，就代表我们可以通过 SetBitmapBits 实现一个内核的任意写。

当我们调用 CreateBitmap 函数后，我们获得一个 HBITMAP 句柄，这个句柄实际上就对应着内核里的 SURFOBJ 对象

```cpp
typedef struct _SURFOBJ
{
    DHSURF  dhsurf;
    HSURF   hsurf;
    DHPDEV  dhpdev;
    HDEV    hdev;
    SIZEL   sizlBitmap;
    ULONG   cjBits;
    PVOID   pvBits;
    PVOID   pvScan0; //+0x38
    LONG    lDelta;
    ULONG   iUniq;
    ULONG   iBitmapFormat;
    USHORT  iType;
    USHORT  fjBitmap;
} SURFOBJ;
```

因此当我们得到对象的内核地址后，address+0x18+0x38 的地方也就是 pvScan0 的地址，如果我们可以通过漏洞在这个位置写入确定的值，那么我们就可以通过 bitmap 来实现任意写。

# Bitmap 利用的扩展
bitmap 非常好使，但是上述利用方法在一些严苛的环境中是没法使用的，比如当你无法控制写入的值，只能控制写入的位置时。因此有人便在这个技术之上开发了新的技术，让 bitmap 可以应用于更多的漏洞场景中。

让我们再看一下 SURFOBJ 在内存中的结构，该对象在内存中后面尾随了一块数据，其大小为 `szlBitmap.cx*szlBitmap.cy`，而 pvScan0 则指向这块数据。这意味着如果我们可以将这个字段的值扩大，我们就可以对 pvScan0 指向的数据进行越界读写。那么我们就可以在内存中一前一后排列两个 SRFOBJ 对象，通过漏洞扩大前面一个 SRFOBJ 对象 szlBitmap，让我们可以越界读写后面的 SRFOBJ 对象的，操作其 pvScan0 字段，进而实现稳定的内存读写。

# 池 FreeList 重用

在 Win10 rs1 v1607 时，微软推出了缓解措施，将 gdicell 的 pKernelAddress 置空，因为无法获取到对象的地址，因此该方法就无法继续使用了，但是黑客们依然想出了办法来预测 bitmap 的地址，这个方法就是利用 accelerator table。

在分配 pool 内存时，如果分配的内存 size 大于一页的话，就会 MiAllocatePoolPages 直接按页分配。而在 MiAllocatePoolPages 中，会先从 FreeList 中找有没有合适的页（从队尾开始遍历），如果有就直接用合适的页，如果没有再把新的页 map 进来。在 MiFreePoolPages 中，该函数首先看该页能否跟前一页进行合并，如果不能合并，则将该页放到 freelist 队尾。

```cpp
PVOID
ExAllocatePoolWithTag (
    IN POOL_TYPE PoolType,
    IN SIZE_T NumberOfBytes,
    IN ULONG Tag
    )
{
//...
    if (NumberOfBytes > POOL_BUDDY_MAX) {

        //
        // The requested size is greater than the largest block maintained
        // by allocation lists.
        //

        RetryCount = 0;
        IsLargeSessionAllocation = (PoolType & SESSION_POOL_MASK);

        RequestType = (PoolType & (BASE_POOL_TYPE_MASK | SESSION_POOL_MASK | POOL_VERIFIER_MASK));

restart1:

        LOCK_POOL(PoolDesc, LockHandle);

        Entry = (PPOOL_HEADER) MiAllocatePoolPages (RequestType,
                                                    NumberOfBytes,
                                                    IsLargeSessionAllocation);
//...
    }
//...    
}
PVOID
MiAllocatePoolPages (
    IN POOL_TYPE PoolType,
    IN SIZE_T SizeInBytes,
    IN ULONG IsLargeSessionAllocation
    )
{
//...
        ListHead = &MmNonPagedPoolFreeListHead[Index];
        LastListHead = &MmNonPagedPoolFreeListHead[MI_MAX_FREE_LIST_HEADS];

        do {

            Entry = ListHead->Flink;

            while (Entry != ListHead) {

                if (MmProtectFreedNonPagedPool == TRUE) {
                    MiUnProtectFreeNonPagedPool ((PVOID)Entry, 0);
                }
    
                //
                // The list is not empty, see if this one has enough space.
                //
    
                FreePageInfo = CONTAINING_RECORD(Entry,
                                                 MMFREE_POOL_ENTRY,
                                                 List);
    
                ASSERT (FreePageInfo->Signature == MM_FREE_POOL_SIGNATURE);
                if (FreePageInfo->Size >= SizeInPages) {
    
                    //
                    // This entry has sufficient space, remove
                    // the pages from the end of the allocation.
                    //
                    //...
                }
            }
        }
//...
}
ULONG
MiFreePoolPages (
    IN PVOID StartingAddress
    )
{
//...
   if (Entry == (PMMFREE_POOL_ENTRY)StartingAddress) {

            //
            // This entry was not combined with the previous, insert it
            // into the list.
            //

            Entry->Size = i;

            Index = (ULONG)(Entry->Size - 1);
    
            if (Index >= MI_MAX_FREE_LIST_HEADS) {
                Index = MI_MAX_FREE_LIST_HEADS - 1;
            }

            if (MmProtectFreedNonPagedPool == FALSE) {
                InsertTailList (&MmNonPagedPoolFreeListHead[Index],
                                &Entry->List);
            }
            else {
                MiProtectedPoolInsertList (&MmNonPagedPoolFreeListHead[Index],
                                      &Entry->List,
                                      Entry->Size < MM_SMALL_ALLOCATIONS ?
                                          TRUE : FALSE);
            }
        }
//...
}
```

可以看到，freelist 中页的使用是一个 LIFO（后进先出）的顺序，因此，只要我们分配的页大小每次都一样，通过循环分配+释放的动作，我们最终可以使每次分配后的页为同一个地址。

accelerator table 是一个内核对象，并且该对象与 bitmap 位于同一个池中。该对象的内核地址我们可以同过 gSharedInfo 这个表获得对应的 handleentry，handleentry 中有一个成员 pHead 存放了该内核对象的地址，（bitmap 对象是通过 GdiSharedHandleTable 获得的，如 gSharedInfo 不是同一个表），并且该对象跟 bitmap 对象都有一个特点，就是我们可以控制该对象的大小，因此，在创建 accelerator table 对象和 bitmap 对象时，通过将其 size 指定为大于一页，这时申请对象就会需要 MiAllocatePoolPages 来分配。而通过上面提到的重复分配+释放的手段，最终我们就可以预测到 bitmap 的地址。

> 通过 CreateAcceleratorTable 创建 0x1000 size 的加速表，立刻 free 掉创建的 AcceleratorTable，不断重复，当再次请求分配 AcceleratorTable 与前一个释放掉的 AcceleratorTable 相同时，请求分配 Bitmap objects，这时 pHead 指针的地址就是结构成员 pKernelAddress 所在的位置。
> [Windows10 v1607内核提权技术的发展——利用AcceleratorTable-安全客 - 安全资讯平台](https://www.anquanke.com/post/id/168356)

在 v1703 (rs2) 中，handleentry 的 pHead 字段再次被指控，此后我们便无法通过 accelerator table 来预测 bitmap 的地址了。

# HmValidateHandle 与 ulClientDelta

这个函数可以通过一个窗口句柄返回内核 tagWND 对象的内核地址。内核中的 tagWND 对象是存放在 desktop heap 中的，而 desktop heap 在不但存在于内核地址中，还在用户地址有一份映射，映射的代码在 MapDesktop 函数中。

```cpp
NTSTATUS MapDesktop(
    PKWIN32_OPENMETHOD_PARAMETERS pOpenParams)
{
//..
    /*
     * Allocate a view of the desktop.
     */
    pdvNew = UserAllocPoolWithQuota (sizeof (*pdvNew), TAG_PROCESSINFO);
    if (pdvNew == NULL) {
        Status = STATUS_NO_MEMORY;
        goto Exit;
    }

    /*
     * Read/write access has been granted. Map the desktop memory into
     * the client process.
     */
    ulViewSize = 0;
    liOffset. QuadPart = 0;
    pClientBase = NULL;

    Status = MmMapViewOfSection (hsectionDesktop,
                                pOpenParams->Process,
                                &pClientBase,
                                0,
                                0,
                                &liOffset,
                                &ulViewSize,
                                ViewUnmap,
                                SEC_NO_CHANGE,
                                PAGE_EXECUTE_READ);
    if (! NT_SUCCESS (Status)) {
        RIPMSG1 (RIP_WARNING,
                "MapDesktop - failed to map to client process (Status == 0x%x).",
                Status);

        RIPNTERR0 (Status, RIP_VERBOSE, "");
        UserFreePool (pdvNew);
        Status = STATUS_NO_MEMORY;
        goto Exit;
    }

    /*
     * Link the view into the ppi.
     */
    pdvNew->pdesk         = pdesk;
    pdvNew->ulClientDelta = (ULONG_PTR)(pheap - pClientBase);
    pdvNew->pdvNext       = ppi->pdvList;
    ppi->pdvList          = pdvNew;
//...
}
```

通过代码我们可以看到，内核会将 desktop heap 在用户地址映射一份，并且计算出 desktop heap 内核地址与用户地址的差存入 desktop view 的 ulClientDelta 字段。这代表当我们知道内核中 tagWND 的地址时，我们可以通过其内核地址 ulClientDelta 计算出该对象的用户地址。但是 ulClientDelta 可以从哪里获取呢？答案在 zzzSetDesktop 函数中。

```cpp
VOID zzzSetDesktop(
    PTHREADINFO pti,
    PDESKTOP    pdesk,
    HDESK       hdesk)
{
    //...
    
    pteb = PsGetThreadTeb(pti->pEThread);
    if (pteb) {
        PDESKTOPVIEW pdv;
        if (pdesk && (pdv = GetDesktopView(pti->ppi, pdesk))) {

            pti->pClientInfo->pDeskInfo =
                    (PDESKTOPINFO)((PBYTE)pti->pDeskInfo - pdv->ulClientDelta);

            pti->pClientInfo->ulClientDelta = pdv->ulClientDelta;
    //...
}
```

zzzSetDesktop 会从 desktop view 中取出 ulClientDelta 字段，放入 pti 的 pClientInfo 中。但是这个 pClientInfo 似乎跟 TEB 没什么关系啊？我们继续看这个 pClientInfo，定位到 xxxCreateThreadInfo

```cpp
NTSTATUS xxxCreateThreadInfo(
    PETHREAD pEThread,
    BOOL     IsSystemThread)
{
//...
    if (pteb != NULL) {
        try {
            pteb->Win32ThreadInfo = ptiCurrent;
        } except (W32ExceptionHandler(FALSE, RIP_WARNING)) {
              Status = GetExceptionCode();
              goto CreateThreadInfoFailed;
        }
    }

    /*
     * Point to the client info.
     */
    if (dwTIFlags & TIF_SYSTEMTHREAD) {
        ptiCurrent->pClientInfo = UserAllocPoolWithQuota(sizeof(CLIENTINFO),
                                                  TAG_CLIENTTHREADINFO);
        if (ptiCurrent->pClientInfo == NULL) {
            Status = STATUS_NO_MEMORY;
            goto CreateThreadInfoFailed;
        }
    } else {
        /*
         * If this is not a system thread then grab the user mode client info
         * elsewhere we use the GetClientInfo macro which looks here
         */
        UserAssert(pteb != NULL);

        try {
            ptiCurrent->pClientInfo = ((PCLIENTINFO)((pteb)->Win32ClientInfo));
        } except (W32ExceptionHandler(FALSE, RIP_WARNING)) {
              Status = GetExceptionCode();
              goto CreateThreadInfoFailed;
        }
//...
}
```

很明显，当不是 system thread 的时候，这个 pClientInfo 就来自 peb 中的 Win32ClientInfo，因此在 zzzSetDesktop 中将 ulClientDelta 存入到 pti 指向的 pClientInfo 实际上就是存入了 peb 中。

现在我们可以通过 HmValidateHandle 获得对象 tagWND 的内核地址，还可以通过 teb 获得 ulClientDelta，即内核桌面堆地址与映射到用户地址的偏移，因此现在我们可以准确的计算出 tagWND 对象的用户地址。

那么 tagWND 中有什么？

```cpp
typedef struct tagWND
{
//...
    struct tagCLS*  pcls;      /* 0x001c Pointer to window class        */
//...
} WND;
/* Window class structure */
typedef struct tagCLS
{
    /* NOTE: The order of the following fields is assumed. */
    struct tagCLS*  pclsNext;
    WORD        clsMagic;
    ATOM        atomClassName;
    struct tagDCE*  pdce;          /* DCE * to DC associated with class */
    int         cWndReferenceCount;   /* The number of windows registered
                         with this class */
    WORD        style;
    WNDPROC     lpfnWndProc;
    int         cbclsExtra;
    int         cbwndExtra;
    HMODULE         hModule;
    HICON       hIcon;
    HCURSOR     hCursor;
    HBRUSH      hbrBackground;
    LPSTR       lpszMenuName;
    LPSTR       lpszClassName;
} CLS;
```

tagWND 中有指向 tagCLS 内核地址的指针，同样根据 ulClientDelta，我们可以计算出 tagCLS 的用户地址。而 tagCLS 结构中存放了一个 lpszMenuName 指针，这个位置分配的内存是 pagepool，因此与 bitmap 在同一个池中，可以起到与 accelerator table 相同的效果。

```cpp
PCLS InternalRegisterClassEx (
    LPWNDCLASSVEREX cczlpwndcls,
    WORD fnid,
    DWORD CSF_flags)
{
                UNICODE_STRING strMenuName;

                /*
                 * Alloc space for the Menu Name.
                 */
                AllocateUnicodeString (&strMenuName, &UString); 
}

```

在 rs2 (1703)  Creators Update 中，微软移除了 Win32ClientInfo 结构体内的 ulClientDelta 指针，因此这种方法无法继续泄露地址了。

# GDI Palette

在 rs3 (v1709) 中，bitmap 还开启了 type isolation，进一步缓解了这种漏洞利用手法，而安全研究者们再次找到了另一个对象 Palette，该对象类似 bitmap, 存在 SetPaletteEntries 函数可以被我们利用，跟进 SetPaletteEntries 函数，在其内部函数 GreSetPaletteEntries 中可以看到，HPALETTE 对应的类是 EPALOBJ，而该类中有一个指向 PALETTE 结构的指针 ppal，是实际内容，该函数通过 `XEPALOBJ::ulSetEntries` 最终实现功能，让我们看一下 `XEPALOBJ::ulSetEntries` 的代码：

```cpp
ULONG XEPALOBJ::ulSetEntries(ULONG iStart, ULONG cEntry, CONST PALETTEENTRY *ppalentry)
{
    ASSERTGDI(bIsPalDC(), "ERROR: ulSetEntries called on non-DC palette");

// Make sure they aren't trying to change the default or halftone palette.
// Make sure they aren't trying to pass us NULL.
// Make sure the start index is valid, this checks the RGB case also.

    if ((ppal == ppalDefault)               ||
        bIsHTPal()                          ||
        (ppalentry == (PPALETTEENTRY) NULL) ||
        (iStart >= ppal->cEntries))
    {
        return(0);
    }

// Make sure we don't try to copy off the end of the buffer

    if (iStart + cEntry > ppal->cEntries)
        cEntry = ppal->cEntries - iStart;

// Let's not update the palette time if we don't have to.

    if (cEntry == 0)
        return(0);

// Copy the new values in

    PPALETTEENTRY ppalstruc = (PPALETTEENTRY) &(ppal->apalColor[iStart]);
    PBYTE pjFore     = NULL;
    PBYTE pjCurrent  = NULL;

// Mark the foreground translate dirty so we get a new realization done
// in the next RealizePaletette.

    if (ptransFore() != NULL)
    {
        ptransFore()->iUniq = 0;
        pjFore = &(ptransFore()->ajVector[iStart]);
    }

    if (ptransCurrent() != NULL)
    {
        ptransCurrent()->iUniq = 0;
        pjCurrent = &(ptransCurrent()->ajVector[iStart]);
    }

// Hold the orginal values in temporary vars.

    ULONG ulReturn = cEntry;

    while(cEntry--)
    {
        *ppalstruc = *ppalentry;

        if (pjFore)
        {
            *pjFore = 0;
            pjFore++;
        }

        if (pjCurrent)
        {
            *pjCurrent = 0;
            pjCurrent++;
        }

        ppalentry++;
        ppalstruc++;
    }

// Set in the new palette time.

    vUpdateTime();

// Mark foreground translate and current translate invalid so they get rerealized.

    return(ulReturn);
}
```

可以看到该类中的 ppal->apalColor 被一一设置了 ppalentry 中的内容，而 ppalentry 的内容是我们可控的，这意味着如果我们能控制这个 apalColor 字段便可以实现任意写。

```cpp
class PALETTE : public OBJECT
{
public:
//...
ULONG   cEntries;      // count of entries currently in palette
//...
    PAL_ULONG  *apalColor;  // Pointer to color table.   Usually points to
                            // &apalColorTabe[0], except for a DirectDraw
                            // GetDC surface, for which it points directly to
                            // the screen surface's color table
    PALETTE    *ppalColor;  // Palette that owns the color table

    // NOTE: THIS IS A VARIABLE-LENGTH FIELD AND MUST BE LAST

    PAL_ULONG  apalColorTable[1]; // array of rgb values that each index corresponds
                                  // plus array of intensities from least intense to most
                                  // intense (plus index to corresponding rgb value)
};
```

利用起来跟 bitmap 一致，因此就不多说了。在缓解上，当 Palette 开启了 type isolation 后 (rs4 v1803)，那种扩展利用的手法也同样无法使用了。

# Type Isolation
> We live in a world where there is a lot of buggy software, and a lot of crafty attackers.

> Unfortunately, we can’t fix every bug.

> What we need are mitigations: ways to make bugs more difficult, or even impossible, to exploit.

> We are raising the bar for hackers.

> -- The Life And Death of Kernel Object Abuse - D1 COMMSEC - Saif Elsherei and Ian Kronquist 

type isolation 是针对上面 bitmap 的扩展利用而开发出的缓解措施，其目的旨在保护一些 ntgdi 和 ntuser 类型的对象免受 uaf 的攻击，通过使攻击者难以操作内存布局让漏洞难以被利用。要注意的是，完全的任意内存写并不在 type isolation 的威胁模型之内，该措施在于防止攻击者在具有一个不完全的任意内存写后将其扩大成一个完全的任意内存写。

在具体实现上，type isolation 分离了对象头与数据部分。以 bitmap 举例，SURFOBJ 后面跟的是该对象的数据部分，在开启了 type isolation 后，SURFOBJ 结构与数据部分不再连续的放在内存中，而是分开来，存放于不同的堆中。对象头部分会存在与 isolated heap 中，而数据部分放于正常的堆中。


Reference：

Abusing GDI  for ring0 exploit primitives.  Diego Juarez - Exploit Developer  Ekoparty 2015

Abusing GDI for ring0 exploit primitives: RELOADED. Nicolas A. Economou. Diego Juarez

Abusing GDI for ring0 exploitprimitives: Evolution. By Nicolas A. Economou

The Life And Death of Kernel Object. AbuseSaif ElSherei (0x5A1F) & Ian Kronquist

[Reverse Engineering the Win32k Type Isolation Mitigation](https://blog.quarkslab.com/reverse-engineering-the-win32k-type-isolation-mitigation.html)

[猫鼠游戏：Windows内核提权样本狩猎思路分享 - FreeBuf网络安全行业门户](https://www.freebuf.com/vuls/267298.html)

---

花了三周时间学习 gdi 系列的利用手法以及 windows 池之类的相关知识，深感不易，然而这大概也只是漏洞的冰山一角。有时候会觉得自己接触安全太晚了，如果从 xp 时代开始弄，那么就不会有那么多安全机制和缓解措施，接触前沿技术的门槛会低很多。而现在我感觉要能看到安全的前沿都十分费力，不过也有好处就是了，那就是现在有大量的资料可以参考，学起来比那时候要轻松很多。