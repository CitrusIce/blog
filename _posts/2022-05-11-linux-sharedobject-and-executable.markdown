---
layout: post
title: "Linux SharedObject与Executable"
date: 2022-05-11 11:26:10 +0800
categories: linux elf
---

在 windows 中，exe 与 dll 只是一个标志位的差别。而在 linux 中则更为复杂，尽管 linux 中.so (sharedobject) 与 executable 文件同为 elf，但是实际上 executable 文件是无法直接被 dlopen。

如果真的使用如下代码加载 pie 文件
```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

int main(int argc, char** argv)
{
    void *handle;
    void (*func_print_name)(const char*);


    handle = dlopen("./pie", RTLD_LAZY);
    if(!handle)
    {
        printf("%s\n",dlerror());
    }
    dlclose(handle);

    return EXIT_SUCCESS;
}
```

则会报出错误：./pie: cannot dynamically load position-independent executable

于是就去看了下 glibc dlopen 的代码，发现是因为 glibc 在 dlopen 的代码里做了限制
[dl-load.c - elf/dl-load.c - Glibc source code (glibc-2.30) - Bootlin](https://elixir.bootlin.com/glibc/glibc-2.30/source/elf/dl-load.c)
```c
  if ((__glibc_unlikely (l->l_flags_1 & DF_1_NOOPEN)
       && (mode & __RTLD_DLOPEN))
      || (__glibc_unlikely (l->l_flags_1 & DF_1_PIE)
	  && __glibc_unlikely ((mode & __RTLD_OPENEXEC) == 0)))
    {
      /* We are not supposed to load this object.  Free all resources.  */
      _dl_unmap_segments (l);

      if (!l->l_libname->dont_free)
	free (l->l_libname);

      if (l->l_phdr_allocated)
	free ((void *) l->l_phdr);

      if (l->l_flags_1 & DF_1_PIE)
	errstring
	  = N_("cannot dynamically load position-independent executable");
      else
	errstring = N_("shared object cannot be dlopen()ed");
      goto call_lose;
    }
```
当 .dynamic section 的 FLAGS_1 tag 具有 DF_1_NOOPEN 或 DF_1_PIE 标志位时，则拒绝加载该 elf 文件。

解决：
处理这两个标志位，pie 文件就可以被 dlopen 加载

---
 
反过来，如何让一个 sharedobject 可以直接执行？

如果直接执行一个.so 文件，我们会看到 Segmentation fault (core dumped) 。观察.so 文件，首先会看到.so 文件是没有.interp 这个 section 的，因此程序执行的时候不会有动态链接器为程序做动态链接。再看入口点位置，发现指向 deregister_tm_clones 这个函数，这个函数很明显不是我们要的入口函数，因此导致程序无法执行。

解决：
首先在代码中加入.interp 这个区段，为程序加入要使用的动态链接器的名字。然后在编译时指定程序入口点，即可使程序正常运行。

但光这样实际上是不完美的，熟悉 linux 程序运行流程的都知道，程序在执行 main 函数前还有 libc 的初始化流程，如果不进行这个流程，那么一些函数则无法使用。最开始我想在编译的时候将入口点相关的代码编译进.so 文件中，但是 gcc 在编译的时候报错：` __init_array_start can not be used when making a shared object` ，看来在动态库中没法链接入口点相关的代码，因此只好自己手动定义入口点，动态调用__libc_start_main 为 libc 进行初始化。

代码供参考：
```c
const char interp_path[] __attribute__((section(".interp"))) = "/lib64/ld-linux-x86-64.so.2";

int _start(void *a1, void *a2, void (*a3)(void))
{
    void *stack;
    asm(" .intel_syntax noprefix\n\
            and rsp,0x0fffffffffffffff0 \n\
            mov  %0,rsp;\n\
            .att_syntax prefix "
        : "=r"(stack));
    pfn__libc_start_main libc_start_main = dlsym(0, "__libc_start_main");
    libc_start_main(main, 0, 0, 0, 0, 0, &stack);
}
```