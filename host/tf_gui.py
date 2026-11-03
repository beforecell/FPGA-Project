"""Unified GUI: JTAG firmware + serial board-card operations + media creation."""
from pathlib import Path
import tkinter as tk
from tkinter import ttk,filedialog,messagebox
import threading,queue,time,json,traceback,sys,datetime,contextlib
import protocol,transfers,device_tools,project_paths

ROOT=Path(__file__).resolve().parent.parent
MAINT=ROOT/project_paths.relative('uart-maintenance')
PLAY=ROOT/'fpga/player'
PLAY_A=PLAY
PROOF=ROOT/'runtime';PROOF.mkdir(parents=True,exist_ok=True)
MEDIA=ROOT/'assets';MEDIA.mkdir(parents=True,exist_ok=True)

def progress_display(value,now):
    """Distinguish estimated encoding length from exact transfer bytes."""
    done=value['done'];total=value.get('total');elapsed=max(.01,now-value['started']);speed=done/elapsed
    frames=value.get('unit')=='frames';estimated=value.get('estimated',False)
    unit=f'{speed:.1f} 帧/s' if frames else f'{speed/1024:.1f} KiB/s'
    if not total or (estimated and done>=total):
        amount=f'已处理{done:,}帧' if frames else f'已处理{done:,}字节'
        percent=99.9 if total else 0
        return percent,f'{value["phase"]} {amount} | {unit} | 总量待确认，暂不估算剩余时间'
    percent=max(0,min(99.9 if estimated else 100,done/total*100))
    amount=(f'（{done:,}/约{total:,}帧）' if estimated else '') if frames else f'（{done/1048576:.1f}/{total/1048576:.1f}MiB）'
    remaining=max(0,total-done)/speed if speed>0 else None
    eta=f'预计剩余约 {remaining/60:.1f} 分钟' if remaining is not None else '正在估算剩余时间'
    if value.get('overall_total'):
        overall=value['overall_done']/value['overall_total']*100
        total_speed=value['overall_done']/max(.01,now-value['overall_started'])
        seconds=(value['overall_total']-value['overall_done'])/total_speed if total_speed else 0
        return overall,f'{value["phase"]} {percent:.1f}%{amount} | 总进度{overall:.1f}% | {unit} | 写入＋校验预计还需约{seconds/60:.1f}分钟'
    return percent,f'{value["phase"]} {percent:.1f}%{amount} | {unit} | {eta}'

def playback_project():
    """Use the promoted immutable player, so edits cannot break daily restore."""
    index=ROOT/'verification/player.json'
    if not index.exists():return PLAY
    m=project_paths.pointer('player');candidate=(ROOT/m['project_relative']).resolve()
    try:candidate.relative_to(ROOT.resolve())
    except ValueError:raise ValueError('推荐固件路径超出发布目录，拒绝下载')
    if device_tools.verify_build(candidate)['bit_sha256']!=m['bit_sha256']:raise ValueError('推荐固件与发布清单不一致')
    return candidate

