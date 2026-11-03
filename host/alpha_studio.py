"""Single entry point. Operations remain in tested transport/backend modules."""
from pathlib import Path
import tkinter as tk
from tkinter import ttk,filedialog,messagebox
import json,tempfile,sys,wave,datetime,threading,queue
from PIL import Image,ImageTk
import tf_gui as base,alpha_package as package,device_tools,network_transport,project_paths

ROOT=Path(__file__).resolve().parent.parent
ART9_RELATIVE=project_paths.relative('fallback-art9')
DIFFERENCE_INDEX='verification/player.json'

def playback_policy(pointer,native):
 """A diagnostic label never permits negative timing or a stale bit hash."""
 if native['setup_ns']<0 or native['hold_ns']<0 or pointer['bit_sha256'].upper()!=native['bit_sha256'].upper():
  raise RuntimeError('所选播放程序的哈希或时序不合格')
 diagnostic=pointer.get('diagnostic_only',False)
 known_diagnostic=bool(pointer.get('local_build')) or (pointer.get('runtime_tag')=='ARTK' and pointer.get('configuration_status')=='UNRESOLVED_READBACK_DIFFERENCE') or (pointer.get('runtime_tag') in ('ARTD','ARTF') and pointer.get('configuration_status')=='INHERITED_READBACK_ISSUE_NOT_RETESTED')
 if diagnostic and not known_diagnostic:
  raise RuntimeError('诊断候选的状态声明不完整，未开始下载')
 return dict(diagnostic=diagnostic,verify_configuration=not diagnostic and pointer.get('uart_controls') is not False,expected_runtime=pointer.get('runtime_tag'))

