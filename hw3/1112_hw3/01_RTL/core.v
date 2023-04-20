
module core (                       //Don't modify interface
	input         i_clk,
	input         i_rst_n,
	input         i_op_valid,
	input  [ 3:0] i_op_mode,
    output        o_op_ready,
	input         i_in_valid,
	input  [ 7:0] i_in_data,
	output        o_in_ready,
	output        o_out_valid,
	output [13:0] o_out_data
);

// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
// ---- Add your own wires and registers here if needed ---- //

parameter S_IDLE = 4'b1111;
parameter S_LOAD = 4'b0000;
parameter S_O_RIGHT_SHIFT = 4'b0001;
parameter S_O_LEFT_SHIFT = 4'b0010;
parameter S_O_UP_SHIFT = 4'b0011;
parameter S_O_DOWN_SHIFT = 4'b0100;
parameter S_REDUCE_DEPTH = 4'b0101;
parameter S_INC_DEPTH = 4'b0110;
parameter S_OUTPUT_PIXEL = 4'b0111;
parameter S_CONV = 4'b1000;
parameter S_MEDIAN = 4'b1001;
parameter S_HAAR = 4'b1010;

reg [3:0] state_r, state_w;
reg [11:0] load_counter_r, load_counter_w;

reg [2:0] origin_x_r, origin_x_w;
reg [2:0] origin_y_r, origin_y_w;
reg [5:0] depth_r, depth_w; // depth  = 1: 8, 2: 16, 3: 32.

wire [7:0] read_data;
reg [11:0] addr;
reg [13:0] result_w, result_r;
reg result_flag_w, result_flag_r; // because SRAM data comes in next clock edge, it is modeled as sequential variable.

// related to display command
reg [7:0] display_counter_r, display_counter_w;

//related to HAAR command
reg [6:0] haar_counter_r, haar_counter_w; // 
reg [2:0] haar_read_counter_r, haar_read_counter_w;
reg signed [13:0] haar_buffer_r [3:0];
reg signed [13:0] haar_buffer_w [3:0];
reg signed [13:0] haar_temp;
integer i;

sram_4096x8 mem(
   .Q(read_data),
   .CLK(i_clk),
   .CEN(state_r == S_IDLE),
   .WEN(state_r != S_LOAD),
   .A(addr),
   .D(i_in_data)
);

// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
// ---- Add your own wire data assignments here if needed ---- //

assign o_op_ready = (state_r == S_IDLE);
assign o_in_ready = 1;
assign o_out_data = result_flag_r? ((state_r == S_OUTPUT_PIXEL)? result_w:result_r):0; // for S_OUTPUT_PIXEL, result delay valid one cycle. therefore use result_w.
assign o_out_valid = result_flag_r;

// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //

//next state logic
always @(*) begin
	state_w = state_r;

	case(state_r)
	S_IDLE: state_w = i_op_valid? i_op_mode:state_w;
	S_LOAD: begin
		// count to 2048
		state_w = (load_counter_r == 2047? S_IDLE:S_LOAD);
	end
	S_O_DOWN_SHIFT: state_w = S_IDLE;
	S_O_UP_SHIFT: state_w = S_IDLE;
	S_O_LEFT_SHIFT: state_w = S_IDLE;
	S_O_RIGHT_SHIFT: state_w = S_IDLE;
	S_REDUCE_DEPTH: state_w = S_IDLE;
	S_INC_DEPTH: state_w = S_IDLE;
	S_OUTPUT_PIXEL: begin
		if(display_counter_r == (depth_r << 5)) begin // 8 * 4 
			state_w = S_IDLE;
		end
	end
	S_HAAR: begin
		if(haar_counter_r == 64) begin
			state_w = S_IDLE;
		end
	end
	default: begin
	end
	endcase
end

