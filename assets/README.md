# 测试素材

不上传私人MP4、真实道路/原声、原TF备份或未核实授权的图片/TTS。可运行scripts/make_synthetic_demo.py生成1秒几何运动+750Hz测试音、4张640×480/24-bit自有几何图片，封装为Synthetic_Demo.img。仅源数据，不含分析结果；它不是历史实板道路镜像，也没有新的板上验收。

生成命令：`.venv\Scripts\python.exe scripts/make_synthetic_demo.py`。IMG及中间文件被.gitignore排除。GUI“加载自有演示镜像”指向这个生成结果。
