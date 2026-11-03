// Same two-clock display interface; FPGA builds one monotonic8-bit transfer
// function per setting change, then reads three identical double-buffered maps.
module alpha_picture_adjust(input clk,rst,frame_start,enable,input[23:0]rgb,
 input[7:0]exposure,contrast,brightness,output reg[23:0]adjusted);
 (* ram_style="bram" *)reg[10:0]coefficients[0:511];integer i;
 initial begin
  for(i=0;i<512;i=i+1)coefficients[i]=0;
  coefficients[0]=11'd64;coefficients[128]=11'd0;coefficients[256]=11'd1920;
  coefficients[1]=11'd66;coefficients[129]=11'd5;coefficients[257]=11'd1923;
  coefficients[2]=11'd68;coefficients[130]=11'd10;coefficients[258]=11'd1925;
  coefficients[3]=11'd70;coefficients[131]=11'd15;coefficients[259]=11'd1928;
  coefficients[4]=11'd72;coefficients[132]=11'd20;coefficients[260]=11'd1930;
  coefficients[5]=11'd74;coefficients[133]=11'd26;coefficients[261]=11'd1933;
  coefficients[6]=11'd76;coefficients[134]=11'd31;coefficients[262]=11'd1935;
  coefficients[7]=11'd78;coefficients[135]=11'd36;coefficients[263]=11'd1938;
  coefficients[8]=11'd80;coefficients[136]=11'd41;coefficients[264]=11'd1940;
  coefficients[9]=11'd82;coefficients[137]=11'd46;coefficients[265]=11'd1943;
  coefficients[10]=11'd84;coefficients[138]=11'd51;coefficients[266]=11'd1946;
  coefficients[11]=11'd87;coefficients[139]=11'd56;coefficients[267]=11'd1948;
  coefficients[12]=11'd89;coefficients[140]=11'd61;coefficients[268]=11'd1951;
  coefficients[13]=11'd92;coefficients[141]=11'd67;coefficients[269]=11'd1953;
  coefficients[14]=11'd94;coefficients[142]=11'd72;coefficients[270]=11'd1956;
  coefficients[15]=11'd97;coefficients[143]=11'd77;coefficients[271]=11'd1958;
  coefficients[16]=11'd100;coefficients[144]=11'd82;coefficients[272]=11'd1961;
  coefficients[17]=11'd103;coefficients[145]=11'd87;coefficients[273]=11'd1964;
  coefficients[18]=11'd105;coefficients[146]=11'd92;coefficients[274]=11'd1966;
  coefficients[19]=11'd108;coefficients[147]=11'd97;coefficients[275]=11'd1969;
  coefficients[20]=11'd111;coefficients[148]=11'd102;coefficients[276]=11'd1971;
  coefficients[21]=11'd115;coefficients[149]=11'd108;coefficients[277]=11'd1974;
  coefficients[22]=11'd118;coefficients[150]=11'd113;coefficients[278]=11'd1976;
  coefficients[23]=11'd121;coefficients[151]=11'd118;coefficients[279]=11'd1979;
  coefficients[24]=11'd124;coefficients[152]=11'd123;coefficients[280]=11'd1981;
  coefficients[25]=11'd128;coefficients[153]=11'd128;coefficients[281]=11'd1984;
  coefficients[26]=11'd132;coefficients[154]=11'd133;coefficients[282]=11'd1987;
  coefficients[27]=11'd135;coefficients[155]=11'd138;coefficients[283]=11'd1989;
  coefficients[28]=11'd139;coefficients[156]=11'd143;coefficients[284]=11'd1992;
  coefficients[29]=11'd143;coefficients[157]=11'd148;coefficients[285]=11'd1994;
  coefficients[30]=11'd147;coefficients[158]=11'd154;coefficients[286]=11'd1997;
  coefficients[31]=11'd151;coefficients[159]=11'd159;coefficients[287]=11'd1999;
  coefficients[32]=11'd155;coefficients[160]=11'd164;coefficients[288]=11'd2002;
  coefficients[33]=11'd160;coefficients[161]=11'd169;coefficients[289]=11'd2004;
  coefficients[34]=11'd164;coefficients[162]=11'd174;coefficients[290]=11'd2007;
  coefficients[35]=11'd169;coefficients[163]=11'd179;coefficients[291]=11'd2010;
  coefficients[36]=11'd174;coefficients[164]=11'd184;coefficients[292]=11'd2012;
  coefficients[37]=11'd179;coefficients[165]=11'd189;coefficients[293]=11'd2015;
  coefficients[38]=11'd184;coefficients[166]=11'd195;coefficients[294]=11'd2017;
  coefficients[39]=11'd189;coefficients[167]=11'd200;coefficients[295]=11'd2020;
  coefficients[40]=11'd194;coefficients[168]=11'd205;coefficients[296]=11'd2022;
  coefficients[41]=11'd199;coefficients[169]=11'd210;coefficients[297]=11'd2025;
  coefficients[42]=11'd205;coefficients[170]=11'd215;coefficients[298]=11'd2028;
  coefficients[43]=11'd211;coefficients[171]=11'd220;coefficients[299]=11'd2030;
  coefficients[44]=11'd217;coefficients[172]=11'd225;coefficients[300]=11'd2033;
  coefficients[45]=11'd223;coefficients[173]=11'd230;coefficients[301]=11'd2035;
  coefficients[46]=11'd229;coefficients[174]=11'd236;coefficients[302]=11'd2038;
  coefficients[47]=11'd236;coefficients[175]=11'd241;coefficients[303]=11'd2040;
  coefficients[48]=11'd242;coefficients[176]=11'd246;coefficients[304]=11'd2043;
  coefficients[49]=11'd249;coefficients[177]=11'd251;coefficients[305]=11'd2045;
  coefficients[50]=11'd256;coefficients[178]=11'd256;coefficients[306]=11'd0;
  coefficients[51]=11'd263;coefficients[179]=11'd261;coefficients[307]=11'd3;
  coefficients[52]=11'd271;coefficients[180]=11'd266;coefficients[308]=11'd5;
  coefficients[53]=11'd278;coefficients[181]=11'd271;coefficients[309]=11'd8;
  coefficients[54]=11'd286;coefficients[182]=11'd276;coefficients[310]=11'd10;
  coefficients[55]=11'd294;coefficients[183]=11'd282;coefficients[311]=11'd13;
  coefficients[56]=11'd302;coefficients[184]=11'd287;coefficients[312]=11'd15;
  coefficients[57]=11'd311;coefficients[185]=11'd292;coefficients[313]=11'd18;
  coefficients[58]=11'd320;coefficients[186]=11'd297;coefficients[314]=11'd20;
  coefficients[59]=11'd329;coefficients[187]=11'd302;coefficients[315]=11'd23;
  coefficients[60]=11'd338;coefficients[188]=11'd307;coefficients[316]=11'd26;
  coefficients[61]=11'd347;coefficients[189]=11'd312;coefficients[317]=11'd28;
  coefficients[62]=11'd357;coefficients[190]=11'd317;coefficients[318]=11'd31;
  coefficients[63]=11'd367;coefficients[191]=11'd323;coefficients[319]=11'd33;
  coefficients[64]=11'd377;coefficients[192]=11'd328;coefficients[320]=11'd36;
  coefficients[65]=11'd388;coefficients[193]=11'd333;coefficients[321]=11'd38;
  coefficients[66]=11'd399;coefficients[194]=11'd338;coefficients[322]=11'd41;
  coefficients[67]=11'd410;coefficients[195]=11'd343;coefficients[323]=11'd44;
  coefficients[68]=11'd422;coefficients[196]=11'd348;coefficients[324]=11'd46;
  coefficients[69]=11'd434;coefficients[197]=11'd353;coefficients[325]=11'd49;
  coefficients[70]=11'd446;coefficients[198]=11'd358;coefficients[326]=11'd51;
  coefficients[71]=11'd458;coefficients[199]=11'd364;coefficients[327]=11'd54;
  coefficients[72]=11'd471;coefficients[200]=11'd369;coefficients[328]=11'd56;
  coefficients[73]=11'd484;coefficients[201]=11'd374;coefficients[329]=11'd59;
  coefficients[74]=11'd498;coefficients[202]=11'd379;coefficients[330]=11'd61;
  coefficients[75]=11'd512;coefficients[203]=11'd384;coefficients[331]=11'd64;
  coefficients[76]=11'd526;coefficients[204]=11'd389;coefficients[332]=11'd67;
  coefficients[77]=11'd541;coefficients[205]=11'd394;coefficients[333]=11'd69;
  coefficients[78]=11'd556;coefficients[206]=11'd399;coefficients[334]=11'd72;
  coefficients[79]=11'd572;coefficients[207]=11'd404;coefficients[335]=11'd74;
  coefficients[80]=11'd588;coefficients[208]=11'd410;coefficients[336]=11'd77;
  coefficients[81]=11'd605;coefficients[209]=11'd415;coefficients[337]=11'd79;
  coefficients[82]=11'd622;coefficients[210]=11'd420;coefficients[338]=11'd82;
  coefficients[83]=11'd639;coefficients[211]=11'd425;coefficients[339]=11'd84;
  coefficients[84]=11'd657;coefficients[212]=11'd430;coefficients[340]=11'd87;
  coefficients[85]=11'd676;coefficients[213]=11'd435;coefficients[341]=11'd90;
  coefficients[86]=11'd695;coefficients[214]=11'd440;coefficients[342]=11'd92;
  coefficients[87]=11'd714;coefficients[215]=11'd445;coefficients[343]=11'd95;
  coefficients[88]=11'd734;coefficients[216]=11'd451;coefficients[344]=11'd97;
  coefficients[89]=11'd755;coefficients[217]=11'd456;coefficients[345]=11'd100;
  coefficients[90]=11'd776;coefficients[218]=11'd461;coefficients[346]=11'd102;
  coefficients[91]=11'd798;coefficients[219]=11'd466;coefficients[347]=11'd105;
  coefficients[92]=11'd820;coefficients[220]=11'd471;coefficients[348]=11'd108;
  coefficients[93]=11'd843;coefficients[221]=11'd476;coefficients[349]=11'd110;
  coefficients[94]=11'd867;coefficients[222]=11'd481;coefficients[350]=11'd113;
  coefficients[95]=11'd891;coefficients[223]=11'd486;coefficients[351]=11'd115;
  coefficients[96]=11'd917;coefficients[224]=11'd492;coefficients[352]=11'd118;
  coefficients[97]=11'd942;coefficients[225]=11'd497;coefficients[353]=11'd120;
  coefficients[98]=11'd969;coefficients[226]=11'd502;coefficients[354]=11'd123;
  coefficients[99]=11'd996;coefficients[227]=11'd507;coefficients[355]=11'd125;
  coefficients[100]=11'd1024;coefficients[228]=11'd512;coefficients[356]=11'd128;
  coefficients[101]=11'd1024;coefficients[229]=11'd512;coefficients[357]=11'd128;
  coefficients[102]=11'd1024;coefficients[230]=11'd512;coefficients[358]=11'd128;
  coefficients[103]=11'd1024;coefficients[231]=11'd512;coefficients[359]=11'd128;
  coefficients[104]=11'd1024;coefficients[232]=11'd512;coefficients[360]=11'd128;
  coefficients[105]=11'd1024;coefficients[233]=11'd512;coefficients[361]=11'd128;
  coefficients[106]=11'd1024;coefficients[234]=11'd512;coefficients[362]=11'd128;
  coefficients[107]=11'd1024;coefficients[235]=11'd512;coefficients[363]=11'd128;
  coefficients[108]=11'd1024;coefficients[236]=11'd512;coefficients[364]=11'd128;
  coefficients[109]=11'd1024;coefficients[237]=11'd512;coefficients[365]=11'd128;
  coefficients[110]=11'd1024;coefficients[238]=11'd512;coefficients[366]=11'd128;
  coefficients[111]=11'd1024;coefficients[239]=11'd512;coefficients[367]=11'd128;
  coefficients[112]=11'd1024;coefficients[240]=11'd512;coefficients[368]=11'd128;
  coefficients[113]=11'd1024;coefficients[241]=11'd512;coefficients[369]=11'd128;
  coefficients[114]=11'd1024;coefficients[242]=11'd512;coefficients[370]=11'd128;
  coefficients[115]=11'd1024;coefficients[243]=11'd512;coefficients[371]=11'd128;
  coefficients[116]=11'd1024;coefficients[244]=11'd512;coefficients[372]=11'd128;
  coefficients[117]=11'd1024;coefficients[245]=11'd512;coefficients[373]=11'd128;
  coefficients[118]=11'd1024;coefficients[246]=11'd512;coefficients[374]=11'd128;
  coefficients[119]=11'd1024;coefficients[247]=11'd512;coefficients[375]=11'd128;
  coefficients[120]=11'd1024;coefficients[248]=11'd512;coefficients[376]=11'd128;
  coefficients[121]=11'd1024;coefficients[249]=11'd512;coefficients[377]=11'd128;
  coefficients[122]=11'd1024;coefficients[250]=11'd512;coefficients[378]=11'd128;
  coefficients[123]=11'd1024;coefficients[251]=11'd512;coefficients[379]=11'd128;
  coefficients[124]=11'd1024;coefficients[252]=11'd512;coefficients[380]=11'd128;
  coefficients[125]=11'd1024;coefficients[253]=11'd512;coefficients[381]=11'd128;
  coefficients[126]=11'd1024;coefficients[254]=11'd512;coefficients[382]=11'd128;
  coefficients[127]=11'd1024;coefficients[255]=11'd512;coefficients[383]=11'd128;
 end

 (* ram_style="bram" *)reg[7:0]map_r[0:511],map_g[0:511],map_b[0:511];integer mi;
 initial for(mi=0;mi<512;mi=mi+1)begin map_r[mi]=mi[7:0];map_g[mi]=mi[7:0];map_b[mi]=mi[7:0];end
 reg bank,write_bank,map_valid,map_ready;reg[7:0]applied_e,applied_c,applied_b,work_e,work_c,work_b;
 reg[8:0]address;reg[10:0]q,eg;reg[9:0]cg;reg signed[8:0]bg;
 reg[3:0]state;reg[20:0]combined;wire[20:0]combined_round=combined+21'd128;
 reg[11:0]gain;reg signed[10:0]bias;reg[7:0]write_index;reg[19:0]product;
 wire current_work=work_e==exposure&&work_c==contrast&&work_b==brightness;
 function[7:0]clip;input[19:0]p;input signed[10:0]offset;reg signed[13:0]v;begin
  v=$signed({1'b0,((p+20'd128)>>8)})+offset;clip=v<0?8'd0:v>255?8'd255:v[7:0];end endfunction
 wire[8:0]wa={write_bank,write_index};wire[7:0]write_value=clip(product,bias);
 reg[7:0]qr,qg,qb;reg[23:0]raw_delayed;reg apply_delayed;
 always @(posedge clk)begin
  qr<=map_r[{bank,rgb[23:16]}];qg<=map_g[{bank,rgb[15:8]}];qb<=map_b[{bank,rgb[7:0]}];
  if(!rst&&state==10)begin map_r[wa]<=write_value;map_g[wa]<=write_value;map_b[wa]<=write_value;end
 end
 always @(posedge clk)begin
  q<=coefficients[address];
  if(rst)begin bank<=0;write_bank<=1;map_valid<=0;map_ready<=0;applied_e<=50;applied_c<=50;applied_b<=50;work_e<=50;work_c<=50;work_b<=50;address<=0;eg<=256;cg<=256;bg<=0;state<=0;combined<=65536;gain<=256;bias<=0;write_index<=0;product<=0;raw_delayed<=0;apply_delayed<=0;adjusted<=0;end
  else begin
   raw_delayed<=rgb;apply_delayed<=enable&&map_valid;adjusted<=apply_delayed?{qr,qg,qb}:raw_delayed;
   if(frame_start&&map_ready&&current_work)begin bank<=write_bank;map_valid<=1;map_ready<=0;applied_e<=work_e;applied_c<=work_c;applied_b<=work_b;end
   case(state)
    0:if(map_ready)begin if(!current_work)map_ready<=0;end
      else if(!map_valid||applied_e!=exposure||applied_c!=contrast||applied_b!=brightness)begin
       work_e<=exposure;work_c<=contrast;work_b<=brightness;write_bank<=!bank;address<={2'b00,exposure>100?7'd100:exposure[6:0]};state<=1;
      end
    1:state<=2;
    2:begin eg<=q;address<={2'b01,work_c>100?7'd100:work_c[6:0]};state<=3;end
    3:state<=4;
    4:begin cg<=q[9:0];address<={2'b10,work_b>100?7'd100:work_b[6:0]};state<=5;end
    5:state<=6;
    6:begin bg<=q[8:0];combined<=eg*cg;state<=7;end
    7:begin gain<=combined_round[19:8];bias<=11'sd128-$signed({1'b0,cg[9:1]})+$signed(bg);write_index<=0;state<=9;end
    9:begin product<=write_index*gain;state<=10;end
    10:if(write_index==255)begin map_ready<=1;state<=0;end else begin write_index<=write_index+1'b1;state<=9;end
    default:state<=0;
   endcase
  end
 end
endmodule
