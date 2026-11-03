// Non-preemptive raw-sector transactions. Requests are latched before arbitration.
// Index scan > PCM refill > video/BMP object. No client drives SD pins directly.
module alpha_sd_arb(input clk,rst,
 input[2:0]request,input[31:0]lba0,lba1,lba2,blocks0,blocks1,blocks2,input[2:0]ready,
 output[2:0]busy,done,valid,output[7:0]data,output[3:0]err0,err1,err2,
 output reg start,output reg[31:0]lba,blocks,input card_busy,card_done,card_valid,
 input[7:0]card_data,input[3:0]card_error,output card_ready);
 reg[2:0]pending;reg[31:0]pl[0:2],pb[0:2];reg[1:0]owner;reg seen;integer i;
 assign busy=pending|{3{owner!=0}};
 assign done={owner==3,owner==2,owner==1}&{3{card_done&&seen}};
 assign valid={owner==3,owner==2,owner==1}&{3{card_valid}};
 assign data=card_data;
 assign err0=owner==1 ? card_error:0;assign err1=owner==2 ? card_error:0;assign err2=owner==3 ? card_error:0;
 assign card_ready=owner==1 ? ready[0]:owner==2 ? ready[1]:owner==3 ? ready[2]:1'b1;
 always @(posedge clk)begin
  if(rst)begin pending<=0;owner<=0;seen<=0;start<=0;lba<=0;blocks<=0;for(i=0;i<3;i=i+1)begin pl[i]<=0;pb[i]<=0;end end
  else begin
   start<=0;
   for(i=0;i<3;i=i+1)if(request[i])begin pending[i]<=1;pl[i]<=i==0 ? lba0:i==1 ? lba1:lba2;pb[i]<=i==0 ? blocks0:i==1 ? blocks1:blocks2;end
   if(owner==0&&!card_busy&&!start)begin
    if(pending[0])begin owner<=1;lba<=pl[0];blocks<=pb[0];pending[0]<=0;start<=1;seen<=0;end
    else if(pending[1])begin owner<=2;lba<=pl[1];blocks<=pb[1];pending[1]<=0;start<=1;seen<=0;end
    else if(pending[2])begin owner<=3;lba<=pl[2];blocks<=pb[2];pending[2]<=0;start<=1;seen<=0;end
   end
   if(owner!=0&&card_busy)seen<=1;
   if(owner!=0&&seen&&card_done)begin owner<=0;seen<=0;end
  end
 end
endmodule
