"""Check the selected interpreter before opening the single GUI entry point."""
from pathlib import Path
import sys,runpy,importlib

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
def main():
    missing=[]
    for name in ['numpy','cv2','PIL','serial']:
        try:importlib.import_module(name)
        except ImportError:missing.append(name)
    if sys.version_info<(3,12):missing.append('Python3.12 or newer')
    if missing:
        import tkinter as tk
        from tkinter import messagebox
        root=tk.Tk();root.withdraw()
        exe=Path(sys.executable).with_name('python.exe')
        messagebox.showerror('Alpha运行环境',
            '当前Python缺少依赖或版本过旧：'+', '.join(missing)+'\n\n解释器：'+str(sys.executable)+
            '\n请按网口复现说明安装Python3.12及依赖。安装命令：\n"'+str(exe)+'" -m pip install -r "'+str(HERE/'requirements-network.txt')+'"')
        root.destroy();return 1
    if '--check' in sys.argv:
        print('PASS runtime dependencies',sys.executable);return 0
    runpy.run_path(str(HERE/'alpha_studio.py'),run_name='__main__')
    return 0
if __name__=='__main__':sys.exit(main())
