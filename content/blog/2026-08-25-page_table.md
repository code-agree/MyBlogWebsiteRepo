+++
title = '虚拟内存与 Page Table:从一次访存看懂 MMU、TLB、Page Fault 的完整机制'
date = 2026-08-25T09:00:00+08:00
draft = false
tags = ["Memory", "Linux", "Performance"]
+++

# 虚拟内存与 Page Table:从一次访存看懂 MMU、TLB、Page Fault 的完整机制

进程隔离、共享内存、huge page、lazy allocation、段错误——这些看似独立的现象,底层是同一个机制的不同侧面:**page table(页表)**。本文从零把它讲透,并在最后把上述现象逐一"接回"这张表。

## 0. 起点:程序里的地址全是虚拟的

你代码里的每个指针、每个 `&变量`,都是 **virtual address(虚拟地址)**——不是内存条上的真实位置。CPU 拿到它不能直接访问 RAM,必须先翻译成 **physical address(物理地址)**。

为什么要虚拟化?直接用物理地址的世界没法过:所有程序挤在同一片真实内存里互相可踩(无隔离)、程序必须预知自己被装载到哪(无法重定位)。虚拟化后,**每个进程都以为自己独占一条平坦的地址空间**,真实内存的分配、位置、给不给,由 OS 在翻译层暗中操作。

## 1. Page 与 page table:按页翻译的字典

翻译不能按字节做(字典会比内存还大),所以按 **page(页)** 做:

- 虚拟地址空间切成 4KB 一页 → **page**
- 物理内存切成 4KB 一块 → **page frame(页帧)**
- **page table** = "virtual page number → physical frame number" 的对照字典,**每个进程一本**
- 字典的每个词条 = **PTE**(page table entry)

```
virtual address (64bit) = [ virtual page number ][ offset(12bit) ]
                                  │查 page table         │原样保留
                                  ▼                      ▼
physical address        = [ physical frame number ][ offset ]
```

**每一次访存**(每条 load/store)都要经过这次翻译,执行者是 CPU 里的硬件单元 **MMU**(Memory Management Unit)——"隔离由硬件强制"就是这个字面意思。

### 澄清一个常见混淆:page ≠ TLB

- **page** 是被管理的单位(4KB 的内存块);
- **page table** 是字典;
- **TLB** 是这本字典的**硬件缓存**(下文详述)。

三者关系:字典(page table)按词条单位(page)记录翻译,TLB 缓存最近查过的词条。

## 2. 字典的真实形状:四级 radix tree,不是平铺数组

64 位地址空间平铺建表,单进程字典就要上百 GB——不可能。实际是**四级基数树**(x86-64:PGD → PUD → PMD → PTE 四层):虚拟地址高位切四段,每段索引一层,走到叶子拿到 frame number。**没用到的地址区域整棵子树不存在**,所以字典稀疏,几 MB 即可描述一个进程。

树根的物理地址存在 CPU 的 **CR3 寄存器**。三个重要推论:

1. **进程切换 = 换 CR3**——换一棵树,整个地址世界瞬间切换;
2. **同进程的线程共用同一个 CR3**(同一棵树)——这就是"线程天然共享内存"的硬件本体;
3. **进程隔离的墙**:A 进程的虚拟地址拿到 B 的树上去走,根本走不到同一个落点。

## 3. TLB:翻译的缓存

每次访存都走四层树 = 每条访存指令背后多四次内存访问,不可接受。MMU 里的 **TLB(Translation Lookaside Buffer)** 缓存最近的翻译结果(千余条):

- TLB hit(绝大多数):翻译零开销;
- TLB miss:硬件自动 page walk(走树),~百 cycle 量级。

这直接解释了 **huge page** 的价值:2MB 的大页让**一条 TLB 表项覆盖 512 倍的内存**——同样的工作集,TLB miss 大幅减少。`mmap` 时的 `MAP_HUGETLB`、透明大页(THP),优化的都是这一层(细节见本站 hugepage 两篇)。

## 4. PTE 不只是翻译,还是关卡:标志位与 page fault

每条 PTE 除 frame number 外还带标志位:

| 位 | 含义 | 违反时 |
|---|---|---|
| **Present** | 此页当前有物理帧吗 | 触发 page fault,内核裁决 |
| **R/W** | 可写吗 | 写只读页 → page fault |
| **U/S** | 用户态可访问吗 | 用户碰内核页 → page fault |
| **NX** | 可执行吗 | 执行数据页 → page fault |

