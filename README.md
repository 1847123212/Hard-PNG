Hard-PNG
===========================
基于 FPGA 的流式 PNG 图象解码器



# 特点
* 支持宽度不大于 4000 像素的 PNG 图片，对图片高度没有限制。
* **支持多种颜色类型**: 灰度、灰度+透明、RGB、索引RGB、RGBA。
* 仅支持 8bit 深度 (大多数 PNG 图片都是 8bit 深度)。
* 流式输入、流式输出。
* 完全使用 SystemVerilog 实现，方便移植和仿真。

| ![框图](https://github.com/WangXuan95/Hard-PNG/blob/master/images/blockdiagram.png) |
| :----: |
| **图1** : Hard-PNG 原理框图 |



# 模块接口和时序

RTL 代码全在 [**png_decoder.sv**](https://github.com/WangXuan95/Hard-PNG/blob/master/png_decoder.sv) 中。其中 **png_decoder** 是顶层模块，它的接口框图如 **图2**

| ![接口图](https://github.com/WangXuan95/Hard-PNG/blob/master/images/interface.png) |
| :----: |
| **图2** : **png_decoder** 接口图 |

它的使用方法很简单，首先需要给 **clk** 信号提供时钟(频率不限)，并将 **rst** 信号置低，代表不复位。
然后将一个完整的 **.png** 文件的内容从 **"PNG文件码流输入接口"** 输入，就可以从 **"图象基本信息输出接口"** 和 **"像素输出接口"** 中得到输出结果。

以我们提供的图片文件 [**test1.png**](https://github.com/WangXuan95/Hard-PNG/blob/master/images/test1.png) 为例。使用 [**WinHex软件**](http://www.x-ways.net/winhex/) 打开 [**test1.png**](https://github.com/WangXuan95/Hard-PNG/blob/master/images/test1.png) ，发现它包含98个字节：
```
0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 
0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x02, 0x08, 0x06, 0x00, 0x00, 0x00, 0x7F, 0xA8, 0x7D, 
0x63, 0x00, 0x00, 0x00, 0x29, 0x49, 0x44, 0x41, 0x54, 0x18, 0x57, 0x63, 0xF8, 0xFF, 0x89, 0xE1, 
0xFF, 0x5B, 0x19, 0x95, 0xFF, 0x0C, 0x0C, 0x0C, 0xFF, 0xED, 0x3D, 0xCE, 0xFC, 0x67, 0x6A, 0xE8, 
0xAD, 0x07, 0xB2, 0x81, 0xBC, 0xFF, 0xFF, 0x19, 0x0E, 0xA4, 0xFD, 0x65, 0x00, 0x00, 0x0D, 0x02, 
0x0F, 0x1C, 0x6B, 0x78, 0x3E, 0xC1, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 
0x60, 0x82
```
该图象颜色类型为RGB，解压后只有4x2=8个像素，16进制表示如下表 (RGB图象完全不透明，因此A通道固定0xFF)：

|           | col 1 | col 2 | col 3 | col 4 |
| :---:     | :---: | :---: | :---: | :---: |
| **row 1** | R:FF G:F2 B:00 A:FF | R:ED G:1C B:24 A:FF | R:00 G:00 B:00 A:FF | R:3F G:48 B:CC A:FF |
| **row 2** | R:7F G:7F B:7F A:FF | R:ED G:1C B:24 A:FF | R:G:FF B:FF A:FF | R:FF G:AE B:CC A:FF |

为了用 **png_decoder** 解压 **test1.png** ，我们应该以 **图3** 的时序把原始的98个字节输入 **"PNG文件码流输入接口"** 。
这是一个类似 **AXI-stream** 的接口，其中 **ivalid=1** 时说明外部想发送一个字节给 **png_decoder**。**iready=1** 时说明 **png_decoder** 已经准备好接收一个字节。只有 **ivalid** 和 **iready** 同时 **=1** 时，**ibyte** 才被成功的输入 **png_decoder** 中。

| ![输入时序图](https://github.com/WangXuan95/Hard-PNG/blob/master/images/wave1.png) |
| :----: |
| **图3** : **png_decoder** 输入时序图，以 **test1.png** 为例 |

在输入的同时，解码结果从模块中输出，如 **图4** 。**newframe**信号出现一个时钟周期的高电平脉冲代表新的一帧图象，同时 **colortype, width, height** 合法直到所有像素输出完为止。其中 **width, height** 分别为图象的宽度和高度， **colortype** 的含义如下表：

| colortype | 2'd0 | 2'd1 | 2'd2 | 2'd3 |
| :-------: | :--: | :--: | :--: | :--: |
| **颜色类型** | 灰度图 | 灰度+透明 | RGB / 索引RGB | RGBA |
| **含义** | RGB通道相等, A通道=0xFF | RGB通道相等 | RGB通道不等, A通道=0xFF | RGBA通道均不等 |

而 **ovalid=1** 代表该时钟周期有一个像素输出，该像素的R,G,B,A通道分别出现在 **opixelr,opixelg,opixelb,opixela** 信号上。

| ![输出时序图](https://github.com/WangXuan95/Hard-PNG/blob/master/images/wave2.png) |
| :----: |
| **图4** : **png_decoder** 输出时序图，以 **test1.png** 为例 |

当一个图象完全输入结束后，我们可以紧接着输入下一个图象进行解码。如果一个图象输入了一半，我们想打断这个解码进程并输入下一个图象，则需要先将 **rst** 信号拉高至少一个时钟周期进行复位。


# RTL 仿真

### 运行仿真

[**tb_png_decoder.sv**](https://github.com/WangXuan95/Hard-PNG/blob/master/tb_png_decoder.sv) 是仿真的顶层，它从指定的 **.png** 文件中读取所有字节输入 [**png_decoder**](https://github.com/WangXuan95/Hard-PNG/blob/master/png_decoder.sv) 中，再从中接收解码结果（原始像素）并写入一个 **.txt** 文件。

仿真前，请将 [**tb_png_decoder.sv**](https://github.com/WangXuan95/Hard-PNG/blob/master/tb_png_decoder.sv) 中的 **PNG_FILE** 宏名改为 **.png** 文件的地址，将 **OUT_FILE** 宏名改为要输出的 **.txt** 文件的地址。然后运行仿真。仿真的时间取决于 **.png** 文件的大小，当 **ivalid** 信号由高变低时，仿真完成。然后你可以从 **.txt** 文件中查看解码结果。

我们在 [**images文件夹**](https://github.com/WangXuan95/Hard-PNG/blob/master/images) 中提供了 13 个 **.png** 文件，它们尺寸各异，且有灰度、RGB、RGBA、索引RGB等不同的颜色类型，你可以用它们进行仿真。

以 [**test3.png**](https://github.com/WangXuan95/Hard-PNG/blob/master/images/test3.png) 为例，我们得到的 **.txt** 文件如下：
```
frame  type:2  width:83  height:74 
f4d8c3ff f4d8c3ff f4d8c3ff f4d8c3ff f4d8c3ff f4d9c3ff ... 
```
这代表图片的尺寸是83x74，颜色类型是2(RGB)，第1行第1列的像素是RGBA=(0xf4, 0xd8, 0xc3, 0xff)，第1行第2列的像素是RGBA=(0xf4, 0xd8, 0xc3, 0xff)，......

### 正确性验证

为了验证解码结果是否正确，我们编写了 Python 程序 [**validation.py**](https://github.com/WangXuan95/Hard-PNG/blob/master/validation.py) ，它对 **.png** 文件进行软件解码，并与 RTL 仿真得到的 **.txt** 文件进行比较，若比较结果相同则验证通过。为了准备必要的运行环境，请安装 Python3 以及其配套的 [**numpy**](https://pypi.org/project/numpy/) 和 [**PIL**](https://pypi.org/project/Pillow/) 库。运行环境准备好后，打开 [**validation.py**](https://github.com/WangXuan95/Hard-PNG/blob/master/validation.py) ，将变量 **PNG_FILE** 改为要验证的 **.png** 文件的路径，将 **TXT_FILE** 改为 RTL 仿真输出的 **.txt** 文件的路径，然后用命令运行它：
```
python validation.py
```
若比较结果相同，则打印 **validation successful!!**

# 性能测试

* **测试平台**: **Hard-PNG** 运行 RTL 仿真，时钟频率 100MHz
* **对比平台**: Intel Core I7 8750H 运行 [**upng**](https://github.com/elanthis/upng) 库（MSVC++ 编译器 17.00.50727  -O3优化）

测试结果如下表，Hard-PNG的解码的性能略低于8750H。可以估计，Hard-PNG 的性能好于单片机和大部分ARM嵌入式处理器

| **图片文件名** | **图片类型** | **图片大小** | **Hard-PNG耗时** | **对比平台耗时** | **Hard-PNG吞吐率** |
| :-----:        | :----------: | :--------:   | :-------------:  | :--------:   | :--------:   |
| test9.png      | RGB          | 631x742      | 110 ms           | 75 ms        | 4.26 Mpixel/s |
| test10.png     | RGB(索引RGB)  | 631x742      | 25 ms            | 不支持       | 18.73 Mpixel/s |
| test11.png     | RGBA         | 1920x1080    | 527 ms           | 348 ms       | 3.93 Mpixel/s |
| test12.png     | RGB(索引RGB)  | 1920x1080    | 105 ms           | 不支持       | 19.75 Mpixel/s |



# FPGA 资源消耗

下表是 **png_decoder** 模块综合后占用的 FPGA 资源量

| **FPGA 厂商** | **FPGA 型号** |   逻辑消耗       | BRAM消耗               |
| :-----:       | :-----------: | :-----------:    | :-------------:        |
| Altera        | Cyclone IV    | 36.5kLE          | 401kbit                |
| Xilinx        | Artix-7       | 17.4kLUT, 9.6kFF | 792kbit (22个36kb BRAM) |



# 参考链接

我们感谢以下链接为我们提供参考：

* [**upng**](https://github.com/elanthis/upng): 一个轻量化的 C 语言 png 解码库
* [**TinyPNG**](https://tinypng.com/): 一个利用索引RGB原理对 png 图片进行压缩的工具
* [**PNG Specification**](https://www.w3.org/TR/REC-png.pdf): png 标准手册
