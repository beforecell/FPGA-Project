//4 geometric slots;one shared coordinate ALU,16 cycles per source snapshot.
// Atomic publication completes640ns after a25MHz HDMI frame_start,in blanking.
// Only a NEW source result advances easing. No prerecorded boxes/CPU analysis.
module alpha_box_smooth(input clk,rst,frame_start,enable,input[15:0]source_frame,
 input[3:0]valid_in,input[111:0]boxes,input paused,
 output reg[3:0]valid_out,output reg[143:0]pixels);
 reg[15:0]last_frame;reg busy,advance;reg[3:0]index,measured_valid,fresh;
 reg[111:0]targets;reg[143:0]work;
 wire[6:0]grid=index[1:0]==0?targets[6:0]:index[1:0]==1?targets[13:7]:index[1:0]==2?targets[20:14]:targets[27:21];
 wire[8:0]target={grid,index[0]?2'b11:2'b00};
 function[8:0]ease;input[8:0]n,p;reg[9:0]d,step;begin
  d=n>p?n-p:p-n;step=(d+3)>>2;if(step>8)step=8;
  ease=d<=1?p:n>p?p+step:p-step;
 end endfunction
 wire[8:0]next_value=!measured_valid[index[3:2]]?9'd0:fresh[index[3:2]]?target:advance?ease(target,work[8:0]):work[8:0];
 wire[143:0]next_work={next_value,work[143:9]};
 always @(posedge clk)begin
  if(rst||!enable)begin last_frame<=0;valid_out<=0;pixels<=0;work<=0;targets<=0;busy<=0;advance<=0;index<=0;fresh<=0;measured_valid<=0;end
  else if(frame_start)begin
   targets<=boxes;work<=pixels;measured_valid<=valid_in;busy<=1;index<=0;
   fresh<=~valid_out|{4{source_frame!=last_frame&&source_frame!=last_frame+1'b1}};
   advance<=source_frame!=last_frame;last_frame<=source_frame;
  end else if(busy)begin
   work<=next_work;
   if(index[1:0]==3)targets<={28'd0,targets[111:28]};
   if(index==15)begin pixels<=next_work;valid_out<=measured_valid;busy<=0;end else index<=index+1'b1;
  end
 end
endmodule
