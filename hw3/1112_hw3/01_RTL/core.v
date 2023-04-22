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
parameter S_WAIT_OP = 4'b1110;
parameter S_GEN_OP = 4'b1101;
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

//related to conv operation
reg [18:0] conv_temp_r, conv_temp_w;
//conv_temp saves the temporary sum of the outer channels.
reg [18:0] conv_temp_core_r [3:0]; 
reg [18:0] conv_temp_core_w [3:0];
// conv_temp_core saves the sum of core's convolution.

reg [3:0] conv_stage_counter_r, conv_stage_counter_w;
//conv_stage = 5 send back to idle.
// 0 means fetching the core.
// 1 lets the core calculation be finished.
// 1 fetches the upper left.
// 2 output the first result.
// 3 fetches the upper right.
// 4 output the second result.
// 5 fetches the lower left.
// 6 output the third result.
// 7 fetches the lower right.
// 8 output the fourth result.
reg [2:0] conv_substage_counter_r, conv_substage_counter_w;
// for each substage, fetch different coordinate data. (also used for core convolution, of course)

reg [18:0] conv_temp_round; // just for rounding

reg [5:0] conv_channel_counter_r, conv_channel_counter_w; 

// for MEDIAN operation
reg [2:0] med_channel_counter_r, med_channel_counter_w; // 0~3, 4 channels
reg [2:0] med_region_counter_r, med_region_counter_w; // 0~3, in raster scan order

reg [7:0] med_temp_data_r [15:0];
reg [7:0] med_temp_data_w [15:0]; // save the display region value.(4*4)
reg [7:0] med_sort_data_r [8:0];
reg [7:0] med_sort_data_w [8:0]; // save the sorting values. (3*3) 

reg med_done; // do it when output is done.
reg med_flag_valid_r, med_flag_valid_w;
reg [4:0] med_stage_r, med_stage_w; // 0 for load
reg [4:0] med_load_counter_r, med_load_counter_w; // from 0 to 16(counter to load values in)

sram_4096x8 mem(
   .Q(read_data),
   .CLK(i_clk),
   .CEN((state_r == S_IDLE) || (state_r == S_WAIT_OP) || (stater == S_GEN_OP)),
   .WEN(state_r != S_LOAD),
   .A(addr),
   .D(i_in_data)
);
// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
// ---- Add your own wire data assignments here if needed ---- //

assign o_op_ready = (state_r == S_GEN_OP);
assign o_in_ready = (state_r == S_LOAD);
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
	S_IDLE: state_w = S_GEN_OP;
	S_GEN_OP: state_w = S_WAIT_OP;
	S_WAIT_OP: state_w = i_op_valid? i_op_mode:state_r;
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
	S_CONV: begin
		if(conv_stage_counter_r == 10) begin
			state_w = S_IDLE;
		end
	end
	S_MEDIAN: begin
		if(med_stage_r == 11 && med_channel_counter_r == 3 && result_flag_w && med_region_counter_r == 3) begin
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

	conv_stage_counter_w = conv_stage_counter_r;
	conv_temp_w = conv_temp_r;
	conv_substage_counter_w = conv_substage_counter_r;

	for(i=0; i<4;i=i+1) begin
		conv_temp_core_w[i] = conv_temp_core_r[i];
	end
	conv_channel_counter_w =  conv_channel_counter_r; 
	
	haar_counter_w = haar_counter_r;
	haar_read_counter_w = haar_read_counter_r;
	for(i=0; i<4; i=i+1) begin
		haar_buffer_w[i] = haar_buffer_r[i];
	end

	med_stage_w = (state_r == S_MEDIAN? med_stage_r: 0);
	med_load_counter_w = (state_r == S_MEDIAN? med_load_counter_r: 0);
	med_flag_valid_w = 0;
	med_channel_counter_w = (state_r == S_MEDIAN? med_channel_counter_r: 0);
	for(i=0;i<16;i=i+1) begin
		med_temp_data_w[i] = med_temp_data_r[i];
	end
	for(i=0;i<9;i=i+1) begin
		med_sort_data_w[i] = med_sort_data_r[i];
	end
	med_region_counter_w = med_region_counter_r; 
	

	case(state_r)
	S_IDLE: begin
		display_counter_w = 0;
		for(i=0; i<4; i=i+1) begin
			haar_buffer_w[i] = 0;
		end
		haar_counter_w = 0;
		haar_read_counter_w = 0;
		conv_stage_counter_w = 0;
		conv_temp_w = 0;
		conv_substage_counter_w = 0;
		for(i=0; i<4;i=i+1) begin
			conv_temp_core_w[i] = 0;
		end
		conv_channel_counter_w = 0; 
	end
	S_LOAD: begin
		load_counter_w = load_counter_r + 1;
		addr = load_counter_r;
	end
	S_O_RIGHT_SHIFT: begin
		if(origin_x_r < 6) origin_x_w = origin_x_r + 1;
	end
	S_O_LEFT_SHIFT: begin
		if(origin_x_r > 0) origin_x_w = origin_x_r - 1;
	end
	S_O_DOWN_SHIFT: begin
		if(origin_y_r < 6) origin_y_w = origin_y_r + 1;
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
	S_MEDIAN: begin
		
