+++
title = 'My First Post'
date = 2024-08-03T00:11:28+08:00
draft = false
+++
This is my first blog post
```cpp
int main(){
    B b;
    return 0;
}
```



### Badge
{{< badge >}}
新文章！
{{< /badge >}}


### 短页码
{{< alert >}}
**警告！** 这个操作是破坏性的！
{{< /alert >}}


{{< alert "twitter" >}}
别忘了在Twitter上[关注我](https://twitter.com/jpanther)。
{{< /alert >}}


### Button
button 输出一个样式化的按钮组件，用于突出显示主要操作。它有三个可选参数：

参数	描述
href	按钮应链接到的 URL。
target	链接的目标。
download	浏览器是否应下载资源而不是导航到 URL。此参数的值将是下载文件的名称。
示例:

{{< button href="#button" target="_self" >}}
Call to action
{{< /button >}}




差分数组的主要适用场景是频繁对原始数组的某个区间的元素进行增减

比如说，我给你输入一个数组 `nums`，然后又要求给区间 `nums[2..6]` 全部加 1，再给 `nums[3..9]` 全部减 3，再给 `nums[0..4]` 全部加 2，再给...

差分数组
```cpp
diff[i] = nums[i] - nums[i - 1];
```
构造差分数组
```cpp
vector<int>diff(nums.size());
diff[0] = nums[0];
for (int i = 1; i < nums.size(); ++i){
	diff[i] = nums[i] - nums[i-1];
}
```
通过差分数组可以反推出原始数组nums
```cpp
vector<int> res(diff.size());
res[0] = diff[0];
for (int i = 1; i < nums.size(); ++i){
	res[i] = res[i - 1] + diff[i];
}
```
按照这样的逻辑，如果需要在数组的某个区间进行增减操作。比如，需要在[i...j]区间，对元素加上x，只需要对
```cpp
diff[i] += x, diff[j + 1] -= x;
```
可以理解反推出的原始数组与diff[i]是有累加关系的，diff[i] + x相当于对i元素后的每一个数组元素都进行了+x, 为了实现要求，需要低效掉j元素后的+x，所以diff[j + 1] -x.

**需要注意的是**
- 差分数组`diff[0] = nums[0];` 
- 差分数组和反推出的数组，长度一致
- 具体的题目可能回看数组的索引进行偏移，比如航班问题，数组是从1开始，需要人为处理。
- 最开始的差分数组可以全为0
