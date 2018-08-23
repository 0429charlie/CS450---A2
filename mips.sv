// this is a mips module that can only execute the addiu instruction
module mips(
	// port list
	input clk, reset,
	output [31:0] instr_addr,
	input [31:0] instr_in,
	output logic [31:0] data_addr,
	input [31:0] data_in,
	output logic [31:0] data_out,
	output data_rd_wr);

	// parameters overridden in testbench
	parameter [31:0] pc_init = 0;
	parameter [31:0] sp_init = 0;
	parameter [31:0] ra_init = 0;

	// IF signals
	logic [31:0] pc;
	assign instr_addr = pc;
	logic [31:0] ir;

	// ID signals
    logic [4:0] reg_rd_num0, reg_rd_num1;
    wire [31:0] reg_rd_data0, reg_rd_data1;
	assign reg_rd_num0 = ir[25:21];
	assign reg_rd_num1 = ir[20:16];

	// EX signals
	logic [31:0] a, b, sign_ext_imm;
	logic [31:0] alu_out;
	int lw = 1;

	// ME signals
	logic st_en;
	assign data_out = b;
	assign data_rd_wr = ~st_en;

	// WD signals
    logic [4:0] reg_wr_num;
    logic [31:0] reg_wr_data;
    logic reg_wr_en;
	// Continuous assignment of reg_wr_data that decide which data to take in
	assign reg_wr_data = lw ? alu_out : data_in;

	enum { init, fetch, id, ex, me, wb } state;

	// register file
    regfile #(.sp_init(sp_init), .ra_init(ra_init)) regs(
		.wr_num(reg_wr_num), .wr_data(reg_wr_data), .wr_en(reg_wr_en),
        .rd0_num(reg_rd_num0), .rd0_data(reg_rd_data0),
		.rd1_num(reg_rd_num1), .rd1_data(reg_rd_data1),
        .clk(clk), .reset(reset));

	always @(posedge clk or posedge reset) begin
		if(reset) begin
			reg_wr_en <= 0;
			pc <= pc_init;
			state <= init;
		end
		else
			case(state)
				init: begin
					// this state is needed since we have to wait for
					// memory to produce the first instruction after reset
					state <= fetch;
				end
				fetch: begin							// ir get new instruction. pc updated so that instr_in will be updated
					ir <= instr_in;						// reg_rd_num0 & 1 will get updated. So as reg_rd_data0 & 1. Which one first!!?
					pc <= pc + 4;
					state <= id;
				end
				id: begin								// Set up variable for calculation
//					if (ir[31:26] == 6'b001001) begin	// reg_rd_data0 & 1 is available?? --- Assume yes now
//						a <= reg_rd_data0;				// Set up b if needed. data_out will get assign to b (Can be done in next step too)
//					end else if (ir[31:26] == 6'b101011) begin
//						b <= reg_rd_data1;
//						a <= reg_rd_data0;
//					end else if (ir[31:26] == 6'b100011) begin		//lw
//						a <= reg_rd_data0;
//					end else if (ir[31:26] == 6'b000000) begin
//						if (ir[5:0] == 6'b100001) begin
//							a <= reg_rd_data0;
//							b <= reg_rd_data1;
//						end else if (ir[5:0] == 6'b001000) begin
//							ir[25:21] <= 5'b11111;
//							a <= reg_rd_data0;
//						end else if (ir[25:0] == 0) begin
//							a <= reg_rd_data0;
//							b <= reg_rd_data1;
//						end
//					end

					// Set up variable for calculation
					// reg_rd_data0 & 1 is available?? --- Assume yes now
					// Set up b if needed. data_out will get assign to b (Can be done in next step too)
					if ((ir[31:26] == 6'b000000) && (ir[5:0] == 6'b001000)) begin
						ir[25:21] <= 5'b11111;
						a <= reg_rd_data0;
					end else begin
						a <= reg_rd_data0;
						b <= reg_rd_data1;
					end
					sign_ext_imm <= {{16{ir[15]}},ir[15:0]};
					state <= ex;
				end
				ex: begin								// Address calculation, Value calculation etc
					if (ir[31:26] == 6'b001001) begin	// Set st_en, data_addr, data_out (this is set by b already) so Data get written or read
						alu_out <= a + sign_ext_imm;
						st_en <= 0;
					end else if (ir[31:26] == 6'b101011) begin
						st_en <= 1;
						data_addr <= a + sign_ext_imm;
						b <= reg_rd_data1;
					end else if (ir[31:26] == 6'b100011) begin
						st_en <= 0;
						data_addr <= a + sign_ext_imm;
					end else if (ir[31:26] == 6'b000000) begin
						if (ir[5:0] == 6'b100001) begin
							st_en <= 0;
							alu_out <= a + b;
						end else if (ir[5:0] == 6'b001000) begin
							st_en <= 0;		// Do I write to the register that hold return address or just simply modify return address??
							a <= reg_rd_data0;	// assigned again because reg_rd_data0 return the value in register 31 now
						end else if (ir[25:0] == 0) begin
							st_en <= 0;
						end
					end
					state <= me;
				end
				me: begin								// enable reg_wr_* as needed so that registers will get updated 
					if (ir[31:26] == 6'b001001) begin
						reg_wr_en <= 1;
						reg_wr_num <= ir[20:16];
						//reg_wr_data <= alu_out;
					end else if (ir[31:26] == 6'b101011) begin
						reg_wr_en <= 0;
						reg_wr_num <= 0;
					end else if (ir[31:26] == 6'b100011) begin
						reg_wr_en <= 1;
						reg_wr_num <= ir[20:16];
						//reg_wr_data <= data_in;
						lw <= 0;	// Decide what reg_wr_data is going to take in
					end else if (ir[31:26] == 6'b000000) begin
						if (ir[5:0] == 6'b100001) begin
							reg_wr_en <= 1;
							reg_wr_num <= ir[15:11];
							//reg_wr_data <= alu_out;
						end else if (ir[5:0] == 6'b001000) begin
							reg_wr_en <= 0;
							reg_wr_num <= 0;
							pc <= a;	// This??			--		For now, I'm setting a to be register 31
						end else if (ir[25:0] == 0) begin
							reg_wr_en <= 0;
							reg_wr_num <= 0;
						end
					end
					st_en <= 0;
					state <= wb;
				end
				wb: begin
					lw <= 1;		// Reset the lw
					reg_wr_en <= 0;
					state <= fetch;
				end
				default: begin
					reg_wr_en <= 0;
					state <= fetch;
				end
			endcase
	end

endmodule
