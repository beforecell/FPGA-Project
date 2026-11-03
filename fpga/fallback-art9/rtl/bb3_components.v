// Bounded4-connected component traversal on an80x60 motion occupancy grid.
// Input cells are written once each frame, then start is asserted. Every
// visited bit is cleared before enqueue, so a cell is enqueued at most once.
// Busy frames are never overwritten. No coordinate or event-frame presets.
module bb3_components #(parameter CONNECTIVITY=4)(input clk,rst,input cell_we,input[12:0]cell_addr,input cell_bit,
 input start,suppress,input[12:0]active_cells,
 output reg busy,done,overflow,output reg[3:0]box_valid,
 output reg[111:0]boxes);
 localparam IDLE=0,SCAN_REQ=1,SCAN_WAIT=2,SCAN_USE=3,SEED=4,
 POP_REQ=5,POP_WAIT=6,POP_USE=7,NEIGH=8,N_WAIT=9,N_USE=10,
 FINISH=11,CLEAR_NEIGH=12;
 reg[3:0]state;reg[12:0]scan,head,tail,area;reg[6:0]scanx,cx,nx,minx,maxx;
 reg[5:0]scany,cy,ny,miny,maxy;reg[2:0]direction;
 reg[12:0]neighbor_addr;reg neighbor_ok;reg[12:0]raddr;
 wire mapq;wire clear_seed=state==SEED,clear_neighbor=state==CLEAR_NEIGH;
 wire mapwe=cell_we||clear_seed||clear_neighbor;
 wire[12:0]mapwa=cell_we?cell_addr:clear_seed?scan:neighbor_addr;
 bb3_sdp_ram #(.WIDTH(1),.AW(13),.DEPTH(8192)) map_ram(clk,mapwe,mapwa,cell_we?cell_bit:1'b0,1'b1,raddr,mapq);
 reg qwe;reg[11:0]qwa;reg[12:0]qdin;wire[12:0]qout;
 bb3_sdp_ram #(.WIDTH(13),.AW(12),.DEPTH(4096),.IMPLEMENT("32K")) queue_ram(clk,qwe,qwa,qdin,1'b1,head[11:0],qout);
 reg[12:0]rank[0:3];integer k;reg[2:0]position;
 always @* begin
  nx=cx;ny=cy;neighbor_ok=1;
  case(direction)
   0:if(cx==0)neighbor_ok=0;else nx=cx-1'b1;
   1:if(cx==79)neighbor_ok=0;else nx=cx+1'b1;
   2:if(cy==0)neighbor_ok=0;else ny=cy-1'b1;
   3:if(cy==59)neighbor_ok=0;else ny=cy+1'b1;
   4:if(cx==0||cy==0)neighbor_ok=0;else begin nx=cx-1'b1;ny=cy-1'b1;end
   5:if(cx==79||cy==0)neighbor_ok=0;else begin nx=cx+1'b1;ny=cy-1'b1;end
   6:if(cx==0||cy==59)neighbor_ok=0;else begin nx=cx-1'b1;ny=cy+1'b1;end
   7:if(cx==79||cy==59)neighbor_ok=0;else begin nx=cx+1'b1;ny=cy+1'b1;end
  endcase
  position=4;
  if(area>rank[3])position=3;
  if(area>rank[2])position=2;
  if(area>rank[1])position=1;
  if(area>rank[0])position=0;
 end
 task advance_scan;begin
  if(scan==4799)begin busy<=0;done<=1;state<=IDLE;end
  else begin scan<=scan+1'b1;if(scanx==79)begin scanx<=0;scany<=scany+1'b1;end else scanx<=scanx+1'b1;state<=SCAN_REQ;end
 end endtask
 task next_neighbor;begin
  if(direction==(CONNECTIVITY==8?7:3))begin head<=head+1'b1;state<=POP_REQ;end
  else begin direction<=direction+1'b1;state<=NEIGH;end
 end endtask
 always @(posedge clk)begin
  if(rst)begin state<=IDLE;scan<=0;scanx<=0;scany<=0;head<=0;tail<=0;area<=0;
   cx<=0;cy<=0;minx<=0;maxx<=0;miny<=0;maxy<=0;direction<=0;raddr<=0;neighbor_addr<=0;
   qwe<=0;qwa<=0;qdin<=0;busy<=0;done<=0;overflow<=0;boxes<=0;box_valid<=0;
   for(k=0;k<4;k=k+1)rank[k]<=0;
  end else begin
   done<=0;qwe<=0;
   case(state)
    IDLE:if(start)begin
     boxes<=0;box_valid<=0;overflow<=0;for(k=0;k<4;k=k+1)rank[k]<=0;
     scan<=0;scanx<=0;scany<=0;
     if(suppress||active_cells>2400)begin done<=1;busy<=0;end
     else begin state<=SCAN_REQ;busy<=1;end
    end
    SCAN_REQ:begin raddr<=scan;state<=SCAN_WAIT;end
    SCAN_WAIT:state<=SCAN_USE;
    SCAN_USE:if(mapq)begin head<=0;tail<=1;area<=1;minx<=scanx;maxx<=scanx;miny<=scany;maxy<=scany;
     qwe<=1;qwa<=0;qdin<={scany,scanx};state<=SEED;
    end else advance_scan;
    SEED:state<=POP_REQ;
    POP_REQ:if(head==tail)state<=FINISH;else state<=POP_WAIT;
    POP_WAIT:state<=POP_USE;
    POP_USE:begin cx<=qout[6:0];cy<=qout[12:7];direction<=0;state<=NEIGH;end
    NEIGH:if(!neighbor_ok)next_neighbor;else begin neighbor_addr<=ny*13'd80+nx;raddr<=ny*13'd80+nx;state<=N_WAIT;end
    N_WAIT:state<=N_USE;
    N_USE:if(!mapq)next_neighbor;
     else if(tail>=4096)begin overflow<=1;box_valid<=0;busy<=0;done<=1;state<=IDLE;end
     else begin qwe<=1;qwa<=tail[11:0];qdin<={ny,nx};tail<=tail+1'b1;area<=area+1'b1;
      if(nx<minx)minx<=nx;if(nx>maxx)maxx<=nx;if(ny<miny)miny<=ny;if(ny>maxy)maxy<=ny;state<=CLEAR_NEIGH;
     end
    CLEAR_NEIGH:next_neighbor;
    FINISH:begin
     // Reject speckles and a region covering most of the picture. Bounds are
     // grid coordinates inclusive; shader expands to the original320x240.
     if(area>=4&&maxx>minx&&maxy>miny&&(maxx-minx)<64&&(maxy-miny)<48&&position<4)begin
      for(k=3;k>0;k=k-1)if(k>position)begin rank[k]<=rank[k-1];boxes[k*28+:28]<=boxes[(k-1)*28+:28];box_valid[k]<=box_valid[k-1];end
      rank[position]<=area;boxes[position*28+:28]<={1'b0,maxy,1'b0,miny,maxx,minx};box_valid[position]<=1;
     end
     advance_scan;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
