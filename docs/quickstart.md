# 从下载到播放：逐步复现与检查点

已于2026-11-03针对首次使用排查。推荐把完整工程解压到可写本地目录，例如C:\FPGA\Alpha；不要从ZIP内部运行，不需要复制开发者用户名、COM7或网卡IPv4。以下是Windows流程；macOS/Linux和其他TD版本没有验证。

## 1. 准备环境

- 安装64位Python3.12，保留Python Launcher和Tcl/Tk组件。`py -3.12 -V`应能显示Python3.12。
- 板上下载需要合法Anlogic TD6.2.1（6.2.168116）及官方USB-JTAG驱动。只有看代码或制作素材时可先不接板。
- MP4转码需要ffmpeg.exe和ffprobe.exe。可放入`host/tools/`（创建该目录），或加入PATH。此目录被Git排除；本库不捆绑FFmpeg和TD安装包。

双击根目录`安装环境.cmd`。**检查点：**看到`PASS runtime dependencies`且无安装失败。缺失依赖时命令行检查会返回非零，不再弹窗卡住；安装失败返回码不再被末尾pause掩盖。

## 2. 恢复本地有权使用的源码依赖

公开Git不包含厂商原始核和Windows字体。取得官方`HX4S20_Contest_202606`资料，然后在仓库根目录运行：

```powershell
& ".\.venv\Scripts\python.exe" scripts/import_dependencies.py --official-root "X:\HX4S20_Contest_202606"
```

**检查点：**49个官方/本机生成输入恢复并通过SHA256。使用锁定的官方版本和Windows字形；字体版本不一致可能拒绝，不能声称所有Windows字体均可生成原bit字节。完整赛事RAR已包含这些输入，不需要此步骤。来源见THIRD_PARTY.md。

## 3. 下载已公开的冻结固件和自有测试镜像

```powershell
& ".\.venv\Scripts\python.exe" scripts/download_release.py --with-demo
& ".\.venv\Scripts\python.exe" scripts/verify_sources.py --require-bits
```

**检查点：**4个bit与可选合成镜像逐一显示SHA256 OK，4个角色/235个原生输入通过校验。脚本只下载和按固定哈希导入，不配置板子、不写TF、不需GitHub CLI登录。

网络受限时，可从[公开Release](https://github.com/beforecell/FPGA-Project/releases/tag/alpha-1.0-artf-diagnostic-20261102)手动下载四个bit，运行`import_firmware.py "X:\downloaded-bits"`；Synthetic_Demo.img放进assets。错误哈希、缺失或本地改过的目标文件不会被悄悄接受/覆盖。

也可自行重建，见下面“重编译”。重新编译与运行公开冻结bit是两条选择，不必为了看演示先重新布局布线。

## 4. 准备自己的视频与图片

双击根目录`启动工作台.vbs`。首次选择本机TD工具路径。先不点击板卡操作即可制作素材：添加视频/图片，最多12项可见媒体；目标25/30FPS，`制作前多少秒=0`表示全部，默认10会截取前10秒；选balanced，然后制作**最终完整Alpha IMG**。

图片任一边超过1920像素，现在会在添加时立即拒绝。可先生成640×480/24bit、等比留边的副本：

```powershell
& ".\.venv\Scripts\python.exe" scripts/prepare_images.py "X:\原图片目录" --output "X:\新的板端图片目录"
```

选择输出BMP，不改原图。原视频无音轨或静音不会被假提示音替代。`_assets/VIDEO01.img`是单视频中间文件，写卡必须选上一级完整资源包。已有同名IMG/缓存目录会在开始编码前提示换名，防止白等和覆盖旧结果。

**检查点：**提示“制作并离线校验”成功，最终IMG被选中；此时仍未写卡。合成演示是几何视频/750Hz测试音/四张图，不是道路实拍，也没有新板测。

## 5. 接线与维护

第一次只接一套板卡/下载器（工具固定cable0）。总电源ON，TF在板槽，USB-JTAG和USB-UART接电脑，网口直连电脑有线网卡，显示器接HDMI_A。只看到USB芯片灯不等于TF已供电。

在工作台选网口→刷新并选择实际有线网卡→进入TF维护模式→连接设备。工具读取现有IPv4并协商板端地址，不修改电脑IP、路由或防火墙；网卡无IPv4/未连接时不能假称可传输。

**检查点：**显示网口、实际TF身份/CID/容量和就绪。维护阶段HDMI黑屏正常。写卡前对本次目标卡、范围和完整SHA再次确认；这是资源包覆盖，不是向FAT文件夹追加。

## 6. 写入、读回、恢复

选择完整IMG→写入并完整读回。总进度按写入+读回计算，写入100%时总进度50%。只有完整比较/读回SHA一致才成功；取消、掉线或错误不算成功，不承诺跨断电续传。

然后选ARTF→加载所选播放器。已固化本板也可以完全断电重开。**检查点：**资源目录就绪、错误0；有UART时软件可读实际状态，没有UART时仅能确认JTAG完成，图像/声音仍应实看。

KEY3/4选择、KEY2打开；普通视频2暂停、3/4短按逐源帧/长按切资源；SW1分析、SW2调速、SW3关键帧、SW4参数。完整规则见controls.md。只有同一视频和同一媒体时钟的不同分析视图，不是PC预制多个处理视频。

## 重编译与注册（需要时再做）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build.ps1 -Project player -TDExe "X:\TD_6.2.1\bin\td_commands_prompt.exe"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build.ps1 -Project tf-maintenance -TDExe "X:\TD_6.2.1\bin\td_commands_prompt.exe"
```

检查新输出的最终路由、setup/hold、资源和bit后，以真实输出目录注册：

```powershell
& ".\.venv\Scripts\python.exe" scripts/register_build.py player "X:\repo\runtime\builds\player_实际时间"
& ".\.venv\Scripts\python.exe" scripts/register_build.py tf-maintenance "X:\repo\runtime\builds\tf-maintenance_实际时间"
```

注册写本地指针，不覆盖冻结输入；新bit标为未独立板测的本地诊断构建。启动/重启工作台使用它。备用串口和ART9回退分别用uart-maintenance/fallback-art9，不要对没有bit的角色宣称已加载。

本次实际重编译了ARTF和NTF1，两者非注释bit载荷都与冻结bit一致，文件SHA因生成日期注释不同而变化。没有因此更换已上板bit，也没有将新文件宣称已重新板测。

## 自检与验证边界

`tests/test_publication.py`检查媒体/GUI/绑定；`tests/test_reproduction.py`检查安装失败返回码、缺目录、注册下载参数、图像边界及实际GUI两视频六图封装。RTL另需Icarus和IVERILOG_BIN。测试不做实体下载/写卡/固化。

本次验证是当前Windows、Python、工具和合法依赖下的独立路径复现，不是每台电脑/每种卡的保证。对接收者的显示、声音、按键、网口实传仍需实板验收；ARTF配置SRAM读回问题及其他限制见limitations.md。

在仓库根目录运行`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test.ps1`可一次完成软件自检，已安装Icarus时加`-RTL`运行RTL回归；不会调用板卡下载器。
