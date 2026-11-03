// Fixed analog pad: EG4S20BG256 CH1=M10, board J1 pin16.
// Feed 12.5 MHz; 120-clock SOC interval = 104.1667 ksamples/s.
module bb_adc_control #(
    parameter integer SAMPLE_DIV=120,
    parameter [7:0] SIM_INITIAL_CODE=8'h20,
    parameter [7:0] SIM_CODE_STEP=8'h11
)(
    input wire adc_clk,input wire rst,output reg [7:0] value,output reg valid
);
    reg [4:0] startup;
    reg [7:0] sample_count;
    reg soc,soc_request,eoc_d;
    wire adc_pd=rst || startup<8;
    wire adc_eoc;
    wire [11:0] adc_raw;
    always @(posedge adc_clk)begin
        if(rst)begin startup<=0;sample_count<=0;soc_request<=0;eoc_d<=0;value<=0;valid<=0;end
        else begin
            soc_request<=0;valid<=0;eoc_d<=adc_eoc;
            if(startup<31)begin startup<=startup+1'b1;sample_count<=0;end
            else if(sample_count==SAMPLE_DIV-1)begin sample_count<=0;soc_request<=1;end
            else sample_count<=sample_count+1'b1;
            if(adc_eoc && !eoc_d)begin value<=adc_raw[11:4];valid<=1;end
        end
    end
    // The hard ADC samples SOC at its rising clock and specifies a substantial
    // hold requirement. Launch SOC at the falling edge, leaving half a period
    // (40ns at 12.5MHz) on both sides; do not hide this physical path in SDC.
    always @(negedge adc_clk)begin
        if(rst)soc<=0;else soc<=soc_request;
    end
`ifdef __ICARUS__
    bb_adc_virtual #(.INITIAL_CODE(SIM_INITIAL_CODE),.CODE_STEP(SIM_CODE_STEP)) u_adc_model(
        .clk(adc_clk),.pd(adc_pd),.soc(soc),.eoc(adc_eoc),.dout(adc_raw));
`else
    EG_PHY_ADC #(
        .CH0("DISABLE"),.CH1("ENABLE"),.CH2("DISABLE"),.CH3("DISABLE"),
        .CH4("DISABLE"),.CH5("DISABLE"),.CH6("DISABLE"),.CH7("DISABLE"),
        .VREF("ENABLE")
    ) u_adc(
        .clk(adc_clk),.pd(adc_pd),.s(3'd1),.soc(soc),.eoc(adc_eoc),.dout(adc_raw));
`endif
endmodule

`ifdef __ICARUS__
// Deterministic digital stand-in only. No analog accuracy or board wiring claim.
module bb_adc_virtual #(
    parameter [7:0] INITIAL_CODE=8'h20,
    parameter [7:0] CODE_STEP=8'h11
)(input wire clk,input wire pd,input wire soc,output reg eoc,output reg [11:0] dout);
    reg [7:0] next_code;
    reg [4:0] conversion;
    reg [2:0] eoc_hold;
    initial begin next_code=INITIAL_CODE;conversion=0;eoc_hold=0;eoc=0;dout=0;end
    always @(posedge clk)begin
        if(pd)begin next_code<=INITIAL_CODE;conversion<=0;eoc_hold<=0;eoc<=0;dout<=0;end
        else begin
            if(eoc_hold!=0)begin eoc_hold<=eoc_hold-1'b1;if(eoc_hold==1)eoc<=0;end
            if(conversion!=0)begin
                conversion<=conversion-1'b1;
                if(conversion==1)begin
                    dout<={next_code,4'b0000};next_code<=next_code+CODE_STEP;
                    eoc<=1;eoc_hold<=3;
                end
            end else if(soc)conversion<=16;
        end
    end
endmodule
`endif
