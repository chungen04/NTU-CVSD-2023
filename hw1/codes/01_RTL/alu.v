module alu #(
    parameter INT_W  = 4,
    parameter FRAC_W = 6,
    parameter INST_W = 4,
    parameter DATA_W = INT_W + FRAC_W
)(
    input                     i_clk,
    input                     i_rst_n,
    input                     i_valid,
    input signed [DATA_W-1:0] i_data_a,
    input signed [DATA_W-1:0] i_data_b,
    input        [INST_W-1:0] i_inst,
    output                    o_valid,
    output       [DATA_W-1:0] o_data
); // Do not modify
    
parameter INST_SIGN_ADD = 4'b0000;
parameter INST_SIGN_SUB = 4'b0001;
parameter INST_SIGN_MUL = 4'b0010;
parameter INST_MAC = 4'b0011;
parameter INST_TANH = 4'b0100;
parameter INST_ORN = 4'b0101;
parameter INST_CLZ = 4'b0110;
parameter INST_CTZ = 4'b0111;
parameter INST_CPOP = 4'b1000;
parameter INST_ROL = 4'b1001;

parameter TANH_INTERS_1_X = 10'sb11_1010_0000; // -96
parameter TANH_INTERS_2_X = 10'sb11_1110_0000; // -32
parameter TANH_INTERS_3_X = 10'sb00_0010_0000; // 32
parameter TANH_INTERS_4_X = 10'sb00_0110_0000; // 96

parameter TANH_INTERS_1_Y = 10'sb11_1100_0000; // -64
parameter TANH_INTERS_2_Y = 10'sb11_1110_0000; // -32
parameter TANH_INTERS_3_Y = 10'sb00_0010_0000; // 32
parameter TANH_INTERS_4_Y = 10'sb00_0100_0000; // 64

// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------

reg i_valid_w, i_valid_r;

reg signed [DATA_W-1:0] o_data_w, o_data_r;
reg signed o_valid_w, o_valid_r;
reg signed [DATA_W-1:0] input_a, input_b;
// ---- Add your own wires and registers here if needed ---- //
wire signed [3*DATA_W-1:0] mul_data_w, mul_data_rounded;
wire signed [DATA_W-1:0] mul_data_final;

integer i;

wire signed [3*DATA_W-1:0] mac_w, mac_round;
wire signed [DATA_W-1:0] mac_final;