// reg [7:0] med_temp_data_r [8:0];
// reg med_done; // do it when output is done.
// reg [2:0] med_stage_r// 0 for load, 1 for first pass sort, 2 for second pass sort, 3 for output.
// reg [3:0] med_load_counter_r// from 0 to 15(counter to load values in, all at once)
		case(med_stage_r)
		0: begin
			// load
			med_load_counter_w = med_load_counter_r + 1;
			med_region_counter_w = 0;
			case(med_load_counter_r)
			0: begin
				if(origin_x_r != 0 && origin_y_r != 0) begin
					addr = (med_channel_counter_r << 6) + origin_x_r - 1 + ((origin_y_r - 1) << 3); 
					med_flag_valid_w = 1;
				end
			end
			1:begin
				if(origin_y_r != 0) begin
					addr = (med_channel_counter_r << 6) + origin_x_r + ((origin_y_r - 1) << 3);
					med_flag_valid_w = 1;
				end
				if(med_flag_valid_r) begin
					med_temp_data_w[0] = read_data;
				end else begin
					med_temp_data_w[0] = 0;
				end
			end
			2: begin
				if(origin_y_r != 0) begin
					addr = (med_channel_counter_r << 6) + origin_x_r + 1 + ((origin_y_r - 1) << 3);
					med_flag_valid_w = 1;
				end
				if(med_flag_valid_r) begin
					med_temp_data_w[1] = read_data;
				end else begin
					med_temp_data_w[1] = 0;
				end 
			end
			3:begin
				if(origin_y_r != 0 && origin_x_r != 6) begin
					addr = (med_channel_counter_r << 6) + origin_x_r + 2 + ((origin_y_r - 1) << 3);
					med_flag_valid_w = 1;
				end
				if(med_flag_valid_r) begin
					med_temp_data_w[2] = read_data;
				end else begin
					med_temp_data_w[2] = 0;
				end
			end
			4:begin
				if(origin_x_r != 0 ) begin
					addr = (med_channel_counter_r << 6) + origin_x_r - 1 + ((origin_y_r) << 3);
					med_flag_valid_w = 1;
				end
				if(med_flag_valid_r) begin
					med_temp_data_w[3] = read_data;
				end else begin
					med_temp_data_w[3] = 0;
				end
			end
			5:begin
				addr = (med_channel_counter_r << 6) + origin_x_r + ((origin_y_r) << 3);
				med_flag_valid_w = 1;
				if(med_flag_valid_r) begin
					med_temp_data_w[4] = read_data;
				end else begin
					med_temp_data_w[4] = 0;
				end
			end
			6:begin
				addr = (med_channel_counter_r << 6) + origin_x_r + 1 + ((origin_y_r) << 3);
				med_flag_valid_w = 1;
				if(med_flag_valid_r) begin
					med_temp_data_w[5] = read_data;
				end else begin
					med_temp_data_w[5] = 0;
				end
			end
			7:begin
				if(origin_x_r != 6) begin
					addr = (med_channel_counter_r << 6) + origin_x_r + 2 + ((origin_y_r) << 3);
					med_flag_valid_w = 1;
				end
				if(med_flag_valid_r) begin
					med_temp_data_w[6] = read_data;
				end else begin
					med_temp_data_w[6] = 0;
				end
			end
			8:begin
				if(origin_x_r != 0) begin
					addr = (med_channel_counter_r << 6) + origin_x_r - 1 + ((origin_y_r + 1) << 3);
					med_flag_valid_w = 1;
				end
				if(med_flag_valid_r) begin
					med_temp_data_w[7] = read_data;
				end else begin
					med_temp_data_w[7] = 0;
				end
			end
			9: begin
				addr = (med_channel_counter_r << 6) + origin_x_r + ((origin_y_r + 1) << 3);
				med_flag_valid_w = 1;
				if(med_flag_valid_r) begin
					med_temp_data_w[8] = read_data;
				end else begin
					med_temp_data_w[8] = 0;
				end
			end
			10: begin
				addr = (med_channel_counter_r << 6) + origin_x_r + 1 + ((origin_y_r + 1) << 3);
				med_flag_valid_w = 1;
				if(med_flag_valid_r) begin
					med_temp_data_w[9] = read_data;
				end else begin
					med_temp_data_w[9] = 0;
				end
			end
			11: begin
				if(origin_x_r != 6) begin
					addr = (med_channel_counter_r << 6) + origin_x_r + 2 + ((origin_y_r + 1) << 3);
					med_flag_valid_w = 1;
				end
				if(med_flag_valid_r) begin
					med_temp_data_w[10] = read_data;
				end else begin
					med_temp_data_w[10] = 0;
				end
			end
			12: begin
				if(origin_x_r != 0 && origin_y_r != 6) begin
					addr = (med_channel_counter_r << 6) + origin_x_r - 1 + ((origin_y_r + 2) << 3);
					med_flag_valid_w = 1;
				end
				if(med_flag_valid_r) begin
					med_temp_data_w[11] = read_data;
				end else begin
					med_temp_data_w[11] = 0;
				end
			end
			13: begin
				if(origin_y_r != 6) begin
					addr = (med_channel_counter_r << 6) + origin_x_r + ((origin_y_r + 2) << 3);
					med_flag_valid_w = 1;
				end
				if(med_flag_valid_r) begin
					med_temp_data_w[12] = read_data;
				end else begin
					med_temp_data_w[12] = 0;
				end
			end
			14: begin
				if(origin_y_r != 6) begin
					addr = (med_channel_counter_r << 6) + origin_x_r + 1 + ((origin_y_r + 2) << 3);
					med_flag_valid_w = 1;
				end
				if(med_flag_valid_r) begin
					med_temp_data_w[13] = read_data;
				end else begin
					med_temp_data_w[13] = 0;
				end
			end
			15: begin
				if(origin_y_r != 6 && origin_x_r != 6) begin
					addr = (med_channel_counter_r << 6) + origin_x_r + 2 + ((origin_y_r + 2) << 3);
					med_flag_valid_w = 1;
				end
				if(med_flag_valid_r) begin
					med_temp_data_w[14] = read_data;
				end else begin
					med_temp_data_w[14] = 0;
				end
			end
			16: begin
				if(med_flag_valid_r) begin
					med_temp_data_w[15] = read_data;
				end else begin
					med_temp_data_w[15] = 0;
				end
				med_stage_w = med_stage_r + 1;
			end
			endcase
		end
		1: begin
			case(med_region_counter_r) 
				0: begin
					med_sort_data_w[0] = med_temp_data_r[0];
					med_sort_data_w[1] = med_temp_data_r[1];
					med_sort_data_w[2] = med_temp_data_r[2];
					med_sort_data_w[3] = med_temp_data_r[4];
					med_sort_data_w[4] = med_temp_data_r[5];
					med_sort_data_w[5] = med_temp_data_r[6];
					med_sort_data_w[6] = med_temp_data_r[8];
					med_sort_data_w[7] = med_temp_data_r[9];
					med_sort_data_w[8] = med_temp_data_r[10];
				end
				1: begin
					med_sort_data_w[0] = med_temp_data_r[1];
					med_sort_data_w[1] = med_temp_data_r[2];
					med_sort_data_w[2] = med_temp_data_r[3];
					med_sort_data_w[3] = med_temp_data_r[5];
					med_sort_data_w[4] = med_temp_data_r[6];
					med_sort_data_w[5] = med_temp_data_r[7];
					med_sort_data_w[6] = med_temp_data_r[9];
					med_sort_data_w[7] = med_temp_data_r[10];
					med_sort_data_w[8] = med_temp_data_r[11];
				end
				2: begin
					med_sort_data_w[0] = med_temp_data_r[4];
					med_sort_data_w[1] = med_temp_data_r[5];
					med_sort_data_w[2] = med_temp_data_r[6];
					med_sort_data_w[3] = med_temp_data_r[8];
					med_sort_data_w[4] = med_temp_data_r[9];
					med_sort_data_w[5] = med_temp_data_r[10];
					med_sort_data_w[6] = med_temp_data_r[12];
					med_sort_data_w[7] = med_temp_data_r[13];
					med_sort_data_w[8] = med_temp_data_r[14];
				end
				3: begin
					med_sort_data_w[0] = med_temp_data_r[5];
					med_sort_data_w[1] = med_temp_data_r[6];
					med_sort_data_w[2] = med_temp_data_r[7];
					med_sort_data_w[3] = med_temp_data_r[9];
					med_sort_data_w[4] = med_temp_data_r[10];
					med_sort_data_w[5] = med_temp_data_r[11];
					med_sort_data_w[6] = med_temp_data_r[13];
					med_sort_data_w[7] = med_temp_data_r[14];
					med_sort_data_w[8] = med_temp_data_r[15];
				end
			endcase
			med_stage_w = 2;
		end
		2:begin
			// vertical sort
			if(med_sort_data_r[0] > med_sort_data_r[1]) begin
				med_sort_data_w[0] = med_sort_data_r[1];
				med_sort_data_w[1] = med_sort_data_r[0]; 
			end
			if(med_sort_data_r[3] > med_sort_data_r[4]) begin
				med_sort_data_w[3] = med_sort_data_r[4];
				med_sort_data_w[4] = med_sort_data_r[3];
			end
			if(med_sort_data_r[6] > med_sort_data_r[7]) begin
				med_sort_data_w[6] = med_sort_data_r[7];
				med_sort_data_w[7] = med_sort_data_r[6];
			end
			med_stage_w = 3;
		end
		3:begin
			if(med_sort_data_r[1] > med_sort_data_r[2]) begin
				med_sort_data_w[1] = med_sort_data_r[2];
				med_sort_data_w[2] = med_sort_data_r[1]; 
			end
			if(med_sort_data_r[4] > med_sort_data_r[5]) begin
				med_sort_data_w[4] = med_sort_data_r[5];
				med_sort_data_w[5] = med_sort_data_r[4];
			end
			if(med_sort_data_r[7] > med_sort_data_r[8]) begin
				med_sort_data_w[7] = med_sort_data_r[8];
				med_sort_data_w[8] = med_sort_data_r[7];
			end
			med_stage_w = 4;
		end
		4:begin
			if(med_sort_data_r[0] > med_sort_data_r[1]) begin
				med_sort_data_w[0] = med_sort_data_r[1];
				med_sort_data_w[1] = med_sort_data_r[0]; 
			end
			if(med_sort_data_r[3] > med_sort_data_r[4]) begin
				med_sort_data_w[3] = med_sort_data_r[4];
				med_sort_data_w[4] = med_sort_data_r[3];
			end
			if(med_sort_data_r[6] > med_sort_data_r[7]) begin
				med_sort_data_w[6] = med_sort_data_r[7];
				med_sort_data_w[7] = med_sort_data_r[6];
			end
			med_stage_w = 5;
		end
		5: begin
			if(med_sort_data_r[0] > med_sort_data_r[3]) begin
				med_sort_data_w[0] = med_sort_data_r[3];
				med_sort_data_w[3] = med_sort_data_r[0]; 
			end
			if(med_sort_data_r[1] > med_sort_data_r[4]) begin
				med_sort_data_w[1] = med_sort_data_r[4];
				med_sort_data_w[4] = med_sort_data_r[1];
			end
			if(med_sort_data_r[2] > med_sort_data_r[5]) begin
				med_sort_data_w[2] = med_sort_data_r[5];
				med_sort_data_w[5] = med_sort_data_r[2];
			end
			med_stage_w = 6;
		end
		6:begin
			if(med_sort_data_r[3] > med_sort_data_r[6]) begin
				med_sort_data_w[3] = med_sort_data_r[6];
				med_sort_data_w[6] = med_sort_data_r[3]; 
			end
			if(med_sort_data_r[4] > med_sort_data_r[7]) begin
				med_sort_data_w[4] = med_sort_data_r[7];
				med_sort_data_w[7] = med_sort_data_r[4];
			end
			if(med_sort_data_r[5] > med_sort_data_r[8]) begin
				med_sort_data_w[5] = med_sort_data_r[8];
				med_sort_data_w[8] = med_sort_data_r[5];
			end
			med_stage_w = 7;
		end
		7: begin
			if(med_sort_data_r[0] > med_sort_data_r[3]) begin
				med_sort_data_w[0] = med_sort_data_r[3];
				med_sort_data_w[3] = med_sort_data_r[0]; 
			end
			if(med_sort_data_r[1] > med_sort_data_r[4]) begin
				med_sort_data_w[1] = med_sort_data_r[4];
				med_sort_data_w[4] = med_sort_data_r[1];
			end
			if(med_sort_data_r[2] > med_sort_data_r[5]) begin
				med_sort_data_w[2] = med_sort_data_r[5];
				med_sort_data_w[5] = med_sort_data_r[2];
			end
			med_stage_w = 8;
		end
		8:begin
			if(med_sort_data_r[2]>med_sort_data_r[4]) begin
				med_sort_data_w[2] = med_sort_data_r[4];
				med_sort_data_w[4] = med_sort_data_r[2];
			end
			med_stage_w = 9;
		end
		9: begin
			if(med_sort_data_r[4]>med_sort_data_r[6]) begin
				med_sort_data_w[4] = med_sort_data_r[6];
				med_sort_data_w[6] = med_sort_data_r[4];
			end
			med_stage_w = 10;
		end
		10: begin
			if(med_sort_data_r[2]>med_sort_data_r[4]) begin
				med_sort_data_w[2] = med_sort_data_r[4];
				med_sort_data_w[4] = med_sort_data_r[2];
			end
			med_stage_w = 11;
		end
		11: begin
			result_flag_w = 1;
			result_w = med_sort_data_r[4];
			if(med_region_counter_r == 3) begin
				med_stage_w = 0;
				med_channel_counter_w = med_channel_counter_r + 1;
			end else begin
				med_stage_w = 1;
				med_region_counter_w = med_region_counter_r + 1;
			end
		end
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
			default:begin
			end
		endcase
	end
	S_CONV: begin
		conv_channel_counter_w = conv_channel_counter_r + 1;
		result_flag_w = 0;
		case(conv_stage_counter_r)
		0:begin
			if(conv_substage_counter_r >= 3 && conv_channel_counter_r == (depth_r<<3)-1) begin
				conv_stage_counter_w = 1;
				// perform calculation on 1.
				conv_channel_counter_w = 0;
				conv_substage_counter_w = 0;
			end
			else if(conv_channel_counter_r == (depth_r<<3)-1) begin
				// move to next position
				conv_substage_counter_w = conv_substage_counter_r + 1;
				conv_channel_counter_w = 0;
			end
			case(conv_substage_counter_r)
			0: begin
				addr = (conv_channel_counter_r << 6) + 0 + origin_x_r + (origin_y_r << 3);
				if(conv_channel_counter_r != 0) begin
					conv_temp_core_w[0] = conv_temp_core_r[0] + (read_data);
				end
			end
			1: begin
				addr = (conv_channel_counter_r << 6) + 1 + origin_x_r + (origin_y_r << 3);
				if(conv_channel_counter_r != 0) begin
					conv_temp_core_w[1] = conv_temp_core_r[1] + (read_data);
				end else begin
					conv_temp_core_w[0] = conv_temp_core_r[0] + (read_data);
				end
			end
			2: begin
				addr = (conv_channel_counter_r << 6) + 8 + origin_x_r + (origin_y_r << 3);
				if(conv_channel_counter_r != 0) begin
					conv_temp_core_w[2] = conv_temp_core_r[2] + (read_data);
				end else begin
					conv_temp_core_w[1] = conv_temp_core_r[1] + (read_data);
				end
			end
			3: begin
				addr = (conv_channel_counter_r << 6) + 9 + origin_x_r + (origin_y_r << 3);
				if(conv_channel_counter_r != 0) begin
					conv_temp_core_w[3] = conv_temp_core_r[3] + (read_data);
				end else begin
					conv_temp_core_w[2] = conv_temp_core_r[2] + (read_data);
				end
			end
			default: begin
			end
			endcase
		end
		1: begin
			conv_temp_core_w[3] = conv_temp_core_r[3] + (read_data);
			conv_stage_counter_w = 2;
			conv_channel_counter_w = 0;
		end
		2:begin
			if(conv_substage_counter_r > 4) begin
				conv_stage_counter_w = 3;
				conv_channel_counter_w = 0;
				conv_substage_counter_w = 0;
			end
			else if(conv_channel_counter_r == (depth_r<<3)-1) begin
				// move to next position
				conv_substage_counter_w = conv_substage_counter_r + 1;
				conv_channel_counter_w = 0;
			end
			case(conv_substage_counter_r)
			0: begin
				if(origin_x_r == 0 || origin_y_r == 0) begin
					conv_substage_counter_w = 1;
					conv_channel_counter_w = 0;
					addr = (conv_channel_counter_r << 6)  + origin_x_r - 1 + ((origin_y_r-1) << 3);
					conv_temp_w = 0;
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r - 1 + ((origin_y_r-1) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end else begin
						conv_temp_w = 0;
					end
				end
			end
			1: begin
				if(origin_x_r == 0) begin
					conv_substage_counter_w = 2;
					conv_channel_counter_w = 0;
					addr = (conv_channel_counter_r << 6)  + origin_x_r - 1 + ((origin_y_r) << 3);
					if (!(origin_x_r == 0 || origin_y_r == 0)) begin // if y_r is 0, previous read data is meaningless.
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r - 1 + ((origin_y_r) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end else if (!(origin_x_r == 0 || origin_y_r == 0)) begin // if y_r is 0, previous read data is meaningless.
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
				end
			end
			2: begin
				if(origin_x_r == 0) begin
					conv_substage_counter_w = 3;
					conv_channel_counter_w = 0;
					addr = (conv_channel_counter_r << 6)  + origin_x_r - 1 + ((origin_y_r + 1) << 3);
					if(origin_x_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r - 1 + ((origin_y_r + 1) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end else if(origin_x_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
				end
			end
			3: begin
				if(origin_y_r == 0) begin
					conv_substage_counter_w = 4;
					conv_channel_counter_w = 0;
					addr = (conv_channel_counter_r << 6)  + origin_x_r + ((origin_y_r - 1) << 3);
					if (origin_x_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r + ((origin_y_r - 1) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end else if (origin_x_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
				end
			end
			4: begin
				if(origin_y_r == 0) begin
					conv_substage_counter_w = 5;
					conv_channel_counter_w = 0;
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 1 + ((origin_y_r - 1) << 3);
					if (origin_y_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 1 + ((origin_y_r - 1) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end else if (origin_y_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
				end
			end
			5: begin
				conv_temp_round = ((origin_y_r == 0? conv_temp_w: (conv_temp_r + (read_data << 0))) + (conv_temp_core_r[0]<<2) + (conv_temp_core_r[1]<<1) + (conv_temp_core_r[2]<<1) + (conv_temp_core_r[3]));
				result_flag_w = 1;
				result_w = (conv_temp_round>>4)+conv_temp_round[3];
			end
			default: begin
			end
			endcase
		end
		3:begin
			// output second result.
			conv_stage_counter_w = 4;
			conv_channel_counter_w = 0;
		end
		4:begin
			// calculate second one
			if(conv_substage_counter_r > 4) begin
				conv_stage_counter_w = 5;
				conv_channel_counter_w = 0;
				conv_substage_counter_w = 0;
			end
			else if(conv_channel_counter_r == (depth_r<<3)-1) begin
				// move to next position
				conv_substage_counter_w = conv_substage_counter_r + 1;
				conv_channel_counter_w = 0;
			end
			case(conv_substage_counter_r)
			0: begin
				if(origin_x_r == 6 || origin_y_r == 0) begin
					conv_substage_counter_w = 1;
					conv_channel_counter_w = 0;
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 2 + ((origin_y_r-1) << 3);
					conv_temp_w = 0;
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 2 + ((origin_y_r-1) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end else begin
						conv_temp_w = 0;
					end
				end
			end
			1: begin
				if(origin_x_r == 6 ) begin
					conv_substage_counter_w = 2;
					conv_channel_counter_w = 0;
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 2 + ((origin_y_r) << 3);
					if (!((origin_x_r == 6 || origin_y_r == 0))) begin // if y_r is 0, previous read data is meaningless.
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 2 + ((origin_y_r) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end else if (!((origin_x_r == 6 || origin_y_r == 0))) begin // if y_r is 0, previous read data is meaningless.
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
				end
			end
			2: begin
				if(origin_x_r == 6) begin
					conv_substage_counter_w = 3;
					conv_channel_counter_w = 0;
					if (origin_x_r != 6)begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 2 + ((origin_y_r + 1) << 3);
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 2 + ((origin_y_r + 1) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end else if (origin_x_r != 6)begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
				end
			end
			3: begin
				if(origin_y_r ==0) begin
					conv_substage_counter_w = 4;
					conv_channel_counter_w = 0;
					if (origin_x_r != 6) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 1 + ((origin_y_r - 1) << 3);
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 1 + ((origin_y_r - 1) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end else if (origin_x_r != 6) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
				end
			end
			4: begin
				if(origin_y_r ==0) begin
					conv_substage_counter_w = 5;
					conv_channel_counter_w = 0;
					if (origin_y_r !=0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
					addr = (conv_channel_counter_r << 6)  + origin_x_r + ((origin_y_r - 1) << 3);
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r + ((origin_y_r - 1) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end else if (origin_y_r !=0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
				end
			end
			5: begin
			result_flag_w = 1;
			conv_temp_round = ((origin_y_r !=0? (conv_temp_r + (read_data << 0)):conv_temp_w) + (conv_temp_core_r[0]<<1) + (conv_temp_core_r[1]<<2) + (conv_temp_core_r[2]) + (conv_temp_core_r[3]<<1));
			result_w = (conv_temp_round>>4)+conv_temp_round[3];
			end
			default: begin
			end
			endcase
		end
		5:begin
			conv_stage_counter_w = 6;
			conv_channel_counter_w = 0;
		end
		6: begin
			// calculate third one
			if(conv_substage_counter_r > 4) begin
				conv_stage_counter_w = 7;
				conv_channel_counter_w = 0;
				conv_substage_counter_w = 0;
			end
			else if(conv_channel_counter_r == (depth_r<<3)-1) begin
				// move to next position
				conv_substage_counter_w = conv_substage_counter_r + 1;
				conv_channel_counter_w = 0;
			end
			case(conv_substage_counter_r)
			0: begin
				if(origin_x_r == 0 || origin_y_r == 6) begin
					conv_substage_counter_w = 1;
					conv_channel_counter_w = 0;
					addr = (conv_channel_counter_r << 6)  + origin_x_r - 1 + ((origin_y_r+2) << 3);
					conv_temp_w = 0;
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r - 1 + ((origin_y_r+2) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end else begin
						conv_temp_w = 0;
					end
				end
			end
			1: begin
				if(origin_x_r == 0) begin
					conv_substage_counter_w = 2;
					conv_channel_counter_w = 0;
					if (!(origin_x_r == 0 || origin_y_r == 6)) begin // if y_r is 0, previous read data is meaningless.
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
					addr = (conv_channel_counter_r << 6)  + origin_x_r - 1 + ((origin_y_r + 1) << 3);
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r - 1 + ((origin_y_r + 1) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end else if (!(origin_x_r == 0 || origin_y_r == 6)) begin // if y_r is 0, previous read data is meaningless.
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
				end
			end
			2: begin
				if(origin_x_r == 0 ) begin
					conv_substage_counter_w = 3;
					conv_channel_counter_w = 0;
					if (origin_x_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
					addr = (conv_channel_counter_r << 6)  + origin_x_r - 1 + ((origin_y_r) << 3);
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r - 1 + ((origin_y_r) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end else if (origin_x_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
				end
			end
			3: begin
				if(origin_y_r == 6) begin
					conv_substage_counter_w = 4;
					conv_channel_counter_w = 0;
					if (origin_x_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
					addr = (conv_channel_counter_r << 6)  + origin_x_r + ((origin_y_r + 2) << 3);
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r + ((origin_y_r + 2) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end else if (origin_x_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
				end
			end
			4: begin
				if(origin_y_r == 6) begin
					conv_substage_counter_w = 5;
					conv_channel_counter_w = 0;
					if(origin_y_r != 6)begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 1 + ((origin_y_r + 2) << 3);
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 1 + ((origin_y_r + 2) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end else if(origin_y_r != 6)begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
				end
			end
			5: begin
				result_flag_w = 1;
				conv_temp_round = ((origin_y_r != 6? (conv_temp_r + (read_data << 0)):conv_temp_w) + (conv_temp_core_r[0]<<1) + (conv_temp_core_r[1]) + (conv_temp_core_r[2]<<2) + (conv_temp_core_r[3]<<1));
				result_w = (conv_temp_round>>4)+conv_temp_round[3];
			end
			default: begin
			end
			endcase
		end
		7: begin
			conv_stage_counter_w = 8;
			conv_channel_counter_w = 0;
		end
		8: begin
			// calculate fourth one
			if(conv_substage_counter_r > 4) begin
				conv_stage_counter_w = 9;
				conv_channel_counter_w = 0;
				conv_substage_counter_w = 0;
			end
			else if(conv_channel_counter_r == (depth_r<<3)-1) begin
				// move to next position
				conv_substage_counter_w = conv_substage_counter_r + 1;
				conv_channel_counter_w = 0;
			end
			case(conv_substage_counter_r)
			0: begin
				if(origin_x_r == 6 || origin_y_r == 6) begin
					conv_substage_counter_w = 1;
					conv_channel_counter_w = 0;
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 2 + ((origin_y_r+2) << 3);
					conv_temp_w = 0;
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 2 + ((origin_y_r+2) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end else begin
						conv_temp_w = 0;
					end
				end
			end
			1: begin
				if(origin_x_r == 6) begin
					conv_substage_counter_w = 2;
					conv_channel_counter_w = 0;
					addr = (conv_channel_counter_r << 6)  + origin_x_r+2  + ((origin_y_r+1) << 3);
					if (!(origin_x_r == 6 || origin_y_r == 6)) begin // if y_r is 0, previous read data is meaningless.
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r+2  + ((origin_y_r+1) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end else if (!(origin_x_r == 6 || origin_y_r == 6)) begin // if y_r is 0, previous read data is meaningless.
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
				end
			end
			2: begin
				if(origin_x_r == 6) begin
					conv_substage_counter_w = 3;
					conv_channel_counter_w = 0;
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 2 + ((origin_y_r ) << 3);
					if(origin_x_r != 6)begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r + 2 + ((origin_y_r ) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end else if(origin_x_r != 6)begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
				end
			end
			3: begin
				if(origin_y_r == 6) begin
					conv_substage_counter_w = 4;
					conv_channel_counter_w = 0;
					addr = (conv_channel_counter_r << 6)  + origin_x_r+1 + ((origin_y_r + 2) << 3);
					if (origin_x_r != 6) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r+1 + ((origin_y_r + 2) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end else if (origin_x_r != 6) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end
				end
			end
			4: begin
				if(origin_y_r == 6) begin
					conv_substage_counter_w = 5;
					conv_channel_counter_w = 0;
					if(origin_y_r != 6)begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
					addr = (conv_channel_counter_r << 6)  + origin_x_r + ((origin_y_r + 2) << 3);
				end else begin
					addr = (conv_channel_counter_r << 6)  + origin_x_r + ((origin_y_r + 2) << 3);
					if(conv_channel_counter_r != 0) begin
						conv_temp_w = conv_temp_r + (read_data << 0);
					end else if(origin_y_r != 6)begin
						conv_temp_w = conv_temp_r + (read_data << 1);
					end
				end
			end
			5: begin
				result_flag_w = 1;
				conv_temp_round = ((origin_y_r != 6? (conv_temp_r + (read_data << 0)):conv_temp_w) + (conv_temp_core_r[0]) + (conv_temp_core_r[1]<<1) + (conv_temp_core_r[2]<<1) + (conv_temp_core_r[3]<<2));
				result_w = (conv_temp_round>>4)+conv_temp_round[3];
			end
			default: begin
			end
			endcase
		end
		9: begin
			conv_stage_counter_w = 10;
			conv_channel_counter_w = 0;
		end
		default: begin
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
		conv_stage_counter_r <= 0;
		conv_temp_r <= 0;
		conv_substage_counter_r <= 0;
		for(i=0; i<4;i=i+1) begin
			conv_temp_core_r[i] <= 0;
		end
		conv_channel_counter_r <= 0;
		med_channel_counter_r <= 0;
		med_region_counter_r <= 0;
		for(i=0;i<16;i=i+1) begin
			med_temp_data_r[i] <= 0;
		end
		med_stage_r <= 0;
		med_load_counter_r <= 0;
		med_flag_valid_r <= med_flag_valid_w;
		for(i=0;i<9;i=i+1) begin
			med_sort_data_r[i] <= 0;
		end
		med_region_counter_r <= med_region_counter_w; 
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
		conv_stage_counter_r <= conv_stage_counter_w;
		conv_temp_r <= conv_temp_w;
		conv_substage_counter_r <= conv_substage_counter_w;
		for(i=0; i<4;i=i+1) begin
			conv_temp_core_r[i] <= conv_temp_core_w[i];
		end
		conv_channel_counter_r <=  conv_channel_counter_w;
		med_channel_counter_r <= med_channel_counter_w;
		med_region_counter_r <= med_region_counter_w;
		for(i=0;i<16;i=i+1) begin
			med_temp_data_r[i] <= med_temp_data_w[i];
		end
		med_stage_r <= med_stage_w;
		med_load_counter_r <= med_load_counter_w;
		med_flag_valid_r <= med_flag_valid_w;
		for(i=0;i<9;i=i+1) begin
			med_sort_data_r[i] <= med_sort_data_w[i];
		end
		med_region_counter_r <= med_region_counter_w; 
	end
end

endmodule
