import runtime_tools
"""Video metadata and deterministic letterboxed board-frame production."""
from pathlib import Path
import cv2,numpy as np,subprocess,json,shutil,threading,tempfile,math
WIDTH,HEIGHT=640,480
def estimated_output_frames(info,target_fps,frame_limit):
 """Progress estimate only: never use metadata to shorten the decode iterator."""
 try:duration=float(info['duration_s'])
 except (KeyError,TypeError,ValueError):return None
 if not math.isfinite(duration) or duration<=0:return None
 return min(frame_limit,max(1,math.ceil(duration*target_fps-1e-6)))

def metadata(path):
 path=Path(path)
 cap=cv2.VideoCapture(str(path))
 if not cap.isOpened():raise ValueError('无法解码这个视频，请检查文件是否损坏或编码是否受支持')
 fps=float(cap.get(cv2.CAP_PROP_FPS));frames=int(cap.get(cv2.CAP_PROP_FRAME_COUNT));w=int(cap.get(3));h=int(cap.get(4));cap.release()
 if not np.isfinite(fps) or fps<=0 or frames<=0 or w<=0 or h<=0:raise ValueError('视频帧率、尺寸或时长信息无效')
 result=dict(path=str(path.absolute()),container=path.suffix.lstrip('.').upper(),width=w,height=h,source_fps=fps,
             frames=frames,duration_s=frames/fps,codec='由本机视频解码器识别',target_fps=min(30,max(1,round(fps))),fit='等比完整显示，空余区域留黑边')
 probe=runtime_tools.find('ffprobe')
 if probe:
  p=subprocess.run([probe,'-v','error','-select_streams','v:0','-show_entries','stream=codec_name,pix_fmt,color_space,avg_frame_rate,sample_aspect_ratio:format=duration,format_name','-of','json',str(path)],capture_output=True,text=True,creationflags=0x08000000)
  if p.returncode==0:
   raw=json.loads(p.stdout);stream=raw.get('streams',[{}])[0];result['codec']=stream.get('codec_name',result['codec']);result['ffprobe']=raw
   try:
    a,b=map(int,stream.get('sample_aspect_ratio','1:1').split(':'));result['pixel_aspect']=a/b if b else 1
   except (ValueError,ZeroDivisionError):result['pixel_aspect']=1
 dar=w*result.get('pixel_aspect',1)/h
 dw,dh=(640,round(640/dar)) if dar>=640/480 else (round(480*dar),480)
 result['active_rect']=[(640-dw)//2,(480-dh)//2,dw,dh]
 return result

def fit_rgb(bgr,pixel_aspect=1):
 h,w=bgr.shape[:2];factor=min(640/(w*pixel_aspect),480/h)
 dw=max(1,min(640,round(w*pixel_aspect*factor)));dh=max(1,min(480,round(h*factor)))
 resized=cv2.resize(bgr,(dw,dh),interpolation=cv2.INTER_AREA if factor<=1 else cv2.INTER_LINEAR)
 out=np.zeros((480,640,3),np.uint8);x=(640-dw)//2;y=(480-dh)//2;out[y:y+dh,x:x+dw]=cv2.cvtColor(resized,cv2.COLOR_BGR2RGB)
 return out

def frames(path,target_fps=30,max_frames=65535,cancel=None):
 ffmpeg=runtime_tools.find('ffmpeg')
 if ffmpeg:
  # FFmpeg schedules VFR by presentation timestamps, unlike assuming every
  # input-frame index is exactly1/average_fps seconds apart.
  error_file=tempfile.TemporaryFile()
  vf=f"fps={target_fps},scale=w='min(640,480*dar)':h='min(480,640/dar)':flags=area,setsar=1,pad=640:480:(ow-iw)/2:(oh-ih)/2,format=rgb24"
  process=subprocess.Popen([ffmpeg,'-nostdin','-v','error','-i',str(path),'-an','-sn','-vf',vf,'-frames:v',str(max_frames),'-f','rawvideo','pipe:1'],stdout=subprocess.PIPE,stderr=error_file,creationflags=0x08000000)
  stop=threading.Event()
  def watch():
   while not stop.wait(.1):
    if cancel and cancel.is_set():process.terminate();return
  threading.Thread(target=watch,daemon=True).start()
  try:
   while True:
    if cancel and cancel.is_set():raise InterruptedError('已取消视频制作')
    data=process.stdout.read(640*480*3)
    if not data:break
    if len(data)!=640*480*3:raise ValueError('视频解码未输出完整帧')
    yield np.frombuffer(data,np.uint8).reshape(480,640,3).copy()
   code=process.wait()
   if cancel and cancel.is_set():raise InterruptedError('已取消视频制作')
   if code:
    error_file.seek(0);raise ValueError('视频解码失败：'+error_file.read().decode('utf-8','replace')[-700:])
  finally:
   stop.set()
   if process.poll() is None:process.terminate();process.wait(timeout=5)
   process.stdout.close();error_file.close()
  return
 info=metadata(path);source_fps=info['source_fps'];cap=cv2.VideoCapture(str(path))
 output_index=0;input_index=0;next_time=0
 try:
  while output_index<max_frames:
   if cancel and cancel.is_set():raise InterruptedError('已取消视频制作')
   ok,bgr=cap.read()
   if not ok:break
   time=input_index/source_fps
   while time+1e-9>=next_time and output_index<max_frames:
    yield fit_rgb(bgr);output_index+=1;next_time=output_index/target_fps
   input_index+=1
 finally:cap.release()

def posters(path):
 info=metadata(path);cap=cv2.VideoCapture(str(path));items=[]
 try:
  for fraction in (0,.33,.66,.95):
   cap.set(cv2.CAP_PROP_POS_FRAMES,int((info['frames']-1)*fraction));ok,bgr=cap.read()
   if not ok:raise ValueError('无法读取相册预览图')
   items.append(fit_rgb(bgr,info.get('pixel_aspect',1)))
 finally:cap.release()
 return items
