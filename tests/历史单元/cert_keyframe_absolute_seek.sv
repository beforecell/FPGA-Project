module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,go=0,cancel=0,ack=0,audio_ready=0,cache=0,flush=0;
reg[15:0]destination=0,fps=25,total=180,committed=0;wire busy,req,audio;
wire[15:0]target,phase;wire[31:0]sample,ms;wire[5:0]msp;
alpha_frame_seek dut(clk,rst,cancel,1'b0,1'b0,16'd77,total,fps,ack,committed,cache,audio_ready,flush,busy,req,audio,target,phase,sample,ms,msp,go,destination);
task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
task run;input integer f,n,d,want;reg[63:0]expected;begin
 fps=f;total=n;destination=d;cache=0;audio_ready=0;go=1;tick(1);go=0;destination=12;
 wait(audio);tick(1);expected=(want*64'd48000+f-1)/f;
 if(target!=want||sample!=expected||ms!=expected/48||msp!=expected%48||phase!=expected*f-want*64'd48000)$fatal(1,"absolute frame/sample mismatch f%d target%d/%d sample%d/%d",f,target,want,sample,expected);
 ack=req;committed=target;audio_ready=1;cache=0;tick(4);if(!busy)$fatal(1,"released without frame cache");
 cache=1;flush=1;tick(4);if(!busy)$fatal(1,"released during PCM flush");flush=0;tick(3);if(busy)$fatal(1,"ack stuck");
end endtask
integer f;
initial begin tick(5);rst=0;
for(f=25;f<=30;f=f+1)begin run(f,180,0,0);run(f,180,17,17);run(f,180,179,179);run(f,180,65535,179);run(f,65535,65534,65534);end
go=1;tick(1);go=0;tick(10);cancel=1;tick(1);cancel=0;tick(5);if(busy||audio)$fatal(1,"cancel did not stop seek");
$display("PASS30 absolute seeks:frame+PCM exact,25..30fps,first/last/large and invalid clamped destination,waits cache/clock/audio/flush,cancel;not merely an OSD number update");$finish;end
initial begin #1000000;$fatal(1,"timeout");end
endmodule