class App:
 def __init__(self,root):
    self.root=root;root.title('Alpha 1.0 · 多媒体工作台');root.geometry('1040x860');root.minsize(960,780)
    self.q=queue.Queue();self.client=None;self.card=None;self.busy=False;self.cancel=threading.Event();self.widgets=[];self.last_progress=0
    self.logfile=(PROOF/'工具详细日志.log').open('a',encoding='utf-8',buffering=1)
    self.port=tk.StringVar();self.connection=tk.StringVar(value='未连接；数据通道：板载 CH340 USB-UART，1,000,000 baud / 8N1')
    self.play_output=tk.StringVar(value='HDMI A')
    self.card_text=tk.StringVar(value='先进入TF维护模式再连接；JTAG加载固件，镜像经所选网口或备用UART传输。')
    self.img=tk.StringVar();self.result=tk.StringVar(value='尚未开始本次操作；选择镜像和连接设备不会自动覆盖卡。')
    self.progress_text=tk.StringVar(value='等待操作');self.start=tk.StringVar(value='0');self.count=tk.StringVar(value='1024')
    self.video=tk.StringVar();self.fps=tk.StringVar(value='30');self.seconds=tk.StringVar(value='10');self.quality=tk.StringVar(value='balanced')
    style=ttk.Style();style.theme_use('clam');style.configure('Title.TLabel',font=('Microsoft YaHei UI',18,'bold'));style.configure('TButton',padding=7)
    shell=ttk.Frame(root);shell.pack(fill='both',expand=True)
    self.canvas=tk.Canvas(shell,highlightthickness=0)
    vs=ttk.Scrollbar(shell,orient='vertical',command=self.canvas.yview)
    hs=ttk.Scrollbar(shell,orient='horizontal',command=self.canvas.xview)
    vs.pack(side='right',fill='y');hs.pack(side='bottom',fill='x');self.canvas.pack(fill='both',expand=True)
    self.canvas.configure(yscrollcommand=vs.set,xscrollcommand=hs.set)
    frame=ttk.Frame(self.canvas,padding=16);self.canvas_frame=frame
    window=self.canvas.create_window((0,0),window=frame,anchor='nw')
    frame.bind('<Configure>',lambda e:self.canvas.configure(scrollregion=self.canvas.bbox('all')))
    self.canvas.bind('<Configure>',lambda e:self.canvas.itemconfigure(window,width=max(e.width,frame.winfo_reqwidth())))
    root.bind('<MouseWheel>',lambda e:self.canvas.yview_scroll(-int(e.delta/120),'units'))
    ttk.Label(frame,text='Alpha 1.0 · 素材、回放与板载 TF 管理',style='Title.TLabel').pack(anchor='w')
    ttk.Label(frame,text='USB-JTAG 下载固件 · USB-UART 传镜像 · 原生四线SD维护，恢复播放时重新初始化读卡和缓存。').pack(anchor='w',pady=(5,5))
    validation='Alpha正在整机验收；实际完成范围见验证总表，画面、声音及实体按键需人工确认。'
    try:
     release=project_paths.pointer('player')
     if release.get('board_telemetry_pass'):
      pending=[title for key,title in [('manual_hdmi_pass','画面'),('manual_audio_pass','声音'),('manual_keys_pass','实体按键')] if not release.get(key)]
      auto_scope='板端交互与长时测试' if release.get('endurance_v3_pass') else '板端交互测试'
      validation='推荐固件 '+release['bit_sha256'][:12]+'：'+auto_scope+'已通过；'+('、'.join(pending)+'仍待完整人工验收。' if pending else '记录中的画面、声音及按键验收已通过。')
      if 'SOAK_FAILED' in release.get('release_stage',''):
       validation='当前固件 '+release['bit_sha256'][:12]+'：交互测试通过；长时音频测试未通过，修复验证中。画面、声音和实体键仍需人工验收。'
    except (OSError,ValueError):pass
    self.validation=tk.StringVar(value=validation)
    ttk.Label(frame,textvariable=self.validation,foreground='#9a3d00').pack(anchor='w',pady=(0,8))
    link=ttk.LabelFrame(frame,text='1  设备与固件',padding=10);link.pack(fill='x')
    row=ttk.Frame(link);row.pack(fill='x');ttk.Label(row,text='CH340 串口').pack(side='left')
    self.combo=ttk.Combobox(row,textvariable=self.port,state='readonly',width=13);self.combo.pack(side='left',padx=7);self.widgets.append(self.combo)
    self.button(row,'刷新',self.refresh);self.button(row,'连接设备',self.connect);self.button(row,'断开',self.disconnect);self.button(row,'只读诊断',self.diagnose);self.button(row,'修复串口接收',self.repair_serial)
    row=ttk.Frame(link);row.pack(fill='x',pady=5)
    ttk.Label(row,text='播放输出').pack(side='left');self.output_combo=ttk.Combobox(row,textvariable=self.play_output,values=['HDMI A'],state='readonly',width=9);self.output_combo.pack(side='left',padx=(5,9));self.widgets.append(self.output_combo)
    self.button(row,'下载播放程序',lambda:self.firmware(False));self.button(row,'进入 TF 维护模式',lambda:self.firmware(True));self.button(row,'恢复播放',self.restore)
    ttk.Label(link,textvariable=self.connection,wraplength=950).pack(anchor='w',pady=3)
    ttk.Label(link,textvariable=self.card_text,wraplength=950).pack(anchor='w')
    book=ttk.Notebook(frame);self.book=book;book.pack(fill='x',pady=10)
    write=ttk.Frame(book,padding=12);book.add(write,text='2  写入已有 IMG')
    row=ttk.Frame(write);row.pack(fill='x');e=ttk.Entry(row,textvariable=self.img);e.pack(side='left',fill='x',expand=True);self.widgets.append(e)
    self.button(row,'选择 .img',self.choose_img)
    ttk.Label(write,text='完整镜像按原样写入板上的 TF 卡。普通 MP4 请先在“素材与预演”中添加并制作 Alpha 资源镜像。',wraplength=920).pack(anchor='w',pady=8)
    row=ttk.Frame(write);row.pack(fill='x');self.button(row,'写入板载 TF → 完整读回校验',self.write);self.button(row,'只读回并对比所选镜像',self.verify)
    read=ttk.Frame(book,padding=12);book.add(read,text='3  读取 / 导出')
    row=ttk.Frame(read);row.pack(fill='x')
    ttk.Label(row,text='起始扇区 LBA').pack(side='left');e=ttk.Entry(row,textvariable=self.start,width=14);e.pack(side='left',padx=6);self.widgets.append(e)
    ttk.Label(row,text='扇区数（每扇区512字节）').pack(side='left');e=ttk.Entry(row,textvariable=self.count,width=16);e.pack(side='left',padx=6);self.widgets.append(e)
    self.button(row,'按所选镜像大小填写',self.range_from_image)
    row=ttk.Frame(read);row.pack(fill='x',pady=8);self.button(row,'导出指定范围',self.export);self.button(row,'填写整张卡范围',self.full_range)
    ttk.Label(read,text='整张卡导出耗时较长；按需导出镜像范围更实用。取消时保留 .partial，不会标成完整镜像。',wraplength=920).pack(anchor='w')
    convert=ttk.Frame(book,padding=12);book.add(convert,text='4  视频转镜像')
    row=ttk.Frame(convert);row.pack(fill='x');e=ttk.Entry(row,textvariable=self.video);e.pack(side='left',fill='x',expand=True);self.widgets.append(e);self.button(row,'选择 MP4 / 视频',self.choose_video)
    row=ttk.Frame(convert);row.pack(fill='x',pady=8)
    for label,var,values in [('目标FPS',self.fps,['25','30']),('质量',self.quality,['balanced','high'])]:
      ttk.Label(row,text=label).pack(side='left');w=ttk.Combobox(row,textvariable=var,values=values,width=10,state='readonly');w.pack(side='left',padx=6);self.widgets.append(w)
    ttk.Label(row,text='制作前多少秒（0=全部）').pack(side='left');e=ttk.Entry(row,textvariable=self.seconds,width=8);e.pack(side='left',padx=6);self.widgets.append(e)
    self.button(row,'转换为配套 IMG',self.convert)
    ttk.Label(convert,text='沿用已验证播放器的 HXBBX005 / BB48 格式；转换完成后切到“写入已有 IMG”，再次确认目标卡再写。',wraplength=920).pack(anchor='w')
    status=ttk.LabelFrame(frame,text='进度与结果',padding=10);status.pack(fill='x')
    self.bar=ttk.Progressbar(status,maximum=100);self.bar.pack(fill='x')
    row=ttk.Frame(status);row.pack(fill='x',pady=5);ttk.Label(row,textvariable=self.progress_text,wraplength=900).pack(side='left')
    self.cancel_button=ttk.Button(row,text='取消当前传输',command=self.cancel_job,state='disabled');self.cancel_button.pack(side='right')
    ttk.Label(status,textvariable=self.result,wraplength=940).pack(anchor='w')
    self.show_log=tk.BooleanVar(value=False);ttk.Checkbutton(frame,text='展开详细日志',variable=self.show_log,command=self.toggle_log).pack(anchor='w',pady=6)
    self.logbox=ttk.Frame(frame);self.log_text=tk.Text(self.logbox,height=9,font=('Consolas',9),wrap='word',state='disabled');self.log_text.pack(fill='both',expand=True)
    ttk.Label(frame,text='旧版本只读保留。SRAM下载断电丢失，TF内容保留；本工具不擦写启动Flash。媒体包是索引扇区格式，不是FAT32。',wraplength=950).pack(anchor='w',pady=5)
    ttk.Label(frame,text='Alpha 只下载 SRAM；断电后需重新下载 Alpha 播放程序。板上的旧启动 Flash 保留。',wraplength=950).pack(anchor='w')
    root.protocol('WM_DELETE_WINDOW',self.close);root.after(80,self.poll);self.refresh()

 def button(self,parent,text,command):
    b=ttk.Button(parent,text=text,command=command);b.pack(side='left',padx=(0,7));self.widgets.append(b);return b
 def log(self,text):self.q.put(('log',str(text)))
 def toggle_log(self):
    if self.show_log.get():self.logbox.pack(fill='both',expand=True)
    else:self.logbox.pack_forget()
 def refresh(self):
    devices=protocol.list_devices();names=[d.device for d in devices];self.combo['values']=names
    if self.port.get() not in names:self.port.set(names[0] if len(names)==1 else '')
    if not names:self.connection.set('未发现 CH340 串口；连接板载 USB-UART Type-C 数据线并检查驱动。蓝牙COM不作为数据通道。')
 def need_client(self):
    if not self.client:raise ValueError('请先进入TF维护模式，再连接设备')
    return self.client
 def set_card(self,card):
    self.card=card;self.card_text.set(f'TF：{card.name}   容量 {card.capacity/1024**3:.2f} GiB（{card.sectors:,} 扇区）\nCID：{card.identity}   初始化：{"就绪" if card.initialized else "未就绪"}')
 def run(self,fn,cancellable=False,needs_board=True):
    if self.busy:return
    self.busy=True;self.cancel.clear();self.last_progress=0;self.bar['value']=0
    self.progress_text.set('正在执行，请等待…')
    self.result.set('正在处理本次操作；只有完整读回校验通过才会显示写卡成功。')
    for w in self.widgets:w.configure(state='disabled')
    self.cancel_button.configure(state='normal' if cancellable else 'disabled')
    def work():
      try:
       with (device_tools.board_access() if needs_board else contextlib.nullcontext()):value=fn()
       self.q.put(('done',value))
      except Exception as e:
       self.log(str(e) if isinstance(e,InterruptedError) else traceback.format_exc())
       if self.client and hasattr(self.client,'port') and ((isinstance(e,(OSError,TimeoutError)) and not isinstance(e,InterruptedError)) or not self.client.port.is_open):
        self.drop_client();self.q.put(('disconnect',None))
       self.q.put(('cancelled' if isinstance(e,InterruptedError) else 'error',str(e)))
    threading.Thread(target=work,daemon=True).start()
 def progress(self,**kw):
    now=time.monotonic()
    if now-self.last_progress>.15 or kw['done']==kw['total']:self.last_progress=now;self.q.put(('progress',kw))
 def connect(self):
    port=self.port.get()
    def action():
      self.drop_client();self.log(f'连接 {port}，1,000,000 / 8N1')
      self.client,card=protocol.connect(port,self.log);self.q.put(('card',card));return '已连接配套维护固件；TF识别成功，尚未写卡。'
    self.run(action)
 def drop_client(self):
    if self.client:
      try:self.client.port.close()
      finally:self.client=None
 def repair_serial(self):
    port=self.port.get()
    def action():
      if self.client:
       try:self.client.disarm()
       finally:self.drop_client()
      self.q.put(('disconnect',None))
      return device_tools.restart_serial(port,self.log)
    self.run(action)
 def diagnose(self):
    port=self.port.get()
    def action():
      import serial
      if port not in [p.device for p in protocol.list_devices()]:raise ValueError('请选择板载CH340串口')
      self.drop_client();self.q.put(('disconnect',None))
      with serial.Serial(port,1000000,timeout=.05,write_timeout=1) as p:
       p.reset_input_buffer();c=protocol.Client(p,timeout=.6,retries=0,log=self.log)
       try:
        if c.ping(b'READ-ONLY-DIAG')!=b'READ-ONLY-DIAG':raise ValueError('PING不一致')
        card=c.info();self.log(f'串口握手通过；SD诊断 {card.debug1:08X}/{card.debug2:08X}；错误 {card.error:X}')
        self.q.put(('diagnostic_card',card))
        return ('维护协议及TF识别正常。' if card.initialized else '维护协议应答正常，TF未识别；写入将被拒绝。')+' 本次未发ARM或WRITE命令。'
       except (TimeoutError,protocol.ProtocolError):pass
      with serial.Serial(port,115200,timeout=.1,write_timeout=1) as p:
       raw=bytearray();end=time.monotonic()+2
       while time.monotonic()<end:raw.extend(p.read(max(1,p.in_waiting)))
       if any(b'ALPHAST'+str(v).encode('ascii') in raw for v in range(1,8)) or b'BBSTAT05' in raw:return '检测到115200波特率的播放固件状态流；需先点击“进入TF维护模式”。未写卡。'
      return '未收到配套维护协议或播放状态流；检查所选端口及固件，必要时使用“修复串口接收”。未写卡。'
    self.run(action)
 def disconnect(self):
    def action():
      if self.client:
        try:self.client.disarm()
        finally:self.drop_client()
      self.q.put(('disconnect',None));return '已断开设备数据通道。'
    self.run(action)
 def firmware(self,maintenance):
    output=self.play_output.get();project=MAINT if maintenance else playback_project()
    def action():
      if self.client:
        try:self.client.disarm()
        except Exception:self.log('未能收到解除写入应答；关闭串口，JTAG重新配置将清除维护状态。')
      self.drop_client();self.q.put(('disconnect',None));self.log('开始JTAG SRAM下载；这一步不传输或覆盖TF镜像。')
      m=device_tools.download(project,self.log)
      return ('原生SD维护固件已下载，请点“连接设备”。' if maintenance else output+'播放固件已下载到SRAM。点击“恢复播放”可进一步检查真实播放状态。')+' bit SHA256 '+m['bit_sha256'][:16]
    self.run(action)
 def restore(self):
    if self.busy:return
    port=self.port.get()
    output=self.play_output.get();project=PLAY_A if output=='HDMI A' else PLAY
    records=sorted(PROOF.glob('写卡_*.json'))
    if records:
      try:
       status=json.loads(records[-1].read_text(encoding='utf-8'))['status']
       if status!='VERIFIED' and not messagebox.askyesno('当前镜像未验证完整','最近一次写卡未完整写入并通过校验，视频可能无法播放。仍退出维护并重新下载播放程序吗？',default='no'):return
      except (ValueError,KeyError,OSError):pass
    def action():
      if self.client:
       try:self.client.disarm()
       except Exception:self.log('解除写入未应答；不表示镜像已完整。重新配置会清除维护状态。')
      self.drop_client();self.q.put(('disconnect',None))
      programmed=device_tools.download(project,self.log)
      status=device_tools.monitor_playback(port,log=self.log)
      status.update(output_port=output,bit_sha256=programmed['bit_sha256'])
      (PROOF/'最近恢复播放状态.json').write_text(json.dumps(status,ensure_ascii=False,indent=2),encoding='utf-8')
      return '播放逻辑已恢复（'+output+'）：实板帧号递增、CRC正常、错误0。HDMI画面与声音尚需实看验收。'
    self.run(action)
 def choose_img(self):
    p=filedialog.askopenfilename(initialdir=MEDIA,filetypes=[('TF镜像','*.img')])
    if p:self.img.set(p)
 def range_from_image(self):
    try:self.start.set('0');self.count.set(str(transfers.image_details(self.img.get())['sectors']))
    except Exception as e:messagebox.showerror('镜像',str(e))
 def full_range(self):
    if self.card:self.start.set('0');self.count.set(str(self.card.sectors));messagebox.showinfo('整卡范围','已填写范围。整卡数据量较大，建议优先导出所需范围；实际速度以当前通道的进度区为准。')
 def confirm_write(self,card,info):
    answer={};event=threading.Event();self.q.put(('confirm',(card,info,event,answer)));event.wait();return answer.get('yes',False)
 def write(self):
    path=self.img.get()
    def action():
      client=self.need_client();info=transfers.image_details(path);card=client.reinitialize();self.q.put(('card',card))
      if info['sectors']>card.sectors:raise ValueError('镜像超过目标TF容量')
      if not self.confirm_write(card,info):return '未确认覆盖，未写入TF。'
      stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f');record=PROOF/f'写卡_{stamp}.json'
      self.log(f'已明确确认：CID {card.identity}，LBA 0..{info["sectors"]-1}，源SHA256 {info["sha256"]}')
      result=transfers.write_image(client,path,card,info,self.cancel,self.progress,record)
      self.log(json.dumps(result,ensure_ascii=False));return f'成功：已完整写入并从板载TF读回逐字节比较，SHA256一致：{result["readback_sha256"]}。当前仍是TF维护模式；加载播放器后才会输出HDMI。'
    self.run(action,True)
 def verify(self):
    path=self.img.get()
    def action():
      import hashlib
      client=self.need_client();info=transfers.image_details(path);card=client.info();h=hashlib.sha256();begin=time.monotonic()
      if info['sectors']>card.sectors:raise ValueError('镜像超出卡容量')
      with open(path,'rb') as f:
       for i in range(info['sectors']):
        if self.cancel.is_set():raise InterruptedError('读回校验取消，未完成完整校验')
        b=client.read_sector(i)
        if b!=f.read(512):raise ValueError(f'读回不一致：LBA {i}')
        h.update(b);self.progress(phase='只读校验',done=(i+1)*512,total=info['bytes'],started=begin)
      if h.hexdigest()!=info['sha256']:raise ValueError('完整SHA256不一致')
      r=dict(status='READ_ONLY_VERIFIED',card_cid=card.identity,bytes=info['bytes'],sha256=h.hexdigest())
      (PROOF/'最近只读校验.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8');return '读回校验通过：'+h.hexdigest()
    self.run(action,True)
 def export(self):
    try:start=int(self.start.get(),0);count=int(self.count.get(),0);self.need_client()
    except Exception as e:messagebox.showerror('导出范围',str(e));return
    timing=('网口读取，实际速度及预计剩余见进度区。' if getattr(self.client,'channel','uart')=='ethernet' else f'串口计入协议字节的线速理论下限{transfers.wire_seconds(count,False)/60:.1f}分钟，实际更久。')
    if not messagebox.askokcancel('确认读取范围',f'从板载TF读取 LBA {start}，共{count:,}扇区，{count*512/1024**2:.2f} MiB。\n'+timing+'\n此操作不写TF。'):return
    p=filedialog.asksaveasfilename(defaultextension='.img',filetypes=[('原始扇区镜像','*.img')])
    if not p:return
    def action():
      client=self.need_client();r=transfers.export_range(client,p,start,count,client.info(),self.cancel,self.progress);self.log(json.dumps(r,ensure_ascii=False));return '导出完整范围成功：'+r['sha256']
    self.run(action,True)
 def choose_video(self):
    p=filedialog.askopenfilename(filetypes=[('视频','*.mp4 *.mkv *.mov *.avi'),('所有文件','*.*')])
    if p:self.video.set(p)
 def convert(self):
    source=self.video.get()
    try:fps=int(self.fps.get());seconds=float(self.seconds.get());quality=self.quality.get()
    except ValueError:messagebox.showerror('参数','帧率和时长必须为数字');return
    if not Path(source).is_file():messagebox.showerror('视频','请先选择视频');return
    if seconds<0:messagebox.showerror('时长','时长不能为负数');return
    path=filedialog.asksaveasfilename(initialdir=MEDIA,defaultextension='.img',filetypes=[('配套镜像','*.img')])
    if not path:return
    def action():
      import blackbox_studio as media,media_pipeline
      limit=min(65535,int(seconds*fps)) if seconds else 65535
      if limit<=0:raise ValueError('时长不足一帧')
      expected=media_pipeline.estimated_output_frames(media_pipeline.metadata(source),fps,limit);begin=time.monotonic()
      def update(n):self.progress(phase='编码',unit='frames',done=n,total=expected,estimated=True,started=begin)
      meta=media.make_image(media_pipeline.frames(source,fps,limit,self.cancel),path,fps,assets=media_pipeline.posters(source),source_label=str(source),quality=quality,cancel=self.cancel,progress=update)
      self.progress(phase='编码',unit='frames',done=meta['frames'],total=meta['frames'],started=begin)
      self.q.put(('image',path));return f'镜像制作完成：{meta["frames"]}帧，{meta["image_bytes"]/1024**2:.1f} MiB。请到“写入已有IMG”确认目标卡后写入。'
    self.run(action,True,needs_board=False)
 def cancel_job(self):self.cancel.set();self.result.set('正在取消：等待当前扇区操作结束。镜像尚未完整校验，不能视为成功。')
 def poll(self):
    try:
     while True:
      kind,value=self.q.get_nowait()
      if kind=='log':
       line=time.strftime('%H:%M:%S')+' '+value;self.logfile.write(line+'\n');self.log_text.configure(state='normal');self.log_text.insert('end',line+'\n');self.log_text.see('end');self.log_text.configure(state='disabled')
      elif kind=='card':
       self.set_card(value)
       self.connection.set('已连接网口 · 配套维护协议与TF身份查询通过' if getattr(self.client,'channel','uart')=='ethernet' else f'已连接 {self.port.get()} · CH340 USB-UART · 配套维护协议握手通过')
      elif kind=='network_card':self.set_card(value[0]);self.connection.set(value[1])
      elif kind=='diagnostic_card':self.set_card(value);self.connection.set(f'{self.port.get()} 只读诊断结束；串口已关闭，需要“连接设备”后才能传输。')
      elif kind=='disconnect':self.connection.set('设备数据通道已断开；JTAG加载固件与传输TF镜像是独立步骤。')
      elif kind=='image':self.img.set(value)
      elif kind=='phase':self.progress_text.set(value)
      elif kind=='progress':
       percent,label=progress_display(value,time.monotonic());self.bar['value']=percent
       self.progress_text.set(label)
      elif kind=='confirm':
       card,info,event,answer=value
       timing=('网口传输：含写入及完整读回；实际速度与全流程预计时间见进度区。' if getattr(self.client,'channel','uart')=='ethernet' else f'串口写入+完整读回，计入协议字节的理论下限约{transfers.wire_seconds(info["sectors"])/60:.1f}分钟，实际更久。')
       text=f'本次将覆盖开发板上TF卡的数据。\n卡：{card.name}，{card.capacity/1024**3:.2f} GiB\nCID：{card.identity}\n范围：LBA 0..{info["sectors"]-1}（{info["bytes"]:,}字节）\n镜像：{info["path"]}\nSHA256：{info["sha256"]}\n\n'+timing+'\n'+('Alpha资源包：'+str(info.get('format')) if info['compatible'] else '格式与播放器不兼容。')+'\n确认本次覆盖？'
       answer['yes']=messagebox.askyesno('确认覆盖板载TF卡',text,default='no');event.set()
      elif kind in ['done','error','cancelled']:
       self.busy=False;self.cancel_button.configure(state='disabled')
       for w in self.widgets:w.configure(state='readonly' if isinstance(w,ttk.Combobox) else 'normal')
       self.result.set(str(value));self.log(('完成：' if kind=='done' else '已取消/未完成：' if kind=='cancelled' else '失败/未完成：')+str(value))
       if kind=='done':self.progress_text.set('本次操作已结束，详情见结果。')
       if kind=='error':self.show_log.set(True);self.toggle_log()
    except queue.Empty:pass
    self.root.after(80,self.poll)
 def close(self):
    if self.busy:messagebox.showinfo('操作正在进行','请先取消并等待当前扇区操作结束，再关闭窗口。');return
    self.drop_client();self.logfile.close();self.root.destroy()

if __name__=='__main__':
 root=tk.Tk();app=App(root)
 if '--image' in sys.argv:app.img.set(sys.argv[sys.argv.index('--image')+1])
 root.mainloop()
