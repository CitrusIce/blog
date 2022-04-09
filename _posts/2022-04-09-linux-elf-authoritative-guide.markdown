---
layout: post
title: "Linux ELF权威指南"
date: 2022-04-09 13:31:40 +0800
categories: linux elf
---

本文不是指南，也并不权威。起这个标题只是想模仿《Window PE 权威指南》这本在我 Windows 入门过程中起到十分重要作用的书。而现在我需要研究研究 linux 相关的技术，因此就起了对应的标题。另外，如果你想要入门 Windows 相关知识用于逆向、开发、武器化等方向，我同样推荐这本书。

# 文件头

同样是由 coff 格式发展而来的 elf 与 pe 一样，一切都是从文件头开始。

```cpp
typedef struct
{
  unsigned char	e_ident[EI_NIDENT];	/* Magic number and other info */
  Elf64_Half	e_type;			/* Object file type */
  Elf64_Half	e_machine;		/* Architecture */
  Elf64_Word	e_version;		/* Object file version */
  Elf64_Addr	e_entry;		/* Entry point virtual address */
  Elf64_Off	e_phoff;		/* Program header table file offset */
  Elf64_Off	e_shoff;		/* Section header table file offset */
  Elf64_Word	e_flags;		/* Processor-specific flags */
  Elf64_Half	e_ehsize;		/* ELF header size in bytes */
  Elf64_Half	e_phentsize;		/* Program header table entry size */
  Elf64_Half	e_phnum;		/* Program header table entry count */
  Elf64_Half	e_shentsize;		/* Section header table entry size */
  Elf64_Half	e_shnum;		/* Section header table entry count */
  Elf64_Half	e_shstrndx;		/* Section header string table index */
} Elf64_Ehdr;
```

相比于 pe 的复杂文件头，elf 的文件头简单许多。比较重要的几个项：
- e_entry 入口点地址
- e_phoff program header FOA
- e_shoff section header FOA

program header 描述了文件装载到内存后的布局，每一个 entry 描述一个 segment 或其他信息用于文件的执行；section header 则描述了文件中各个 section 的信息，在 elf 装在过程中，文件中的 section 会被载入到内存中可执行文件的各个 segment 中。

使用 readelf 可以看到 elf 中 section 与 segment 的对应关系
```bash
$ readelf -l a.out

Elf file type is DYN (Shared object file)
Entry point 0x1060
There are 13 program headers, starting at offset 64

Program Headers:
  Type           Offset             VirtAddr           PhysAddr
                 FileSiz            MemSiz              Flags  Align
  PHDR           0x0000000000000040 0x0000000000000040 0x0000000000000040
                 0x00000000000002d8 0x00000000000002d8  R      0x8
  INTERP         0x0000000000000318 0x0000000000000318 0x0000000000000318
                 0x000000000000001c 0x000000000000001c  R      0x1
      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
  LOAD           0x0000000000000000 0x0000000000000000 0x0000000000000000
                 0x00000000000005f8 0x00000000000005f8  R      0x1000
  LOAD           0x0000000000001000 0x0000000000001000 0x0000000000001000
                 0x00000000000001f5 0x00000000000001f5  R E    0x1000
  LOAD           0x0000000000002000 0x0000000000002000 0x0000000000002000
                 0x0000000000000160 0x0000000000000160  R      0x1000
  LOAD           0x0000000000002db8 0x0000000000003db8 0x0000000000003db8
                 0x0000000000000258 0x0000000000000260  RW     0x1000
  DYNAMIC        0x0000000000002dc8 0x0000000000003dc8 0x0000000000003dc8
                 0x00000000000001f0 0x00000000000001f0  RW     0x8
  NOTE           0x0000000000000338 0x0000000000000338 0x0000000000000338
                 0x0000000000000020 0x0000000000000020  R      0x8
  NOTE           0x0000000000000358 0x0000000000000358 0x0000000000000358
                 0x0000000000000044 0x0000000000000044  R      0x4
  GNU_PROPERTY   0x0000000000000338 0x0000000000000338 0x0000000000000338
                 0x0000000000000020 0x0000000000000020  R      0x8
  GNU_EH_FRAME   0x0000000000002010 0x0000000000002010 0x0000000000002010
                 0x0000000000000044 0x0000000000000044  R      0x4
  GNU_STACK      0x0000000000000000 0x0000000000000000 0x0000000000000000
                 0x0000000000000000 0x0000000000000000  RW     0x10
  GNU_RELRO      0x0000000000002db8 0x0000000000003db8 0x0000000000003db8
                 0x0000000000000248 0x0000000000000248  R      0x1

 Section to Segment mapping:
  Segment Sections...
   00
   01     .interp
   02     .interp .note.gnu.property .note.gnu.build-id .note.ABI-tag .gnu.hash .dynsym .dynstr .gnu.version .gnu.version_r .rela.dyn .rela.plt
   03     .init .plt .plt.got .plt.sec .text .fini
   04     .rodata .eh_frame_hdr .eh_frame
   05     .init_array .fini_array .dynamic .got .data .bss
   06     .dynamic
   07     .note.gnu.property
   08     .note.gnu.build-id .note.ABI-tag
   09     .note.gnu.property
   10     .eh_frame_hdr
   11
   12     .init_array .fini_array .dynamic .got
 ```

