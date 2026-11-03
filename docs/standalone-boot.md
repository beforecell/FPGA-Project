# 固化与独立启动

SRAM下载使用td_commands_prompt.exe；启动Flash的program_spi使用同一TD安装目录中的**bw_commands_prompt.exe**。实际成功命令参数为：

```tcl
download -mode program_spi -bit X:/path/ARTF.bit -chip EG4S20BG256 -flashsize 16 -cable 0 -spd 6 -v
```

flashsize16表示16Mbit/2MiB。**不要添加SRAM入口的-error_max参数**，BW的program_spi不接受它。不要沿用已停用的旧图形固化程序。

scripts/solidify_flash.py默认只打印目标和命令，不调用设备：

```powershell
& ".\.venv\Scripts\python.exe" scripts/solidify_flash.py --bw "X:\TD_6.2.1\bin\bw_commands_prompt.exe"
```

确认对应HX4S20C、实际Flash容量、正确bit和当前启动内容备份之后，只有显式追加--execute并输入FLASH ARTF才实际覆盖启动Flash。本轮发布整理只测试dry-run/日志判断，没有执行--execute或烧板。

program_spi后须出现verify_spi和完整内部比较完成，无错误且退出码正确才能说Flash工具校验通过。它与FPGA配置SRAM读回检查不同。原始BIN不能当普通bit还原，历史备份不等于当前内容新备份。

固化后的真实检查：完全断电、排除USB供电、灯全灭5秒后重上电，不再下载；核对ARTF身份/目录，再人工检查HDMI、声音和按键。已有历史记录证明本板ARTF Flash校验和用户断电后的UART自启，不扩大为新电脑或全部功能验收。

日常独立电源+HDMI_A+TF即可用，开机仍进入资源选择，不自动播放第一条。更换视频只更新TF，维护阶段临时电路不改固化Flash；更新后重新加载播放器或断电重开。书签断电清空，素材保留。
