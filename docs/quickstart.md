# 从克隆到播放

Windows64位、64位Python3.12及Launcher、合法Anlogic TD6.2.1（6.2.168116）和下载器驱动。安装环境.cmd只创建本仓库.venv并安装host/requirements-network.txt，不碰原工程或板子。MP4转换需另装ffmpeg/ffprobe加入PATH或host/tools。

先执行README中的依赖恢复与verify_sources。然后选择两种合法固件来源之一：

1. 有权使用的冻结bit：`python scripts/import_firmware.py "X:\authorized-bits"`按SHA放回4个工程。管理者的候选Release是草稿，普通访客不能下载；不要假称公开仓库带现成bit。
2. 自行重建：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build.ps1 -Project player -TDExe "X:\TD_6.2.1\bin\td_commands_prompt.exe"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build.ps1 -Project tf-maintenance -TDExe "X:\TD_6.2.1\bin\td_commands_prompt.exe"
```

需要串口备用或ART9回退时再以对应Project重建。构建复制到runtime/builds，原冻结输入不会覆盖。检查新生成的verification/时序、资源及bit SHA；正时序后运行：

```powershell
& ".\.venv\Scripts\python.exe" scripts/register_build.py player "X:\repo\runtime\builds\player_实际时间"
& ".\.venv\Scripts\python.exe" scripts/register_build.py tf-maintenance "X:\repo\runtime\builds\tf-maintenance_实际时间"
```

注册只接收与冻结输入完全一致的本机构建，保存到runtime/firmware并更新本地指针，不改Git冻结manifest。新的布局/bit即使同源，也按待实板验证的本地诊断构建处理。重启GUI后使用本地注册路径。

按接线文档接好板子，双击启动工作台.vbs。首次在TD工具路径选择自己的td_commands_prompt.exe。已有兼容TF时点击加载所选播放器；需要换素材先制作完整Alpha IMG，进入TF维护、连接、写入并读回，最后加载播放器。硬件下载和实体覆盖只有明确点击及确认后才发生。

只编译了player、没有回退bit时，不要点击ART9回退；缺少固件会明确报错，不会猜另一个旧目录。完整可复现集合需分别构建或导入四角色。