// for mul
assign mul_data_w = i_data_a * i_data_b;
assign mul_data_rounded = (mul_data_w[5])? (mul_data_w+'sb100_0000)>>>6: (mul_data_w)>>>6; 
assign mul_data_final = (mul_data_rounded>10'sb01_1111_1111)? (10'sb01_1111_1111): 
                            ((mul_data_rounded<10'sb10_0000_0000)? 10'sb10_0000_0000:mul_data_rounded[9:0]);

assign mac_w = $signed((o_data_r+'sb0)<<<6) + $signed(input_a)*$signed(input_b);
assign mac_round = (mac_w[5])? (mac_w+'sb100_0000)>>>6: (mac_w)>>>6; 
assign mac_final = (mac_round>10'sb01_1111_1111)? (10'sb01_1111_1111): 
                            ((mac_round<10'sb10_0000_0000)? 10'sb10_0000_0000:mac_round[9:0]);
// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
assign o_valid = o_valid_r;
assign o_data = o_data_r;
// ---- Add your own wire data assignments here if needed ---- //


// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //
always@(*) begin
    i_valid_w = i_valid;
    o_data_w = o_data_r;
    o_valid_w = o_valid_r;
    if(o_valid_r) begin
        o_valid_w = 0;
    end
    if(i_valid_r) begin
        case(i_inst)
            INST_SIGN_ADD: begin
                if(i_data_a + i_data_b + 'sb0 > 10'sb01_1111_1111) begin // add +0 for extension
                    o_data_w = 10'sb01_1111_1111;
                end
                else if (i_data_a + i_data_b + 'sb0 < 10'sb10_0000_0000) begin
                    o_data_w = 10'sb10_0000_0000;
                end
                else begin
                    o_data_w = i_data_a + i_data_b;
                end
                o_valid_w = 1;
            end
            INST_SIGN_SUB: begin
                if(i_data_a - i_data_b + 'sb0 > 10'sb01_1111_1111) begin // add +0 for extension
                    o_data_w = 10'sb01_1111_1111;
                end
                else if (i_data_a - i_data_b + 'sb0 < 10'sb10_0000_0000) begin
                    o_data_w = 10'sb10_0000_0000;
                end
                else begin
                    o_data_w = i_data_a - i_data_b;
                end
                o_valid_w = 1;
            end
            INST_SIGN_MUL: begin
                o_data_w = mul_data_final;
                o_valid_w = 1;
            end
            INST_MAC: begin
                o_data_w = mac_final;
                o_valid_w = 1;
            end
            INST_TANH: begin
                if(i_data_a <= TANH_INTERS_1_X) begin
                    o_data_w = TANH_INTERS_1_Y;
                end
                else if(i_data_a > TANH_INTERS_1_X && i_data_a <= TANH_INTERS_2_X) begin
                    o_data_w = i_data_a[0]? ((i_data_a >>> 1) - 'sd16 + 'sd1):((i_data_a >>> 1) - 'sd16);
                end
                else if(i_data_a > TANH_INTERS_2_X && i_data_a <= TANH_INTERS_3_X) begin
                    o_data_w = i_data_a;
                end
                else if(i_data_a > TANH_INTERS_3_X && i_data_a <= TANH_INTERS_4_X) begin
                    o_data_w = i_data_a[0]? ((i_data_a >>> 1) + 'sd16 + 'sd1):((i_data_a >>> 1) + 'sd16);
                end
                else begin // i_data_a > TANH_INTERS_4_X
                    o_data_w = TANH_INTERS_4_Y;
                end
                o_valid_w = 1;
            end
            INST_ORN: begin
                o_data_w = i_data_a | ~i_data_b;
                o_valid_w = 1;
            end
            INST_CLZ: begin
                if(i_data_a[9] == 1) o_data_w = 0;
                else if(i_data_a[8] == 1) o_data_w = 1;
                else if(i_data_a[7] == 1) o_data_w = 2;
                else if(i_data_a[6] == 1) o_data_w = 3;
                else if(i_data_a[5] == 1) o_data_w = 4;
                else if(i_data_a[4] == 1) o_data_w = 5;
                else if(i_data_a[3] == 1) o_data_w = 6;
                else if(i_data_a[2] == 1) o_data_w = 7;
                else if(i_data_a[1] == 1) o_data_w = 8;
                else if(i_data_a[0] == 1) o_data_w = 9;
                else o_data_w = 10;
                o_valid_w = 1;
            end
            INST_CTZ: begin
                if(i_data_a[0] == 1) o_data_w = 0;
                else if(i_data_a[1] == 1) o_data_w = 1;
                else if(i_data_a[2] == 1) o_data_w = 2;
                else if(i_data_a[3] == 1) o_data_w = 3;
                else if(i_data_a[4] == 1) o_data_w = 4;
                else if(i_data_a[5] == 1) o_data_w = 5;
                else if(i_data_a[6] == 1) o_data_w = 6;
                else if(i_data_a[7] == 1) o_data_w = 7;
                else if(i_data_a[8] == 1) o_data_w = 8;
                else if(i_data_a[9] == 1) o_data_w = 9;
                else o_data_w = 10;
                o_valid_w = 1;
            end
            INST_CPOP: begin
                o_data_w = ((i_data_a[0]+i_data_a[1])+(i_data_a[2]+i_data_a[3]))+
                    (i_data_a[4]+i_data_a[5])+
                    ((i_data_a[6]+i_data_a[7])+(i_data_a[8]+i_data_a[9]));
                o_valid_w = 1;
            end
            INST_ROL: begin
                for(i=0; i<DATA_W; i=i+1) begin
                    o_data_w[i] = i_data_a[(i-i_data_b+DATA_W)%DATA_W];
                end
                o_valid_w = 1;
            end
            default: begin
                
            end
        endcase
    end
end



// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //
always@(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_data_r <= 0;
        o_valid_r <= 0;
        i_valid_r <= 0;
        input_a <= 0;
        input_b <= 0;
    end else begin
        o_data_r <= o_data_w;
        o_valid_r <= o_valid_w;
        i_valid_r <= i_valid_w;
        input_a <= i_data_a;
        input_b <= i_data_b;
    end
end

endmodule