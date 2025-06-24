+++
title = '2025 06 23 02 Cpu_data'
date = 2025-06-23T02:05:31+08:00
draft = true
+++


CPU的发展历史
1. 图灵机
2. 冯诺伊曼模型
计算机的基本结构(运算器、控制器、存储器、输入设备、输出设备)
运算器、控制器在CPU里，存储器就是常见的内存、输入出设备就是计算机的外接设备，比如键盘 显示器。

### 存储器
分为 寄存器、各级Cache、内存、SSD
存储数据的基本单位是字节(byte)，每一个字节对应一个内存地址

一般CPU读写寄存器的速度是半个CPU cycle，对于2GHz的CPU来讲，就是0.5 ns
32位CPU中寄存器可以存储 4 个字节；64位，存储 8 个字节


### CPU cahce(SRAM芯片)
L1 cache 2-4 cycles ; 32k + 32 kb
L2 cache 10 -20 cycles ; 256 kb
L3 cache 20 -60 cycles; 3072 kb
如何查看cache的大小
```bash
root@racknerd-65cf40b:~# cat /sys/devices/system/cpu/cpu0/cache/index0/coherency_line_size 
64
```


### 内存(DRAM)
200 - 300 cycles

CPU访问数据的流程，寄存器 -> L1 cache -> L2 cache -> L3 cache -> memory


cpu L1 cache随机访问的延迟是1 ns ，内存是100ns，是内存的100倍左右。




### CPU

32位
32位CPU一次可以计算4个字节
64位
一次可以计算8个字节

### CPU的组成
寄存器、控制单元、逻辑运算单元
寄存器：通用寄存器、程序计数器、指令寄存器

cpu的时间周期 = 1 / Freq

2GHz的cpu 一般时间周期 = 0.5ns



#### CPU的架构
一个CPU里有多个CPU核心，每个核心有自己的L1 cache、L2 cache，所有的CPU 核心共享L3 cache

Cache 分为 1. data cache 2. instrument cache

Cache 

### 如何写出让CPU跑得更快的代码
L1 cache 2-4 cycles ; 32k + 32 kb
L2 cache 10 -20 cycles ; 256 kb
L3 cache 20 -60 cycles; 3072 kb
内存 200 - 300 cycles

cpu所要操作的数据在cpu cache中的话，将会带来很大的性能提升。访问的数据在CPU cache中，意味着缓存命中，缓存命中率越高，代码被读取的数据就越快，CPU也就跑得越快。

所以，如何写出让CPU跑得更快的代码 这个问题，可以改成 如何写出CPU缓存命中率高的代码

这里需要分开来看 数据缓存 和 指令缓存 的缓存命中率

- 提升数据缓存的命中率
比如，遍历二维数组，二维数据的内存布局是按照行顺序的，为了提升缓存命中率，遍历时也需要按照行来顺序访问。这种遍历方式能有效的利用 CPU cache 带来的好处。因为CPU读取内存是顺序读取，一次读取cache line = 64kb 大小，下次需要访问vec[i][j + 1]时，可以直接从cache 中访问，而不是memory。

- 提升指令缓存的命中率

提升分支预测准确率
例如：有一个元素0 到 100之间随机数字组成的一维数组，需要筛选出小于50的元素。
有两种做法，
1. 直接遍历，判断是否小于50
2. 先排序，再判断是否小于50

2的方式更高效，分支预测能更准确

如果分支可以预测到接下来要执行if里的指令，还是else指令的话，就可以[提前] 把这些指令放在指令缓存中，这样CPU可以直接从Cache 读取到指令，于是执行速度就会很快。





