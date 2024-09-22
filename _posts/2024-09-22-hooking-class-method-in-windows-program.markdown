---
layout: post
title: "Hook Windows 程序的类成员函数"
date: 2024-09-22 10:55:46 +0800
categories: hook windows
---

对于 inline hook 这种技术我相信大家早已耳熟能详，我们往往使用 detours 或者 minhook 等框架来对函数进行挂钩。然而，hook 类成员函数却并不那么容易。

假设有这么个类：

```cpp
class ClassA
{
  public:
    void funcA() {}
};
```

我们的目标是对 funcA 进行 hook。

遇到的第一个问题就是我们很难获取目标函数的地址。像 hook 框架如 minhook，都需要我们传入一个函数目标地址，这个地址类型是 `void*` 类型的:

```cpp
MH_STATUS WINAPI MH_CreateHook(LPVOID pTarget, LPVOID pDetour, LPVOID *ppOriginal)
```

但是当我们想直接对 `ClassA::funcA` 取地址的时候就会遇到报错：

```cpp
//invalid type conversionC/C++(171)
void* funcAPtr = (void*)&ClassA::funcA;
//invalid type conversionC/C++(171)
void* funcAPtr = reinterpret_cast<void*>(&ClassA::funcA);
```

那么难道对于类成员函数，就不能有一个指向类成员函数的指针吗？不是的，只是它必须是指向该类成员函数的函数指针，也就是 `void(ClassA::*)()`，用代码来说就是你必须得这样：

```cpp
typedef void (ClassA::*PFN_FUNC_A)();
PFN_FUNC_A funcAPtr = &ClassA::funcA;
```

但这仍然不解决我们的问题，我们需要的是一个 `void*` 类型的指针而不是指向成员函数的指针，但 cpp 标准中这两者之间恰恰无法相互转换。幸好，msvc 有一个比较 hack 的方法来解决这个问题：

```cpp
auto ptr = &ClassA::funcA;
void* funcAPtr = (void*&)ptr;
```

这实际上是未定行为但是它刚好解决了我们的问题，现在我们有了指向这个类成员函数的地址。

另外在看了 StackOverflow 的回答后我看到了另外一种更优雅的办法，适用于任何编译器：

```cpp
union {
    PFN_FUNC_A funcAMethodPtr;
    void* funcAPtr;
} autoPtr = {&ClassA::funcA};
void* funcAPtr = autoPtr.funcAPtr;
printf("ClassA::funcA:0x%p\n", funcAPtr);
```

因为我们知道指针长度是相等的，通过 union 结构我们可以轻松的做数据类型转换。

现在还需要编写 stub 函数。由于成员函数的调用预定是 thiscall，但是正常来说你不能直接这样

```cpp
void __thiscall stub();
```

在 x64 情况下所有调用约定都是直接 rcx/rdx/r8/r9 这么顺序传参，并且由调用者创建栈帧，因此我们可以直接编写 stub 函数

```cpp
void stub(void* this) {}
```

而在 x86 下，cdecl 方式全部通过栈传递参数，而 thiscall 却需要通过 ecx 传递，所以没办法直接用 cdecl 函数来做 stub。那么有哪些其他的方式呢？最简单的就是再创建一个 class，在新 class 中定义一个相同的参数的函数来作为 stub，例如：

```cpp
class StubClassA{
public:
    void stubFuncA();
}
```

这样的方式又有点麻烦，毕竟光是获取这个 stubFuncA 的地址就需要一番操作。幸好我们还有其他选择，那就是 fastcall。

fastcall 通过 ecx/edx 传递前两个参数，并且与 thiscall 一样都是由被调用者平栈，因此通过 fastcall 我们就能获取到 this 指针了，我们可以这样写：

```cpp
void __fastcall stubFuncA(void* this,void* edx,void* arg1，void* arg2, .....);
```

这样我们便可以通过 stub 函数来接收参数。

最后一个问题，在 stub 中我们还需要调用原始被 hook 的函数，如何通过成员函数指针来调用成员函数呢？

```cpp
typedef void (ClassA::*PFN_FUNC_A)();
PFN_FUNC_A originalFuncA;
void __fastcall hookFuncA(ClassA* thisPtr){
    (thisPtr->*originalFuncA)();
    // or
    ((*thisPtr).*originalFuncA)();
}
```

至此，类成员函数的hook就可以实现了。

文章中出现的代码：

```cpp
#include <iostream>

class ClassA
{
  public:
    void funcA() {}
};

class StubClassA{
public:
    void stubFuncA();
};

typedef void (ClassA::*PFN_FUNC_A)();
PFN_FUNC_A originalFuncA;

void __fastcall hookFuncA(ClassA* thisPtr){
    (thisPtr->*originalFuncA)();
    // or
    ((*thisPtr).*originalFuncA)();
}

int main()
{
    ClassA objA;
    PFN_FUNC_A funcAMethodPtr = &ClassA::funcA;
    {
        auto ptr = &ClassA::funcA;
        void* funcAPtr = (void*&)ptr;
        printf("ClassA::funcA:0x%p\n", funcAPtr);
    }

    {
        union {
            PFN_FUNC_A funcAMethodPtr;
            void* funcAPtr;
        } autoPtr = {&ClassA::funcA};

        void* funcAPtr = autoPtr.funcAPtr;
        printf("ClassA::funcA:0x%p\n", funcAPtr);
    }
}
```

---

参考：

https://isocpp.org/wiki/faq/pointers-to-members

https://stackoverflow.com/questions/8121320/get-memory-address-of-member-function