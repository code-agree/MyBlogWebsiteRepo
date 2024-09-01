+++
title = 'First Post'
date = 2024-08-04T00:13:28+08:00
draft = false
tag = 'cat'
+++


# Const

Owner: More_surface Ted
Created time: July 25, 2024 4:59 PM

const 可以用来修饰变量、函数、指针等。

1. 修饰变量

当修饰变量时，意味着该变量为只读变量，即不能被修改。

例如

```cpp
const int a = 10;
a = 20; //编译报错，a为只读，不可修改
```

但是可以通过一些指针类型转换操作[const_cast](https://www.notion.so/const_cast-45bcd744ee374253abebd58b83a5c812?pvs=21) ，修改这个变量。

例如

```cpp
int main(){
    const int a = 10;
    const int* p = &a; // p是指向const int类型的对象
    int* q = const_cast<int*>(p);  // 类型转换，将p转换成指向int型对象的指针
    *q = 20;  // 通过指针操作修改 const a的值
    std::cout << a << std::ends; // 输出结果 仍然是10
    return 0;
}
```

输出结果不变，归功于编译器醉做了优化，编译时把代码替换为了如下所示。

`std::cout << "a = " << 10 << std::endl;` 

1. 修饰函数参数，表示函数不会修改参数

```cpp
void func(const int a) {
    // 编译错误，不能修改 a 的值
    a = 10;
}
```

1. 修饰函数返回值

当修饰函数返回值时，表示函数的返回值为只读，不能被修改。好处是可以使函数的返回值更加安全，不会被误修改。

```cpp
const int func() {
    int a = 10;
    return a;
}

int main() {
    const int b = func(); // b 的值为 10，不能被修改
    b = 20; // 编译错误，b 是只读变量，不能被修改
    return 0;
}
```

1. 修饰指针或引用

4.1. const修饰的是指针所指向的变量，而不是指针本身；指针本身可以被修改(可以指向新的变量)，但是不能通过指针修改所指向的变量。

```cpp
const int* p; // 声明一个指向只读变量的指针，可以指向 int 类型的只读变量
int a = 10;
const int b = 20;
p = &a; // 合法，指针可以指向普通变量
p = &b;  // 合法，指针可以指向只读变量
*p = 30; // 非法，无法通过指针修改只读变量的值

```

4.2. 只读指针

const关键字修饰的是指针本身，使得指针本身成为只读变量。

这种情况指针本身不能被修改(即一旦初始化就不能指向其他变量)，但是可以通过指针修改所指向的变量

```cpp
int a = 10;
int b = 10;
int* const p = &a; // 声明一个只读指针，指向a
*p = 30; //合法，可以通过指向修改a的值
p = &a; //非法， 无法修改只读指针的值
```

4.3. 只读指针指向只读变量

const同时修饰指针本身和指针所指向的变量，使得指针本身和所指向的变量都变成只读变量。

因此指针本身不能被修改，也不能通过指针修改所指向的变量

```cpp
const int a = 10;
const int* const p = &a; //声明一个只读指针，指向只读变量a
*p = 20; // 非法
p = nullptr // 非法
```

4.4. 常量引用

常量引用是指引用一个只读变量的引用，因此不能用过常量引用修改变量的值

```cpp
const int a = 10;
const int& b = a; //声明一个常量引用，引用常量a
b = 20; //非法，无法通过常量引用修改常量的 a 的值
```

1. 修饰成员函数

当const 修饰成员函数时，表示该函数不会修改对象的状态(就是不会修改成员变量)

```cpp
class A {
public:
    int func() **const** {
        // 编译错误，不能修改成员变量的值
        m_value = 10;
        return m_value;
    }
private:
    int m_value;
};
```

例子：

```cpp
class MyClass {
public:
    int getValue() const {
        return value;
    }
    
    void setValue(int v) {
        value = v;
    }
    
private:
    int value;
};
```

```cpp
const MyClass constObj;
MyClass nonConstObj;

constObj.getValue();    // 正确：可以在 const 对象上调用 const 成员函数
nonConstObj.getValue(); // 也正确：非 const 对象也可以调用 const 成员函数

// constObj.setValue(10);  // 错误：不能在 const 对象上调用非 const 成员函数
nonConstObj.setValue(10);  // 正确：可以在非 const 对象上调用非 const 成员函数
```

const 对象不能调用非const成员函数，因为可能会修改对象的状态，违反const的承诺

const成员函数，可以被 const 对象调用。

优点：

- 安全性，确保 `const`对象不会被意外修改
- 接口设计：允许创建只读接口，提高代码的可读性和可维护性