**每次访存,MMU 顺手查验标志位**。任何不符 → CPU 触发硬件异常(#PF)陷入内核 → 内核对照进程的合法内存区域表(**VMA**)裁决:

- **合法缺页**(demand paging 按需分页 / CoW / 栈增长):内核悄悄补页、填表、恢复执行——程序毫无感知。**page fault 本身不是错误**,每秒发生无数次;
- **非法访问**:升级为 **SIGSEGV**——这才是"段错误"。段错误是 page fault 中"确认为 bug"的子集。

**Present 位就是 lazy allocation 的机关**:`ftruncate` 出一个 64MiB 的共享内存文件时,PTE 全是 Present=0,一个物理帧都没分配;首次写某页 → page fault → 内核此刻才分配 frame、填表。这就是"虚拟大小(virtual size)巨大而 **RSS** 很小"的机制。

## 5. 回收所有伏笔:一张表解释五个现象

### 5.1 进程隔离(故障半径的墙)

不同进程 = 不同 CR3 = 不同的树。A 的野指针在 B 的树上没有任何路径可达——错误写在**地址翻译阶段**就无处落地,防线是硬件的、逐次访存执行的。这也是"一个线程崩溃带崩全进程、但进程之间互不连坐"的根本原因:**故障隔离的单元 = 内存隔离的单元 = page table 的单元 = 进程**。

### 5.2 共享内存(隔离墙上的窗)

`mmap(MAP_SHARED)` 做的全部事情:**让两个进程各自树上的某些叶子 PTE,指向同一批 physical frame**。

```
进程 A 的树                        进程 B 的树
    ...                                ...
     └─ PTE → frame 0x24c1 ──┐   ┌── PTE → frame 0x24c1
                             ▼   ▼
                    ┌──────────────────┐
                    │ 物理帧 0x24c1     │ ← 同一块真实内存
                    └──────────────────┘
```

由此一次性解释三件事:写一边另一边立刻可见(本来就是同一块内存,跨核可见性由 cache coherence 保证);两边虚拟地址可以不同(树路径不同,落点相同);**共享内存里绝不能存指针**(指针是"树路径"不是"落点",A 的路径在 B 的树上通向别处)。

### 5.3 Lazy allocation

见第 4 节 Present 位:名义容量近乎免费,物理占用随首次触碰逐页兑现。大容量 ring buffer"名义 64MiB、RSS 只算写过的页"即此机制。

### 5.4 fork 与 CoW

fork 后父子两棵树的叶子指向相同 frame,且都标只读;谁先写谁触发 page fault,内核复制一帧、改各自 PTE 再放行——"写时复制"完全是 PTE 标志位的游戏。

### 5.5 mlock 与实时性

page fault 意味着热路径上可能出现毫秒级的补页/换入停顿。低延迟程序用 `mlockall` + 启动期预热(prefault)把所有页钉在内存、提前兑现,让热路径**永不 page fault**——本质是把 Present 位在启动期全部置好。

## 6. 一句话总结

> **Page table = 每进程私有的"虚拟→物理"翻译树 + 每次访存的硬件关卡,由 MMU 逐次执行,TLB 缓存其结果。**
> 它一物四用:不同的树 = 隔离的墙(进程边界、故障半径);叶子同帧 = 共享的窗(shared memory 的全部魔法);Present 位 = lazy allocation 的机关(virtual size vs RSS);权限位 + 缺页裁决 = SIGSEGV 的裁判。

## 附:术语对照表

| 中文 | 英文 | 一句话 |
|---|---|---|
| 页 | page | 虚拟空间的 4KB 切分单位 |
| 页帧 | page frame | 物理内存的 4KB 切分单位 |
| 页表 / 页表项 | page table / PTE | 翻译字典 / 字典词条(含帧号+标志位) |
| 内存管理单元 | MMU | 执行翻译与查验的 CPU 硬件 |
| 翻译后备缓冲 | TLB | 翻译结果的硬件缓存(≠ page!) |
| 缺页 | page fault | MMU 报给内核的中性事件,合法则补页,非法升级 SIGSEGV |
| 按需分页 | demand paging | 首次访问才分配物理帧 |
| 写时复制 | CoW (copy-on-write) | 共享帧+只读标记,写时缺页复制 |
| 大页 | huge page | 2MB/1GB 页,一条 TLB 表项覆盖更多内存 |
| 常驻集 | RSS (resident set size) | 真正占着物理帧的部分 |
| 合法区域表 | VMA (virtual memory area) | 内核记录的进程合法地址区间,缺页裁决的依据 |

## 自测

1. 同进程两线程为什么天然共享内存?(用 CR3 一句话)
2. `mmap(MAP_SHARED)` 后两进程读写同一变量,数据怎么"传"过去?(陷阱题)
3. 64MiB 共享内存文件刚创建完,物理内存用了多少?何时、何机制变成真实占用?
4. 为什么 A 进程的野指针物理上写不进 B 进程的内存?防线在哪个环节?

(答案:1. 同 thread group 共享 mm,CR3 相同——同一棵树;2. 不需要传——两棵树叶子指同一 frame,写的就是同一块内存;3. 约为零(Present=0),首次写触发 page fault 才逐页分配;4. 硬件,MMU 地址翻译环节——B 的 frame 在 A 的树上无路径可达。)
