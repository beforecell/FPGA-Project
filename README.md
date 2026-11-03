# HX4S20C Alpha 1.0：多媒体回放与FPGA实时分析

基于康芯HX4S20C/安路EG4S20BG256的TF多媒体播放器：板端视频、BMP图片和PCM原声播放，四格/放大视图、实时帧差、最多四个运动区域框、5.46秒音频波形与能量、逐源帧定位、时间带与四个关键帧书签。Windows工作台负责素材转码、网口板载TF读写及固件加载。

**当前版本为ARTF诊断候选，不是全部验证/功能验收通过的稳定版。** 已有原生正时序、UART控制和Flash固化/断电自启遥测；配置SRAM读回一致性仍待核实。旧版人工画面、声音和30分钟记录没有转移为本版验收。

## 页面名称与下载选择

| 页面中的名称 | 中文含义 | 应该怎样选择 |
|---|---|---|
| `main` | **当前主分支：最新源码与说明** | 日常查看、克隆或下载源码使用这里；它会继续更新 |
| `alpha-1.0-artf-repro-fix-20261103` | **2026-11-03 复现修正版源码快照（推荐）** | 想取得固定、不会继续变化的本次修复源码，选这个标签 |
| `alpha-1.0-artf-diagnostic-20261102` | **2026-11-02 历史原版快照与固件附件** | 下载四份冻结bit和合成IMG；其自动Source code不包含11月3日的复现修复 |

上述两个是**版本标签（Tags）**，不是Issue，也不是两个新工程或两个分支。`main`是唯一默认主分支。为兼容已有下载脚本和链接，英文标签标识保持不变；Release页面使用清晰的中文名称。

**取源码：**[当前main](https://github.com/beforecell/FPGA-Project/tree/main)或[推荐固定版本](https://github.com/beforecell/FPGA-Project/releases/tag/alpha-1.0-artf-repro-fix-20261103)。**取bit/演示IMG：**[历史固件附件](https://github.com/beforecell/FPGA-Project/releases/tag/alpha-1.0-artf-diagnostic-20261102)，也可按快速开始运行固定SHA下载脚本。两次发布的冻结播放器固件没有变，均保留ARTF诊断候选说明。

## 获取与复现

1. Windows64位、Python3.12、合法TD6.2.1（6.2.168116）及JTAG驱动；制作MP4另装FFmpeg/ffprobe。
2. 下载/克隆本仓库并保留结构，双击根目录`安装环境.cmd`。
3. 根据[第三方依赖说明](THIRD_PARTY.md)，取得有权使用的官方竞赛资料。在仓库根目录运行：

```powershell
& ".\.venv\Scripts\python.exe" scripts/import_dependencies.py --official-root "X:\HX4S20_Contest_202606"
& ".\.venv\Scripts\python.exe" scripts/verify_sources.py
```

4. 推荐先运行`.venv\Scripts\python.exe scripts/download_release.py --with-demo`，按固定SHA下载四份冻结bit与合成演示，再运行`.venv\Scripts\python.exe scripts/verify_sources.py --require-bits`。如需重建，用Build.ps1和register_build.py，详见[完整快速开始](docs/quickstart.md)；本机新bit不自动继承原bit实板结论。
5. 双击根目录`启动工作台.vbs`。已有兼容TF时加载播放器即可；更换素材按[网口写卡流程](docs/network-tf-workflow.md)操作。

**源码仓库与[候选Release](https://github.com/beforecell/FPGA-Project/releases/tag/alpha-1.0-artf-diagnostic-20261102)均公开。** Release提供4个实际bit、合成测试镜像、固件清单和完整SHA256；无需登录即可下载。厂商原始HDL、Windows字体文件、私人视频/原声和卡备份仍不上传。49项源码依赖可由合法官方资料/本机字体恢复，逐文件SHA必须匹配；已在本机独立目录验证完整235项构建输入。固件公开不代表第三方IP、字体或素材获得额外MIT授权，也不代表ARTF诊断问题已解决。相同字体版本/渲染若不匹配，恢复器会拒绝，不能假称得到原固件。

## 工程结构

```text
fpga/player/            ARTF冻结输入、TD工程、约束和原生报告
fpga/tf-maintenance/    NTF1网口TF维护
fpga/uart-maintenance/  备用低速串口维护
fpga/fallback-art9/     必要回退源码；缺少新版时间带/关键帧
host/                  统一工作台、编码器、PCM与传输后端
scripts/               安装、依赖恢复、构建/注册、校验、厂商BW固化说明入口
tests/                 软件/RTL测试和确定性合成输入
dependencies/          官方来源、有限适配、字体生成配方及精确哈希
verification/          版本绑定、脱敏证据和本轮发布检查
docs/                  接线、操作、架构、格式、验证和限制
assets/                自有合成素材生成说明；不放真实道路视频
```

## 版本与证据

| 角色 | bit SHA256前缀 | 原生setup/hold | 范围 |
|---|---|---|---|
| ARTF | `3FBD9229E297` | +1.265 / +0.035ns | 三源帧间隔差分；实际BW写Flash+verify_spi；用户断电后15个有效UART包、目录就绪/错误0 |
| NTF1 | `106575929DCB` | +0.752 / +0.024ns | 历史32,026,624字节网口写入+完整读回96.609秒、29重传、SHA一致 |
| ART9回退 | `F2EADA95F3D6` | 见对应manifest | 历史按键/波形/声音证据；不含时间带/关键帧 |
| UART备用 | `EE8B3EC55893` | 见对应manifest | 串口维护，速度受链路限制 |

完整SHA与235项输入绑定在[verification/versions.json](verification/versions.json)及各工程build_manifest中。已有记录与本轮新测试区分见[验证说明](docs/validation.md)，所有缺口见[限制](docs/limitations.md)。

播放器比较`abs(Y(t)-Y(max(0,t-3)))`并去噪提取内轮廓，不是三帧AND或插帧；30FPS时比较跨度100ms。目标页为运动区域框，不做车辆/行人语义分类。音频页为时间波形与均方能量，本版没有启用FFT。

## 两种存储与两套固件

- `.bit`决定电路；TF `.img`保存源视频编码数据、图片和PCM。PC不预生成帧差、目标框或波形结果。
- SRAM临时下载断电丢失。启动Flash固化和TF素材断电保留；书签断电清空。
- 网口维护与播放器先后占用同一FPGA。维护期间没有HDMI；写卡后重新加载播放器或完全断电重开固化版本。
- 已完成固化的板子日常只需独立电源、HDMI_A和TF。换素材只写TF，不重复固化。

## 许可与分发

保留仓库初始MIT文本；它不覆盖第三方权利、官方IP、Windows字体或不随库发布的素材/固件。归属与范围见[LICENSE_SCOPE.md](LICENSE_SCOPE.md)和[THIRD_PARTY.md](THIRD_PARTY.md)。不要把本库描述成所有软硬件和素材均已取得公开再分发许可。

## 复现流程修复（2026-11-03）

已增加[逐步检查点](docs/quickstart.md)和[排查记录](docs/reproduction-debug.md)。支持`download_release.py --with-demo`按固定SHA自动下载公开固件/合成镜像；超大图片可用prepare_images.py制作副本。修复安装错误返回码、缺工程目录误报通过、注册后网口下载参数、通道/素材误导提示与CLI检查弹窗。原生ARTF/NTF1在独立中文空格路径重编译通过，冻结HDL和发布bit保持不变。
