// ****************************************************************************
// Filename: map_table.v
// Discription: Map table
//				Three cases: 1.	Dispatch
//								Read out the tags(pregs) of two oprands' aregs and dest
//								areg. Write in new preg to the index of the dest areg. 
//								*Notice that the ready bit outputs of two oprands
//								should catch what CDB braodcasts at the same
//								cycle.
//							 2.	CDB broadcast
//								If corresponding preg is found, change its ready
//								bit to 1.
//							 3. Early branch single cycle recovery
//								Map table maintains some checkpoint copies. It
//								will be flushed back when branch prediction is
//								wrong by manipulating these copies.
// Author: Chuan Cen
// Version History:
// 	intial creation: 10/17/2017
// 	***************************************************************************
//
typedef enum {NORMAL, ROLLBACK} STATE;	

`define DEBUG
`define BR_DEPTH 5
`define LG_BR_DEPTH 3	// >= log2(BR_DEPTH)

module map_table(
		input					clk,
		input					rst,						//|From where|									
		input	[4:0]			opa_areg_idx_i,				//[Decoder]		A logic register index to read the physical register name and ready bit of oprand A from map table.
		input	[4:0]			opb_areg_idx_i,				//[Decoder]		A logic register index to read the physical register name and ready bit of oprand B from map table.
		input	[4:0]			dest_areg_idx_i,			//[Decoder]		A logic register index to read the old dest physical reg, and to write a new dest physical reg.
		input	[5:0]			new_free_preg_i,			//[Free-List]	New physical register name from Free List.
		input					dispatch_en_i,				//[Decoder]		Enabling all inputs above. 
		input	[5:0]			cdb_set_rdy_bit_preg_i,		//[CDB]			A physical reg from CDB to set ready bit of corresponding logic reg in map table.
		input					cdb_set_rdy_bit_en_i,		//[CDB]			Enabling setting ready bit. 
		input	[BR_DEPTH-1:0]	br_valid_arr_i,				//[BTST]		If 0 then dynamicly update
		input	[BR_DEPTH-1:0]	br_ygr_arr_i,				//[BTST]		If 1 then ygr than wrong branch
		input	[BR_DEPTH-1:0]	br_tag_i,					//[ROB]			Relevant branch tag 00001/00010/00100/01000/10000		
		input					br_wrong_i,					//[ROB]			Is branch predit wrong?
		//input					br_correct_i,				//[ROB]			Predit correct?

	
		`ifdef DEBUG
			input	[4:0]		read_idx_i,					// Check the original map table only. 
			output	[5:0]		read_preg_o,
			output				read_rdy_bit_o,
			output				cdb_match_fd,
		`endif
															//|To where|
		output	[5:0]			opa_preg_o,					//[RS]			Oprand A physical reg output.
		output	[5:0]			opb_preg_o,					//[RS]			Oprand B physical reg output.
		output		 			opa_preg_rdy_bit_o,			//[RS]			Oprand A physical reg ready bit output. 
		output		 			opb_preg_rdy_bit_o,			//[RS]			Oprand B physical reg ready bit output.
		output	[5:0]			dest_old_preg_o				//[ROB]			Old dest physical reg output. 
		);

		logic	[BR_DEPTH:0][31:0][5:0]		MAP;			//MAP[0] is the original MAP. MAP[1] is the first copy and so on.
		logic	[BR_DEPTH:0][31:0]			RDY;			//RDY[0] is the original RDY. RDY[1] is the first copy and so on.
		logic	[BR_DEPTH:0][31:0][5:0]		next_MAP;		//Next MAP values
		logic	[BR_DEPTH:0][31:0]			next_RDY;		//Next RDY values

		logic	[4:0]			cdb_match_index;
		logic					cdb_match_found;
	
		logic [BR_DEPTH:0]	valid_arr;
		logic [BR_DEPTH:0]	ygr_arr;
		logic  [LG_BR_DEPTH:0] wrong_idx;
	
		STATE state;
	
		`ifdef DEBUG
			assign read_preg_o = MAP[0][read_idx_i];
			assign read_rdy_bit_o = RDY[0][read_idx_i];
			assign cdb_match_fd = cdb_match_found;
		`endif
	
		assign valid_arr = {br_valid_arr_i, 1'b1};		// Concatenate copies and original bits.
		assign ygr_arr = {br_ygr_arr_i, 1'b1};

		assign opa_preg_o = dispatch_en_i ? MAP[0][opa_areg_idx_i]: 6'b000000;		// Always use original map table here. Copies only for dealing with branch issues.
		assign opb_preg_o = dispatch_en_i ? MAP[0][opb_areg_idx_i]: 6'b000000;
		assign opa_preg_rdy_bit_o = dispatch_en_i ? cdb_match_index==opa_areg_idx_i ? 1 : RDY[0][opa_areg_idx_i] : 0;
		assign opb_preg_rdy_bit_o = dispatch_en_i ? cdb_match_index==opb_areg_idx_i ? 1 : RDY[0][opb_areg_idx_i] : 0;
		assign dest_old_preg_o = dispatch_en_i ? MAP[0][dest_areg_idx_i] : 6'b000000;
		
		assign state = br_wrong_i ? ROLLBACK : NORMAL; 	// Two different situations. 

		always_comb begin	// Find the index of wrong branch.
			for(int i=0;i<BR_DEPTH;i++) begin
				if (br_tag_i[i] == 1'b1) begin
					wrong_idx = i+1;		// Offset is 1 because the array is concatenated with original one. 
					break;
				end
			end
		end

		always_comb begin	// Here we make the next_MAP/RDY ready for sequential assignments.
			case(state)
				NORMAL:
				begin
				if (cdb_set_rdy_bit_en_i && cdb_match_found) begin
					for (int j=0;j<BR_DEPTH+1;j++) begin
						if (valid_arr[j] == 0) begin
							for (int i=0; i<32; i++) begin
								if (i==cdb_match_index) begin
									next_RDY[j][i] = 1;
								end else begin
									next_RDY[j][i] = RDY[0][i];   // Accordant with the origin.
								end
							end
						end else begin
							for (int i=0; i<32; i++) begin
								next_RDY[j][i] = RDY[j][i];		// Fixed. Maintain unchanged.
							end
						end
					end
				end else begin
				end
				if (dispatch_en_i) begin
					for (int j=0;j<BR_DEPTH+1;j++) begin
						if (valid_arr[j] == 0) begin
							for (int i=0; i<32; i++) begin
								if (i==dest_areg_idx_i) begin
									next_MAP[j][dest_areg_idx_i] = new_free_preg_i;
									next_RDY[j][dest_areg_idx_i] = 0;
								end else begin
									next_MAP[j][i] = MAP[0][i];		// Accordant with the origin.
									next_RDY[j][i] = RDY[0][i];
								end
							end
						end else begin
							next_MAP[j][i] = MAP[j][i];		// Fixed. Maintain unchanged.
							next_RDY[j][i] = RDY[j][i];
						end
					end
				end else begin
				end

				end
				ROLLBACK:
				begin
					for (int j=0;j<BR_DEPTH+1;j++) begin
						if (ygr_arr[j] == 1) begin
							for (int i=0; i<32; i++) begin
								next_MAP[j][i] = MAP[wrong_idx][i];		// Assigned by the wrong copy
								next_RDY[j][i] = RDY[wrong_idx][i];
							end
						end else begin
							for (int i=0; i<32; i++) begin
								next_MAP[j][i] = MAP[j][i];		// Maintain in this cycle. No other operation (like dispatch or something) allowed. 
								next_RDY[j][i] = RDY[j][i];
							end
						end
					end		
				end
				default:
			endcase
		end

		always_comb begin					// Find index by cdb's tag
			cdb_match_index = 0;
			cdb_match_found = 0;
			if(cdb_set_rdy_bit_en_i) begin
				for (int i=0;i<32;i++) begin
					if (MAP[0][i] == cdb_set_rdy_bit_preg_i) begin
						cdb_match_index = i;
						cdb_match_found = 1;
						break;
					end
				end
			end
		end

		always_ff@(posedge clk) begin								// Use for loop going over through every registers to make sequential assignments
			if (rst) begin
				for (int j=0;j<BR_DEPTH+1;j++) begin
					for (int i=0; i<32; i++) begin
						MAP[j][i] <= `SD i;
						RDY[j][i] <= `SD 1;
					end
				end
			end else begin
				for (int j=0;j<BR_DEPTH+1;j++) begin
					for (int i=0; i<32; i++) begin
						MAP[j][i] <= `SD next_MAP[j][i];
						RDY[j][i] <= `SD next_RDY[j][i];
					end
				end
			end
		end
		
endmodule