# 导入表

elf 其实没有导入表，相对的，它直接使用符号的概念来替代导入函数。elf 中有两个符号表，分别为.dynsym section 和.symtab sectio，.dynsym 只包含动态链接所需要的符号，.symtab 则包含程序中的所有符号，.dynsym 为.symtab 的子集。在 elf 装载的过程中，.dynsym 需要被装载到内存中，而.symtab 则无需装载到内存。对于程序的运行来说，.symtab 是不必要的，因此可以使用 strip 来删去 elf 中的.symtab。你可以把.dynsym 理解为 pe 中的导入导出表，而 symtab 则是程序编译出来所产生的 pdb 文件。

## 导入与导出：

在符号表的每项中字段 st_shndx 表示了符号的类型，如果符号类型为 SHN_UNDEF (0) 则代表这个符号在当前文件中没有定义，是需要导入的符号。同时符号具有可见性级别，在 st_other 字段的低 3 位有对于符号可见性的定义，分别是：
- STB_LOCAL 本地可见，只有当前文件可见的符号
- STB_GLOBAL 全局可见，设置此项意味着这个符号是导出的
- STB_WEAK 类似全局可见，但是具有低优先级

## .got: elf 中的 iat 表

装载器在获取到程序需要的函数地址后，将地址写入到 got 表中。got 表中的第一项为.dynamic section 的偏移，在有 plt 的情况下，第二项为 link_map ，第三项为_dl_runtime_resolver，之后则是各个符号的地址。

## 填充 got 表：

值得注意的是，.dynsym 与 .got 并没有明确的对应关系，也就是说单单从这两张表无法得知 got 表中的某项是哪个符号的地址。而其对应关系存在 elf 的.rela section，是重定位相关的 section 。因此符号的地址的填充就被放在了重定位相关的过程中，这个放到下一段说。

# 重定位

在说重定位之前首先要说 linux 的 pic 技术，而在说 pic 技术之前还要先说 x86 的指令架构以及 aslr。x86 指令中对于内存数据的读写往往是通过绝对地址来寻址的。举一个例子
```asm
;833D BC69BB77 00
cmp dword ptr ds:[0x77BB69BC], 0x0;
```
这条指令访问了内存 0x77BB69BC ，我们可以看到其地址是直接写在字节码中的。而在 x64 中，这个地址则会被转换为相对于下一条指令地址的偏移。如果使用绝对地址寻址，那就代表这个程序在内存中加载的位置必须是固定的，如果改变了位置，那么就会找不到相应的数据。而 aslr 机制则会让程序在不同的地址上加载，这就使程序无法正常运行。windows 的解决方案是重定位表，即在程序在内存装载后，通过程序中的重定位表对程序进行修补让程序可以正常运行。在 linux 中，不光有重定位表，还有 pic 技术。

