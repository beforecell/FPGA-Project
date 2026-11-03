//4 one-to-one geometric slots,with spatial fragment union.
// One tiny synchronous RAM shares current/previous boxes across bounded FSM work.
// No semantic identity,appearance model,prediction or prerecorded coordinates.
module bb_target_boxes(input clk,rst,start,continuous,input[3:0]valid_in,input[111:0]boxes,
 output reg done,output reg[3:0]valid_out,output reg[111:0]boxes_out);
 localparam IDLE=0,LOAD=1,AREQ=2,AUSE=3,BREQ=4,BUSE=5,OLDREQ=6,OLDUSE=7,
 CANDREQ=8,CANDUSE=9,MATCHWRITE=10,NEWREQ=11,NEWUSE=12,OUTREQ=13,OUTUSE=14,WAITRAM=15;
 reg[3:0]state,after_read;reg[1:0]a,b,j,chosen,index;reg[2:0]ra;
 reg[3:0]work_valid,old_valid,new_valid,used;reg[27:0]ma,bestbox;reg found;reg[8:0]distance;
 wire[27:0]q;
 wire[6:0]al=ma[6:0],ar=ma[13:7],at=ma[20:14],ab=ma[27:21];
 wire[6:0]bl=q[6:0],br=q[13:7],bt=q[20:14],bb=q[27:21];
 wire[6:0]ul=al<bl?al:bl,ur=ar>br?ar:br,ut=at<bt?at:bt,ub=ab>bb?ab:bb;
 wire[6:0]left=al>bl?al:bl,right=ar<br?ar:br;
 wire[7:0]aw={1'b0,ar}-{1'b0,al}+1'b1,bw={1'b0,br}-{1'b0,bl}+1'b1;
 wire aligned=right>=left&&({1'b0,right}-{1'b0,left}+1'b1)>=(aw<bw?(aw+1'b1)>>1:(bw+1'b1)>>1);
 wire contained=(al>=bl&&ar<=br&&at>=bt&&ab<=bb)||(bl>=al&&br<=ar&&bt>=at&&bb<=ab);
 wire vertical_close={1'b0,at}<={1'b0,bb}+3&&{1'b0,bt}<={1'b0,ab}+3;
 wire join_boxes=contained||(aligned&&vertical_close&&ur-ul<64&&ub-ut<48);
 wire overlap=al<=br&&ar>=bl&&at<=bb&&ab>=bt;
 wire[7:0]cx={1'b0,al}+ar,cy={1'b0,at}+ab,ox={1'b0,bl}+br,oy={1'b0,bt}+bb;
 wire[8:0]cost={1'b0,(cx>ox?cx-ox:ox-cx)}+{1'b0,(cy>oy?cy-oy:oy-cy)};
 wire[2:0]free_slot=!new_valid[0]?0:!new_valid[1]?1:!new_valid[2]?2:!new_valid[3]?3:4;
 wire merge_write=state==BUSE&&work_valid[a]&&work_valid[b]&&join_boxes;
 wire new_write=state==NEWUSE&&work_valid[a]&&!used[a]&&free_slot<4;
 wire we=state==LOAD||merge_write||state==MATCHWRITE||new_write;
 wire[2:0]wa=state==LOAD?{1'b0,index}:merge_write?{1'b0,a}:state==MATCHWRITE?{1'b1,a}:{1'b1,free_slot[1:0]};
 wire[27:0]wd=state==LOAD?boxes[index*28+:28]:merge_write?{ub,ut,ur,ul}:state==MATCHWRITE?(found?bestbox:28'd0):q;
 bb3_sdp_ram #(.WIDTH(28),.AW(3),.DEPTH(8)) geometry(clk,we,wa,wd,1'b1,ra,q);
 task read_word;input[2:0]address;input[3:0]destination;begin ra<=address;after_read<=destination;state<=WAITRAM;end endtask
 always @(posedge clk)begin
  if(rst)begin state<=IDLE;after_read<=0;a<=0;b<=0;j<=0;chosen<=0;index<=0;ra<=0;work_valid<=0;old_valid<=0;new_valid<=0;used<=0;ma<=0;bestbox<=0;found<=0;distance<=0;done<=0;valid_out<=0;boxes_out<=0;end
  else begin
   done<=0;
   case(state)
    IDLE:if(start)begin work_valid<=valid_in;if(!continuous)old_valid<=0;new_valid<=0;used<=0;index<=0;state<=LOAD;end
    LOAD:if(index==3)begin a<=0;b<=1;state<=AREQ;end else index<=index+1'b1;
    WAITRAM:state<=after_read;
    AREQ:if(a==3)begin a<=0;state<=OLDREQ;end else read_word({1'b0,a},AUSE);
    AUSE:begin ma<=q;state<=BREQ;end
    BREQ:read_word({1'b0,b},BUSE);
    BUSE:begin
     if(merge_write)begin work_valid[b]<=0;a<=0;b<=1;state<=AREQ;end
     else if(b==3)begin a<=a+1'b1;b<=a+2;state<=AREQ;end
     else begin b<=b+1'b1;state<=BREQ;end
    end
    OLDREQ:read_word({1'b1,a},OLDUSE);
    OLDUSE:begin ma<=q;j<=0;found<=0;distance<=511;state<=CANDREQ;end
    CANDREQ:read_word({1'b0,j},CANDUSE);
    CANDUSE:begin
     if(old_valid[a]&&work_valid[j]&&!used[j]&&overlap&&cost<distance)begin chosen<=j;distance<=cost;bestbox<=q;found<=1;end
     if(j==3)state<=MATCHWRITE;else begin j<=j+1'b1;state<=CANDREQ;end
    end
    MATCHWRITE:begin
     if(found)begin new_valid[a]<=1;used[chosen]<=1;end
     if(a==3)begin a<=0;state<=NEWREQ;end else begin a<=a+1'b1;state<=OLDREQ;end
    end
    NEWREQ:read_word({1'b0,a},NEWUSE);
    NEWUSE:begin
     if(new_write)begin new_valid[free_slot]<=1;used[a]<=1;end
     if(a==3)begin index<=0;state<=OUTREQ;end else begin a<=a+1'b1;state<=NEWREQ;end
    end
    OUTREQ:read_word({1'b1,index},OUTUSE);
    OUTUSE:begin
     boxes_out<={q,boxes_out[111:28]};
     if(index==3)begin valid_out<=new_valid;old_valid<=new_valid;done<=1;state<=IDLE;end
     else begin index<=index+1'b1;state<=OUTREQ;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