class AlphaApp(base.App):
 def __init__(self,root):
  super().__init__(root);root.geometry(f'{min(1180,root.winfo_screenwidth()-100)}x{min(900,root.winfo_screenheight()-100)}');root.minsize(800,600)
  difference_available=(ROOT/DIFFERENCE_INDEX).exists()
  player_versions=(['ARTF 帧差去闪诊断版'] if difference_available else [])+['ART9 回退版']
  self.playback_variant=tk.StringVar(value=player_versions[0])
  for widget in self.widgets:
   if isinstance(widget,ttk.Button) and widget.cget('text') in ('下载播放程序','恢复播放'):
    if widget.cget('text')=='下载播放程序':
     self.load_player_button=widget;widget.configure(text='加载所选播放器',command=self.restore_selected)
    else:widget.configure(text='恢复 ART9 播放')
  versions=ttk.Combobox(self.output_combo.master,textvariable=self.playback_variant,values=player_versions,state='readonly',width=19)
  versions.pack(side='left',before=self.load_player_button,padx=5);self.widgets.append(versions)
  self.validation.set(('ARTF采用三源帧差分与内轮廓，保留时间带/关键帧；' if difference_available else '')+'写卡结束后请点“加载所选播放器”恢复HDMI。ARTF仍为诊断候选（配置SRAM读回一致性待查），ART9为回退版。')
  for w in self.canvas_frame.winfo_children():
   if isinstance(w,ttk.Label) and w.cget('text').startswith('USB-JTAG 下载固件'):
    w.configure(text='USB-JTAG加载固件；网口或USB-UART按所选方式传镜像；写卡完成后恢复播放器。')
  self.transport=tk.StringVar(value='网口');self.network_choice=tk.StringVar();self.network_adapters=[];self.network_results=queue.SimpleQueue()
  row=ttk.Frame(self.combo.master.master);row.pack(fill='x',pady=4)
  ttk.Label(row,text='TF数据通道').pack(side='left')
  mode=ttk.Combobox(row,textvariable=self.transport,values=['网口','串口'],state='readonly',width=7);mode.pack(side='left',padx=5);self.widgets.append(mode)
  mode.bind('<<ComboboxSelected>>',self.transport_changed)
  self.network_combo=ttk.Combobox(row,textvariable=self.network_choice,state='readonly',width=44);self.network_combo.pack(side='left',padx=5);self.widgets.append(self.network_combo)
  self.button(row,'刷新有线网卡',self.refresh_network)
  self.button(row,'TD工具路径',self.choose_td)
  self.connection.set('当前选择网口；先刷新有线网卡、加载网络维护程序，再连接设备。电脑IPv4配置不会被修改。')
  # Progress stays above the tabs,visible during both encoding and transfer.
  self.bar.master.pack_configure(before=self.book)
  self.assets=[];self.preview_photo=None
  self.book.forget(2)
  page=ttk.Frame(self.book,padding=12);self.book.insert(0,page,text='1  素材与预演');self.book.select(page)
  row=ttk.Frame(page);row.pack(fill='x')
  self.button(row,'添加视频 / 旧配套IMG',self.add_video_asset)
  self.button(row,'添加图片',self.add_image_asset)
  self.button(row,'移除选中素材',self.remove_asset)
  self.button(row,'制作 Alpha 资源镜像',self.make_package)
  self.button(row,'加载自有演示镜像',self.select_demo)
  # Historical private-media button omitted from the public distribution.
  body=ttk.Frame(page);body.pack(fill='both',expand=True,pady=8)
  self.asset_tree=ttk.Treeview(body,columns=('kind','size','source'),show='tree headings',height=7)
  self.asset_tree.heading('#0',text='名称');self.asset_tree.heading('kind',text='类型');self.asset_tree.heading('size',text='尺寸 / 时长');self.asset_tree.heading('source',text='来源')
  self.asset_tree.column('#0',width=160);self.asset_tree.column('kind',width=80);self.asset_tree.column('size',width=160);self.asset_tree.column('source',width=340)
  self.asset_tree.pack(side='left',fill='both',expand=True)
  self.preview=tk.Label(body,width=40,height=10,bg='#132338',fg='white',text='选择素材预览\n软件预览不代表板端效果');self.preview.pack(side='left',padx=10)
  self.asset_tree.bind('<<TreeviewSelect>>',self.show_preview)
  row=ttk.Frame(page);row.pack(fill='x')
  ttk.Label(row,text='视频目标帧率').pack(side='left');ttk.Combobox(row,textvariable=self.fps,values=['25','30'],state='readonly',width=7).pack(side='left',padx=6)
  ttk.Label(row,text='制作前多少秒（0=全部）').pack(side='left');ttk.Entry(row,textvariable=self.seconds,width=8).pack(side='left',padx=6)
  ttk.Label(row,text='画质').pack(side='left');ttk.Combobox(row,textvariable=self.quality,values=['balanced','high'],state='readonly',width=10).pack(side='left',padx=6)
  ttk.Label(page,text='图片保留标准24位BMP真实尺寸，由板端适配；其他图片会另存为BMP。视频转换为配套格式并提取48kHz单声道音轨。最多12项媒体。',wraplength=1040).pack(anchor='w',pady=6)
  controls=ttk.LabelFrame(page,text='播放器遥控 / 诊断（115200，仅读媒体，不写TF）',padding=6);controls.pack(fill='x',pady=4)
  self.player_states=queue.SimpleQueue();self.last_player_state=None;self.player_buttons={}
  self.player_context=tk.StringVar(value='先点“播放器状态”；按键含义会按最近读到的实际画面状态更新。')
  ttk.Label(controls,textvariable=self.player_context,wraplength=1040).pack(anchor='w')
  keys=ttk.Frame(controls);keys.pack(fill='x',pady=4)
  for title,action in [('播放器状态','status'),('3 上 / 上一帧','up'),('4 下 / 下一帧','down'),('2 打开 / 暂停','open'),('1 返回 / 暂停','back'),('长按1','hold1')]:
   self.player_buttons[action]=self.button(keys,title,lambda a=action:self.player_action(a))
  held=ttk.Frame(page);held.pack(fill='x')
  for title,action in [('长按2 / 图片轮播','hold2'),('长按3 / 上一个视频','hold3'),('长按4 / 下一个视频','hold4')]:
   self.player_buttons[action]=self.button(held,title,lambda a=action:self.player_action(a))
  self.button(held,'载入当前诊断版',lambda:self.restore(candidate=True))
  if difference_available:self.button(held,'载入帧差去闪诊断版',lambda:self.restore(candidate='difference'))
  self.button(held,'恢复 ART9 播放',self.restore)
  ttk.Label(page,text=('ARTF：三源帧间隔差分＋形态学内轮廓；真实验收范围见候选记录。' if difference_available else '')+'时间带诊断版的配置SRAM读回一致性仍待查；ART9可回退，均为SRAM临时加载。',wraplength=1040).pack(anchor='w',pady=3)
  for action,button in self.player_buttons.items():
   if action!='status':button.configure(state='disabled')
  ttk.Label(page,text='按钮按当前画面状态解释；“长按”按钮仅发送一次长按事件，持续调速请按住板上实体键。SW1上拨进入分析、下拨退出。',wraplength=1040).pack(anchor='w')
  volume_row=ttk.LabelFrame(page,text='板端音量（ART6及更新版）：0静音，1～100线性幅度；默认20。显示器菜单音量另行控制。',padding=6)
  volume_row.pack(fill='x',pady=5)
  self.volume_value=tk.DoubleVar(value=20);self.volume_confirmed=tk.StringVar(value='尚未读取板端音量')
  ttk.Scale(volume_row,from_=0,to=100,variable=self.volume_value,orient='horizontal',length=280).pack(side='left',padx=5)
  ttk.Spinbox(volume_row,from_=0,to=100,textvariable=self.volume_value,width=6).pack(side='left')
  self.button(volume_row,'设置板端音量',self.set_board_volume)
  ttk.Label(volume_row,textvariable=self.volume_confirmed).pack(side='left',padx=10)
  self.book.tab(1,text='2  写入与完整校验');self.book.tab(2,text='3  读取 / 导出')
  root.title('Alpha 1.0 · 多媒体工作台')
 def poll(self):
  super().poll()
  if hasattr(self,'network_results'):
   try:
    while True:
     self.network_adapters=self.network_results.get_nowait()
     labels=[f'{a.name} | {a.ip}/{a.prefix} | {a.link_speed}' for a in self.network_adapters]
     self.network_combo['values']=labels
     if self.network_choice.get() not in labels:self.network_choice.set(labels[0] if len(labels)==1 else '')
   except queue.Empty:pass
  if not hasattr(self,'player_states'):return
  try:
   while True:self.last_player_state=self.player_states.get_nowait()
  except queue.Empty:pass
  if not self.busy and self.last_player_state is None:
   for action,button in self.player_buttons.items():
    if action!='status':button.configure(state='disabled')
  elif not self.busy:
   if hasattr(self,'volume_confirmed') and 'volume_percent' in self.last_player_state:self.volume_confirmed.set(f'板端已确认：{self.last_player_state["volume_percent"]}%')
   title,labels=player_controls(self.last_player_state)
   self.player_context.set(title+'；这是最近一次读取，实体操作后可点“播放器状态”刷新。')
   for action,button in self.player_buttons.items():
    if action=='status':continue
    text=labels.get(action)
    button.configure(text=text or {'open':'2 本状态无动作','back':'1 本状态无动作','hold1':'长按1 无动作','hold2':'长按2 无动作','hold3':'长按3 无动作','hold4':'长按4 无动作','up':'3 无动作','down':'4 无动作'}[action],state='normal' if text else 'disabled')
 def player_action(self,action):
  port=self.port.get();expected_state=self.last_player_state
  def work():
   import serial,alpha_link
   if self.client:
    try:self.client.disarm()
    finally:self.drop_client()
   self.q.put(('disconnect',None))
   with serial.Serial(port,115200,timeout=.1,write_timeout=1) as link:
    if action!='status':
     current=next(alpha_link.read_status(link,2),None)
     if not current or current['version']<3:raise RuntimeError('当前是旧按键版本；新交互固件通过验收并设为推荐版后再使用这些按钮')
     current_labels=player_controls(current)[1]
     if action not in current_labels or (expected_state is not None and current_labels.get(action)!=player_controls(expected_state)[1].get(action)):
      self.player_states.put(current)
      return '板上状态已改变或此键当前无效，已更新按钮；本次没有发送按键，请按更新后的名称操作。'
     cmd,mask={'open':(1,2),'up':(1,4),'down':(1,8),'back':(1,1),'hold1':(2,1),'hold2':(2,2),'hold3':(2,4),'hold4':(2,8)}[action]
     alpha_link.send_control(link,cmd,mask)
    state=next(alpha_link.read_status(link,2),None)
   if state is None:raise RuntimeError('未收到Alpha状态；若当前为维护固件，请先恢复播放。未写卡。')
   self.player_states.put(state)
   self.log('播放器实际状态：'+json.dumps(state,ensure_ascii=False))
   result=f'资源库 {"打开" if state["browser"] else "关闭"}；选中第{state["selected"]+1}/{state["resource_count"]}项；时间 {state["media_ms"]/1000:.2f}s；源帧{state["frame_id"]}；欠载{state["underflows"]}；错误{state["error"]}。'
   if state.get('version',0)>=2:result+=f' 实体短按{state["short_count"]}次、长按{state["long_count"]}次；描述符{"就绪" if state["selected_ready"] else "未就绪"}。'
   if state.get('version',0)>=3:result+=f' 速度{state["rate"]:.2f}×；{"速度设置" if state["speed_mode"] else "分析" if state["analysis_on"] else "普通模式"}。'
   if state.get('version',0)>=4:result+=f' {state["runtime_tag"]}；分析源帧{state["analysis_input_frame"]} / 运动结果帧{state["motion_result_frame"]}；PCM采样{state["live_pcm_count"]}。'
   if state.get("runtime_tag") in ("ART9","ARTK","ARTD","ARTF"):result+=f' 波形完成桶{state["wave_completed_bins"]}、历史{state["wave_history_bins"]}/256桶；本版FFT未启用。'
   elif state.get("version",0)>=4:result+=f' FFT更新{state["fft_updates"]}、跳样{state["fft_skipped_samples"]}。'
   if state.get('version',0)>=7:
    result+=f' 关键帧{state.get("keyframe_count",0)}/4；'+('标记源帧 '+str(state['keyframes']) if state.get('keyframes_coherent') else '标记更新中，等待一致快照')
   return result+' 这只是串口状态，HDMI画面与声音需另行确认。'
  self.run(work)
 def set_board_volume(self):
  try:value=max(0,min(100,round(float(self.volume_value.get()))))
  except (ValueError,tk.TclError):messagebox.showerror('音量','请输入0～100');return
  self.volume_value.set(value);port=self.port.get()
  def work():
   import serial,alpha_link
   if self.client:
    try:self.client.disarm()
    finally:self.drop_client()
   self.q.put(('disconnect',None))
   with serial.Serial(port,115200,timeout=.1,write_timeout=1) as link:
    state=next(alpha_link.read_status(link,2),None)
    if not state or state.get('version',0)<5 or state.get('runtime_tag') not in ('ART6','ART7','ART8','ART9','ARTK','ARTD','ARTF'):raise RuntimeError('当前板上版本不支持数字音量；请先下载通过检查且支持数字音量的候选。')
    state=alpha_link.send_control(link,5,value)
    if state.get('volume_percent')!=value:raise RuntimeError('尚未读到目标音量，不能显示设置成功')
    self.player_states.put(state)
   return f'板端音量已确认{value}%；原声与提示音共用该音量。该控制不修改显示器菜单中的音量档位。'
  self.run(work)
 def select_demo(self):
  path=ROOT/'assets/Synthetic_Demo.img'
  try:package.inspect(path,True)
  except FileNotFoundError:
   messagebox.showerror('演示镜像','请先从公开Release下载Synthetic_Demo.img到assets目录，或运行scripts/make_synthetic_demo.py生成。');return
  except Exception as e:messagebox.showerror('演示镜像',str(e));return
  self.img.set(str(path));self.book.select(1)
  self.result.set('已选择合成测试资源包：几何视频、750Hz测试音及四张标准图片。尚未写卡；此素材没有实板验收记录。')
 def select_realtime_demo(self):
  path=ROOT/'assets/Alpha_Realtime_V5.img'
  try:package.inspect(path,True)
  except Exception as e:messagebox.showerror('本轮候选镜像',str(e));return
  self.img.set(str(path));self.book.select(1)
  self.result.set('已选择V5镜像：真实道路音轨、同步测试、四张图片及帧差提示语。本次仅选择文件；卡内内容以完整读回记录为准。写入前须核对卡身份与覆盖确认。')
 def transport_changed(self,event=None):
  if self.client:self.disconnect()
  self.card=None
  self.connection.set('已选择'+self.transport.get()+'；请加载对应维护程序后重新连接。网口数据不依赖COM口。')
 def choose_td(self):
  p=filedialog.askopenfilename(title='选择TD安装目录bin内的td_commands_prompt.exe',filetypes=[('TD命令行','td_commands_prompt.exe')])
  if not p:return
  try:chosen=device_tools.configure_td(p)
  except Exception as e:messagebox.showerror('TD工具路径',str(e));return
  self.result.set('已保存TD路径：'+chosen+'。尚未下载任何固件。')
 def refresh_network(self):
  def work():
   adapters=network_transport.list_adapters();self.network_results.put(adapters)
   return f'发现{len(adapters)}个有IPv4地址的有线网卡；请选择与开发板直连的一项。未修改电脑IP、网关或Wi-Fi。'
  self.run(work,needs_board=False)
 def connect(self):
  if self.transport.get()=='串口':return super().connect()
  index=self.network_combo.current()
  if index<0 or index>=len(self.network_adapters):messagebox.showerror('选择网卡','请先刷新并选择与开发板相连的有线网卡');return
  adapter=self.network_adapters[index]
  def work():
   self.drop_client()
   self.client,card=network_transport.connect(adapter,self.log)
   self.q.put(('network_card',(card,f'已连接网口：{adapter.name} {adapter.ip} → {self.client.peer[0]}；窗口{self.client.window}，不经COM口传数据。')))
   return '网络维护协议与TF身份查询通过，尚未写卡。'
  self.run(work)
 def add_video_asset(self):
  paths=filedialog.askopenfilenames(title='选择视频或旧HXBBX005镜像',filetypes=[('视频与旧镜像','*.mp4 *.mkv *.mov *.avi *.img')])
  for p in paths:self._add('video',p)
 def add_image_asset(self):
  paths=filedialog.askopenfilenames(title='选择图片',filetypes=[('图片','*.bmp *.png *.jpg *.jpeg')])
  for p in paths:self._add('image',p)
 def _add(self,kind,path):
  if len(self.assets)>=12:messagebox.showerror('素材数','首版最多12项媒体');return
  p=Path(path)
  try:
   if kind=='image':
    with Image.open(p) as im:w,h=im.size
    if not (1<=w<=1920 and 1<=h<=1920):raise ValueError(f'图片尺寸{w}×{h}超出1..1920像素范围。请先等比缩小副本；可使用scripts/prepare_images.py，原图不改动。')
    info=f'{w} × {h}'
   elif p.suffix.lower()=='.img':
    import blackbox_studio as media
    meta=media.read_header(p);info=f"{meta['frames']/meta['fps']:.2f}秒 / 配套编码"
   else:
    import media_pipeline
    meta=media_pipeline.metadata(p);info=f"{meta['width']}×{meta['height']} / {meta['duration_s']:.2f}秒"
   i=len(self.assets);self.assets.append(dict(kind=kind,path=str(p),name=p.stem,info=info))
   self.asset_tree.insert('', 'end',iid=str(i),text=p.stem,values=('视频' if kind=='video' else '图片',info,str(p)))
  except Exception as e:messagebox.showerror('无法添加',str(e))
 def remove_asset(self):
  selected=self.asset_tree.selection()
  if not selected:return
  for i in sorted(map(int,selected),reverse=True):self.assets.pop(i)
  self.asset_tree.delete(*self.asset_tree.get_children())
  for i,a in enumerate(self.assets):self.asset_tree.insert('','end',iid=str(i),text=a['name'],values=('视频' if a['kind']=='video' else '图片',a['info'],a['path']))
 def show_preview(self,event=None):
  ids=self.asset_tree.selection()
  if not ids:return
  a=self.assets[int(ids[0])]
  try:
   if a['kind']=='image':im=Image.open(a['path']).convert('RGB')
   elif Path(a['path']).suffix.lower()=='.img':
    import blackbox_studio as media,bb48_codec
    im=Image.fromarray(bb48_codec.decode_frame(media.read_payload(a['path'],0)[0]))
   else:
    import cv2,media_pipeline
    c=cv2.VideoCapture(a['path']);ok,bgr=c.read();c.release()
    if not ok:raise ValueError('无法预览')
    im=Image.fromarray(media_pipeline.fit_rgb(bgr))
   im.thumbnail((320,180));self.preview_photo=ImageTk.PhotoImage(im);self.preview.configure(image=self.preview_photo,text='',width=320,height=180)
  except Exception as e:self.preview.configure(image='',text=str(e),width=40,height=10)
 def make_package(self):
  if not self.assets:messagebox.showinfo('素材','请先添加视频或图片');return
  try:fps=int(self.fps.get());seconds=float(self.seconds.get());quality=self.quality.get()
  except ValueError:messagebox.showerror('参数','帧率和时长须为数字');return
  if seconds<0:messagebox.showerror('时长','时长不能为负数');return
  output=filedialog.asksaveasfilename(initialdir=base.MEDIA,defaultextension='.img',filetypes=[('Alpha资源包','*.img')])
  if not output:return
  if Path(output).exists() or (Path(output).parent/(Path(output).stem+'_assets')).exists():
   messagebox.showerror('请换镜像名称','同名镜像或素材目录已经存在。本工具保留旧内容，请选择新名称后再制作。');return
  sources=list(self.assets)
  def work():
   import blackbox_studio as media,media_pipeline,time
   out=Path(output);cache=out.parent/(out.stem+'_assets')
   if cache.exists():raise FileExistsError('同名素材目录已存在，请换镜像名')
   cache.mkdir();assets=[]
   for i,a in enumerate(sources):
    if self.cancel.is_set():raise InterruptedError('制作取消；未写入TF')
    p=Path(a['path']);alias=('VIDEO' if a['kind']=='video' else 'IMAGE')+f'{i+1:02d}'
    if a['kind']=='image':
     target=cache/(alias+'.bmp')
     with Image.open(p) as im:
      if not (1<=im.width<=1920 and 1<=im.height<=1920):raise ValueError('图片宽高须在1..1920范围')
      im.convert('RGB').save(target)
     w,h=package.bmp_info(target);assets.append(package.Asset(package.IMAGE,alias,target,w,h,1,1,0,source=str(p)))
    else:
     pcm=None
     if p.suffix.lower()=='.img':
      header=media.read_header(p);inner=p
     else:
      inner=cache/(alias+'.img');limit=min(65535,int(seconds*fps)) if seconds else 65535
      if limit<1:raise ValueError('时长不足一帧')
      expected=media_pipeline.estimated_output_frames(media_pipeline.metadata(p),fps,limit);begin=time.monotonic()
      meta=media.make_image(media_pipeline.frames(p,fps,limit,self.cancel),inner,fps,assets=media_pipeline.posters(p),source_label=str(p),quality=quality,cancel=self.cancel,progress=lambda n:self.progress(phase='编码 '+alias,unit='frames',done=n,total=expected,estimated=True,started=begin))
      header=media.read_header(inner)
      self.progress(phase='编码 '+alias,unit='frames',done=header['frames'],total=header['frames'],started=begin)
      self.q.put(('phase','正在提取 '+alias+' 的原声音轨…'))
      pcm=package.extract_pcm(p,cache/(alias+'.pcm'),header['frames']/header['fps'],self.log)
     assets.append(package.Asset(package.VIDEO,alias,inner,640,480,header['fps'],header['frames'],round(header['frames']*1000/header['fps']),pcm,str(p)))
   voices=load_voices()
   self.q.put(('phase','正在封装资源并离线校验镜像…'))
   meta=package.build(assets,out,voices,self.log);package.inspect(out,verify_payload=True)
   self.q.put(('image',str(out)))
   return f'Alpha镜像已制作并离线校验：{len(assets)}项媒体，{meta["image_bytes"]/1024**2:.1f}MiB。尚未写卡。'
  self.run(work,True,needs_board=False)
 def firmware(self,maintenance):
  if maintenance:
   if self.transport.get()=='串口':return super().firmware(True)
   def work():
    self.drop_client();self.q.put(('disconnect',None))
    project=ROOT/'fpga/tf-maintenance'
    pointer=ROOT/'verification/network.json'
    if pointer.exists():
     qualified=project_paths.pointer('tf-maintenance');project=ROOT/qualified['project_relative']
     if device_tools.verify_build(project)['bit_sha256'].upper()!=qualified['bit_sha256'].upper():raise RuntimeError('网络维护固件与发布清单不符')
    device_tools.download(project,self.log,diagnostic=qualified.get('diagnostic_only',False))
    return '网口维护固件已加载到SRAM；刷新有线网卡并点“连接设备”。这一步未写TF，维护程序不输出HDMI。'
   return self.run(work)
  return self.restore()
 def restore_selected(self):
  if self.playback_variant.get().startswith('ARTF'):return self.restore(candidate='difference')
  return self.restore(candidate=self.playback_variant.get().startswith('ARTK'))
 def restore(self,candidate=False):
  records=sorted(base.PROOF.glob('写卡_*.json'))
  if records:
   try:
    last=json.loads(records[-1].read_text(encoding='utf8'))
    if last.get('status')!='VERIFIED' and not messagebox.askyesno('最近镜像未完整校验','最近一次写卡未完成完整读回校验，媒体可能不完整。仍切换到播放器吗？',default='no'):return
   except (OSError,ValueError):pass
  port=self.port.get()
  def work():
   if self.client:
    try:self.client.disarm()
    finally:self.drop_client()
   self.q.put(('disconnect',None))
   project=ROOT/ART9_RELATIVE
   m=project_paths.pointer('fallback-art9')
   if candidate:
    manifest=ROOT/(DIFFERENCE_INDEX if candidate=='difference' else 'verification/player.json')
    if not manifest.exists():raise RuntimeError('本轮候选尚未通过发布前检查，请先使用保留的推荐版本。')
    m=project_paths.pointer('player');project=ROOT/m['project_relative']
    if device_tools.verify_build(project)['bit_sha256'].upper()!=m['bit_sha256'].upper():raise RuntimeError('候选指向与bit不匹配')
   policy=playback_policy(m,device_tools.verify_build(project))
   have_uart=port in [d.device for d in base.protocol.list_devices()]
   if not have_uart:policy['verify_configuration']=False
   if policy['diagnostic']:self.log('载入'+m['runtime_tag']+'诊断候选；配置资格见候选说明，不会伪报配置读回通过，也不改启动Flash。')
   programmed=device_tools.download(project,self.log,device=port,**policy)
   if not have_uart:
    self.player_states.put(None)
    return f'{m.get("runtime_tag","播放器")}已通过JTAG下载到SRAM；没有可用USB-UART，尚未读取运行状态，HDMI画面与声音待实看。TF镜像校验结果另见写卡记录。'
   if candidate and m.get('uart_controls') is False:
    state=dict(status='LOCAL_ONLY_BIT_DOWNLOADED',version=7,runtime_tag='ARTK_LOCAL',uart_controls=False,bit_sha256=programmed['bit_sha256'],hdmi_visual_verified=False)
    self.player_states.put(state)
    (base.PROOF/'最近Alpha状态.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),encoding='utf8')
    return '本地独立版SRAM下载完成；使用板上按键操作。此构建不运行播放串口遥控/遥测，画面与声音需观察确认；TF维护刷写工具照常使用。'
   state=programmed.get('runtime') or device_tools.monitor_alpha(port,log=self.log,expected_runtime=m.get('runtime_tag'))
   state['bit_sha256']=programmed['bit_sha256'];state['hdmi_visual_verified']=False
   state['configuration_verified']='configuration' in programmed
   state['diagnostic_only']=policy['diagnostic']
   (base.PROOF/'最近Alpha状态.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),encoding='utf8')
   if state['catalog_ready'] and state['error']==0:
    if policy['diagnostic']:return m['runtime_tag']+'诊断版已加载、目录就绪。父版本配置读回问题仍待查，当前不是正式推荐版本；SW3用于关键帧。'
    if state.get('version',0)<3:return '旧版Alpha推荐快照已加载，资源索引就绪；尚非V3按键版本。新交互遥控暂不适用，待V3验收后更新推荐快照。'
    return ('实时分析候选' if state.get('version',0)>=4 else 'Alpha V3')+'已加载，资源索引就绪；KEY3/4上下选择、KEY2打开。画面、声音与实体键尚需实板验收。'
   return 'Alpha固件有应答，但资源尚未就绪：请使用ALPHA100镜像。错误码 '+str(state['error'])
  self.run(work)
 def write(self):
  try:
   info=base.transfers.image_details(self.img.get())
   if info.get('format')!='ALPHA100':
    if Path(self.img.get()).parent.name.endswith('_assets'):
     raise ValueError('你选到了_assets文件夹里的单视频中间镜像。请返回上一级，选择“制作Alpha资源镜像”时保存的完整.img资源包；无需重新编码。')
    raise ValueError('Alpha播放器需ALPHA100完整资源包；旧IMG请先在素材页添加后重新封装')
  except Exception as e:messagebox.showerror('镜像格式',str(e));return
  super().write()

def player_controls(state):
 """Describe the actual V3 context. No inferred live polling or board writes."""
 if state.get('uart_controls') is False:return '本地独立版：请用板上按键；播放串口遥控/遥测未启用，TF维护工具可照常使用',{}
 if state.get('version',0)<3:return '旧版固件：请恢复V3后使用新交互',{}
 if state.get('error'):return '播放器错误 '+str(state['error'])+'：请查看详细日志',{}
 if state.get('adjust_mode'):
  names=['曝光','对比度','亮度','音量'];field=['exposure','contrast','brightness','volume_percent'][state['adjust_item']]
  return f"SW4调节：{names[state['adjust_item']]} {state[field]}/100；关闭SW4退出",dict(back='1 选择下一调节项',up='3 增加1',down='4 减少1',hold3='长按3 连增4',hold4='长按4 连减4')
 if not state.get('catalog_ready') or state.get('loading') or state.get('seek_busy'):
  return '装载 / 定位中：请等完成后读取状态',{}
 if state.get('announcing'):return '视图播报中：结束后读取状态',{}
 if state.get('browser'):
  return ('主界面：视频 / 图片' if state.get('root_page') else '图片列表' if state.get('folder_images') else '视频列表'),dict(up='3 上移',down='4 下移',open='2 打开选中',back='1 返回上一级')
 if state.get('image_mode'):
  return ('图片自动轮播：5秒/张；手动换图退出轮播' if state.get('photo_auto') else '图片查看'),dict(up='3 上一张',down='4 下一张',back='1 返回图片列表',hold1='长按1 返回列表',**({'hold2':'长按2 '+('停止轮播' if state.get('photo_auto') else '开始轮播')} if state.get('runtime_tag') in ('ART7','ART8','ART9','ARTK','ARTD','ARTF') else {}))
 play='继续' if not state.get('playing') else '暂停'
 ui6=state.get('runtime_tag') in ('ART6','ART7','ART8','ART9','ARTK','ARTD','ARTF')
 if state.get('speed_mode'):
  return (f'SW2调速：{state["rate"]:.2f}×；只有关闭SW2才能退出' if ui6 else f'速度设置：{state["rate"]:.2f}×'),dict(up='3 减速',down='4 加0.50×',open='2 '+play,hold3='长按3 减0.25×',hold4='长按4 加0.25×',**({} if ui6 else dict(hold1='长按1 退出调速')))
 if state.get('keyframe_mode'):
  entries=state.get('keyframes');label=' / '.join(map(str,entries)) if entries is not None else '等待一致快照'
  return f'SW3关键帧：{state.get("keyframe_count",0)}/4，源帧 [{label}]；关闭SW3退出',dict(up='3 回溯最近前关键帧',down='4 记录当前源帧',open='2 '+play,back='1 删除最近标记')
 if not state.get('analysis_on'):
  if ui6:return '普通视频：2暂停，1退出，SW2调速',dict(up='3 上一帧',down='4 下一帧',open='2 '+play,back='1 返回视频列表',hold3='长按3 上个视频',hold4='长按4 下个视频')
  return '普通视频（旧ART5键位）',dict(up='3 上一帧',down='4 下一帧',back='1 '+play,hold1='长按1 返回列表',hold3='长按3 上个视频',hold4='长按4 下个视频')
 zoom=state.get('fullscreen',False)
 if state.get('runtime_tag') in ('ART9','ARTK','ARTD','ARTF') and zoom:return '分析放大：短按逐帧，长按切视图',dict(up='3 上一帧',down='4 下一帧',hold3='长按3 上一视图',hold4='长按4 下一视图',open='2 '+play,back='1 返回四格')
 return ('分析放大：视图选择' if zoom else '四格分析：视图选择'),dict(up='3 放大当前视图',down='4 选择下一视图',open='2 '+play,back='1 返回四格' if zoom else '1 返回视频列表',**({} if ui6 else dict(hold1='长按1 进入调速')))

def load_voices():
 voices=[]
 for i in range(4):
  p=ROOT/'assets/提示语音'/('cue1_frame_difference.pcm' if i==1 and (ROOT/'assets/提示语音/cue1_frame_difference.pcm').exists() else f'cue{i}.pcm')
  if not p.exists():return []  # No unlicensed voice assets are shipped;packager supports zero voices.
  voices.append(package.Asset(package.VOICE,f'CUE{i}',p,1,1,1,1,0,p,source='本机中文TTS预制播报'))
 return voices

if __name__=='__main__':
 root=tk.Tk();app=AlphaApp(root);root.after(200,app.refresh_network);root.mainloop()