//data logic
always @(*) begin
	origin_x_w = origin_x_r;
	origin_y_w = origin_y_r;
	load_counter_w = load_counter_r;
	depth_w = depth_r;
	display_counter_w = display_counter_r;
	addr = 0;
	result_w = result_r;
	result_flag_w = 0;
	haar_counter_w = haar_counter_r;
	haar_read_counter_w = haar_read_counter_r;

	for(i=0; i<4; i=i+1) begin
		haar_buffer_w[i] = haar_buffer_r[i];
	end
	case(state_r)
	S_IDLE: begin
		display_counter_w = 0;
		for(i=0; i<4; i=i+1) begin
			haar_buffer_w[i] = 0;
		end
		haar_counter_w = 0;
		haar_read_counter_w = 0;
	end
	S_LOAD: begin
		load_counter_w = load_counter_r + 1;
		addr = load_counter_r;
	end
	S_O_RIGHT_SHIFT: begin
		if(origin_x_r < 7) origin_x_w = origin_x_r + 1;
	end
	S_O_LEFT_SHIFT: begin
		if(origin_x_r > 0) origin_x_w = origin_x_r - 1;
	end
	S_O_DOWN_SHIFT: begin
		if(origin_y_r < 7) origin_y_w = origin_y_r + 1;
	end
	S_O_UP_SHIFT: begin
		if(origin_y_r > 0) origin_y_w = origin_y_r - 1;
	end
	S_REDUCE_DEPTH: begin
		case(depth_r)
		1: depth_w = 1;
		2: depth_w = 1;
		4: depth_w = 2;
		default: begin
		end
		endcase
	end
	S_INC_DEPTH: begin
		case(depth_r)
		1: depth_w = 2;
		2: depth_w = 4;
		4: depth_w = 4;
		default: begin
		end
		endcase
	end
	S_OUTPUT_PIXEL: begin
		display_counter_w = display_counter_r + 1;
		result_w = {6'd0, read_data};
		result_flag_w = (display_counter_r == (depth_r << 5))? 0:1;
		case(display_counter_r[1:0])
		0: addr = origin_x_r + (origin_y_r << 3) + (display_counter_r[7:2] << 6) + 0;
		1: addr = origin_x_r + (origin_y_r << 3) + (display_counter_r[7:2] << 6) + 1;
		2: addr = origin_x_r + (origin_y_r << 3) + (display_counter_r[7:2] << 6) + 8;
		3: addr = origin_x_r + (origin_y_r << 3) + (display_counter_r[7:2] << 6) + 9;
		default: begin
		end
		endcase
	end
	S_HAAR: begin
		// a single channel of haar operation has 16 cycles to finish.
		case(haar_counter_r[3:0])
			0: begin
				addr = (haar_counter_r[5:4] << 6) + origin_x_r + (origin_y_r << 3);
				haar_counter_w = haar_counter_r + 1;
			end
			1:begin
				addr = (haar_counter_r[5:4] << 6) + 1 + origin_x_r + (origin_y_r << 3);
				haar_buffer_w[0] = read_data;
				haar_counter_w = haar_counter_r + 1;
			end
			2:begin
				addr = (haar_counter_r[5:4] << 6) + 8 + origin_x_r + (origin_y_r << 3);
				haar_buffer_w[1] = read_data;
				haar_counter_w = haar_counter_r + 1;
			end
			3:begin
				addr = (haar_counter_r[5:4] << 6) + 9 + origin_x_r + (origin_y_r << 3);
				haar_buffer_w[2] = read_data;
				haar_counter_w = haar_counter_r + 1;
			end
			4:begin
				haar_buffer_w[3] = read_data;
				haar_counter_w = haar_counter_r + 1;
			end
			5:begin
				haar_temp = $signed(haar_buffer_r[0]) + $signed(haar_buffer_r[1]) + $signed(haar_buffer_r[2]) + $signed(haar_buffer_r[3]);
				result_w = $unsigned(haar_temp >>> 1) + $unsigned(haar_temp[0]);
				result_flag_w = 1;
				haar_counter_w = haar_counter_r + 1;
			end
			6:begin
				haar_temp = $signed(haar_buffer_r[0]) - $signed(haar_buffer_r[1]) + $signed(haar_buffer_w[2]) - $signed(haar_buffer_w[3]);
				result_w = $unsigned(haar_temp >>> 1) + $unsigned(haar_temp[0]);
				result_flag_w = 1;
				haar_counter_w = haar_counter_r + 1;
			end
			7:begin
				haar_temp = $signed(haar_buffer_r[0]) + $signed(haar_buffer_r[1]) - $signed(haar_buffer_w[2]) - $signed(haar_buffer_w[3]);
				result_w = $unsigned(haar_temp >>> 1) + $unsigned(haar_temp[0]);
				result_flag_w = 1;
				haar_counter_w = haar_counter_r + 1;
			end
			8:begin
				haar_temp = $signed(haar_buffer_r[0]) - $signed(haar_buffer_w[1]) - $signed(haar_buffer_w[2]) + $signed(haar_buffer_w[3]);
				result_w = $unsigned(haar_temp >>> 1) + $unsigned(haar_temp[0]);
				result_flag_w = 1;
				haar_counter_w = haar_counter_r + 1;
			end
			9:begin
				result_w = 0;
				result_flag_w = 0;
				haar_counter_w = haar_counter_r + 7; // go to next one
			end
			10:begin
			end
			11:begin
			end
			12:begin
			end
			13:begin
			end
			14:begin
			end
			15:begin
			end
		endcase
	end
	default: begin
	end
	endcase
end

// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //

always @(posedge i_clk or negedge i_rst_n) begin
	if(~i_rst_n) begin
		state_r <= S_IDLE;
		load_counter_r <= 0;
		origin_x_r <= 0;
		origin_y_r <= 0;
		depth_r <= 4; // deepest
		display_counter_r <= 0;
		result_r <= 0;
		result_flag_r <= 0;
		haar_counter_r <= 0;
		haar_read_counter_r <= 0;
		for(i=0; i<4; i=i+1) begin
			haar_buffer_r[i] = haar_buffer_w[i];
		end
	end
	else begin
		state_r <= state_w;
		load_counter_r <= load_counter_w;
		origin_x_r <= origin_x_w;
		origin_y_r <= origin_y_w;
		depth_r <= depth_w;
		result_r <= result_w;
		display_counter_r <= display_counter_w;
		result_flag_r <= result_flag_w;
		haar_counter_r <= haar_counter_w;
		haar_read_counter_r <= haar_read_counter_w;
		for(i=0; i<4; i=i+1) begin
			haar_buffer_r[i] = haar_buffer_w[i];
		end
	end
end

endmodule
