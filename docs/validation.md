# 验证范围

## 已有冻结证据

ARTF原生TD6.2.1 setup+1.265ns/hold+0.035ns；17,941 LUT、12,955寄存器、56 ERAM9K、15 RAM32K、21 DSP、2 PLL。原生最终只读路由/时钟/时序复核未改bit或数据库。完整输入哈希未因Git整理而更改。

ARTF已有UART前后逐源帧及PCM位置、视图切换和60.031秒118包运行记录；77指采样中见到的不同帧号，不是总播放帧数。错误0、欠载0；不是30分钟、HDMI采集或物理按键新验收。

随后厂商BW实际写启动Flash约230秒，verify_spi通过。用户报告所有灯熄灭5秒后重开，不再下载；只读UART15包识别ARTF、目录就绪、错误0。没有重新听测/实看；配置SRAM读回一致性仍待核实。

帧差旧ARTD首次目测更清楚后被用户补充频闪，不作为最终通过。三帧间隔的89组夜间参考按RGB565输入，全屏轮廓面积比<0.1的跳变32→0，四格38→1；这是特定素材离线指标，不是物体准确率或显示器频闪仪测量。

NTF1历史完整32,026,624字节网口写/读回、SHA相同及声音/两图片切换实看；本轮没有重新写卡。ART9、基础版历史证据不能移植给ARTF。

## 本轮仓库验证

本轮执行项与结果记录在verification/publication-checks.json。软件、确定性RTL和依赖恢复按具体命令分别记录；使用自有合成输入和脱敏网络夹具，不能冒充原道路测试。冷启动/写卡证据为脱敏历史副本，原始记录留在本地。

原HDL/约束/build.tcl输入保持字节一致，2026-11-03复现修复轮次另在干净中文/空格路径真实重编译了ARTF和NTF1；详情见reproduction-debug.md。本轮没有下载FPGA、写TF/Flash或改网络配置。包装脚本及host路径适配有独立测试，不沿用旧bit结论证明新主机界面无误。

可运行tests/test_publication.py、test_manager.py、test_network_software.py、test_network_bridge.py、test_difference_rtl.py、test_historical_unit.py。Icarus的IVERILOG_BIN指向本机bin目录；测试模型不代表SD物理时序或HDMI物理链路。