pic 由编译器实现，即通过生成地址无关代码来使程序可以在不同地址下运行。其中对数据的访问部分，编译器将需要绝对地址寻址的部分改为间接地址寻址。看一个例子

```asm
endbr32
lea     ecx, [esp+4]
and     esp, 0FFFFFFF0h
push    dword ptr [ecx-4]
push    ebp
mov     ebp, esp
push    ebx
push    ecx
call    __x86_get_pc_thunk_ax; 获取eip
add     eax, (offset _GLOBAL_OFFSET_TABLE_ - $) ;获取到got表
sub     esp, 0Ch
lea     edx, (str - 3FD8h)[eax] ; "adfafds" got表地址+got表到str字符串地址的偏移
push    edx             ; format
mov     ebx, eax
call    _printf
add     esp, 10h
mov     eax, 0
lea     esp, [ebp-8]
pop     ecx
pop     ebx
pop     ebp
lea     esp, [ecx-4]
retn
```

尽管有 pic，但是仍有需要修正的数据，如全局变量中的函数指针就需要在运行时进行修正，因此 elf 中仍然有重定位表。elf 中的 .rel.plt 、.rel.dyn 就是其重定位表。其中.rel.dyn 是对代码段访问的修正，.rel.plt 是对代码段函数调用的修正。

重定位的过程中也包括了对导入符号的填充，因此每个重定位项中就包含了 got 表与.dynsym 中符号的对应关系。
```c
// 重定位项结构体
typedef struct {
	Elf32_Addr	r_offset;
	Elf32_Word	r_info;
} Elf32_Rel;

typedef struct {
	Elf32_Addr	r_offset;
	Elf32_Word	r_info;
	Elf32_Sword	r_addend;
} Elf32_Rela;

typedef struct {
	Elf64_Addr	r_offset;
	Elf64_Xword	r_info;
} Elf64_Rel;

typedef struct {
	Elf64_Addr	r_offset;
	Elf64_Xword	r_info;
	Elf64_Sxword	r_addend;
} Elf64_Rela;
```
[Relocation](https://refspecs.linuxbase.org/elf/gabi4+/ch4.reloc.html)
- `r_info`
- This member gives both the symbol table index with respect to which the relocation must be made, and the type of relocation to apply. For example, a call instruction's relocation entry would hold the symbol table index of the function being called. If the index is `STN_UNDEF`, the undefined symbol index, the relocation uses 0 as the \`\`symbol value''. Relocation types are processor-specific; descriptions of their behavior appear in the processor supplement. When the text below refers to a relocation entry's relocation type or symbol table index, it means the result of applying `ELF32_R_TYPE` (or `ELF64_R_TYPE`) or `ELF32_R_SYM` (or `ELF64_R_SYM`), respectively, to the entry's `r_info` member.

r_info 中给出了重定位目标的类型与重定位目标在符号表中的索引（如果有的话），与 r_offset 相结合形成了.dynsym 与 got 的对应关系。在重定位过程中，动态链接器根据符号索引找到程序所要导入的符号，再将符号地址写入到 got 表的相应位置（由 r_offset 计算得出）。

---

一些参考资料：

[Inside ELF Symbol Tables](https://blogs.oracle.com/solaris/post/inside-elf-symbol-tables)

[7.5. ELF在Linux下的动态链接实现](http://nicephil.blinkenshell.org/my_book/ch07s05.html)

[Symbol Table Section - Linker and Libraries Guide](https://docs.oracle.com/cd/E23824_01/html/819-0690/chapter6-79797.html#chapter6-tbl-21)

[隨意寫寫: 如何解讀 dynamic section](http://brandon-hy-lin.blogspot.com/2015/12/dynamic-section.html)