# 第三方来源与依赖恢复

本库按最小分发原则排除全部`user_source/hdl_source`与`vendor/anlogic`官方内容。锁定文件为dependencies/official-inputs.json，共45项（包含回退工程的重复依赖）。每项列出官方根目录下的准确相对路径、ZIP成员或原始文件SHA、少量本地适配及最终冻结SHA。依赖恢复器不联网、不下载未知镜像，不读写板子。

取得官方康芯HX4S20C竞赛资料`HX4S20_Contest_202606`，版本包括TD6.2.1示例与7_lab_ex_2026_nosoft。主要来源为`2_Example/DEMO_TD版本6.2.1.zip`（完整归档SHA见锁定文件）、其中33号以太网实验，以及7_lab_ex的lab_ex4_tf/lab_ex5_i2s。部分IP也在6_EG4S20数据手册中的厂商参考设计归档。应从赛事方/康芯/安路正式渠道取得授权资料；本库不提供未经核实的公开下载链接。

```powershell
& ".\.venv\Scripts\python.exe" scripts/import_dependencies.py --official-root "X:\HX4S20_Contest_202606"
```

原文件哈希不符会停止；不会换一个“相似版本”充数。本地适配只恢复已冻结的复位、端口顺序、时钟参数和计数修正，不能据此把整个官方文件宣称为自研。

另有4个中文标签生成文件：两播放器各自alpha_views.v和alpha_labels.vh。Git中仅保留无位图模板与生成配方；本地Pillow13.0.0使用Windows的msyh.ttc、simsun.ttc生成。锁中给出已验证字体哈希和字号/坐标。字体版本不同可能不能还原相同像素，恢复器会按目标文件SHA拒绝，而非悄悄改变源码。字体文件不分发。

恢复后的235个输入必须通过scripts/verify_sources.py。已在当前Windows、官方资料和字体环境实际恢复并核对；没有声称第二台电脑已验证。

R2FFT来自yoonisi/R2FFT，保留BSD-3-Clause。其历史Verilog2001文件为冻结构建输入，本版FFT没有运行实例。Python/NumPy/OpenCV/Pillow/pyserial通过版本清单安装；TD、驱动、FFmpeg不分发。合成几何/正弦测试内容由脚本现场生成，无真实道路或私人声音。
