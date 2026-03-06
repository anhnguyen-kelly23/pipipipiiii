//--------------------------------------------------------------------------------
// Round constant computation module
// Matches xoodoo_rc.vhd functionality
//--------------------------------------------------------------------------------
module xoodoo_rc(
    state_in,
    state_out,
    rc
);
    input  [5:0] state_in;
    output [5:0] state_out;
    output [31:0] rc;
    
    wire [2:0] si;
    wire [3:0] temp_new_si;
    wire [2:0] new_si;
    wire [2:0] qi;
    wire [2:0] new_qi;
    wire [3:0] qi_plus_t3;
    
    assign si = state_in[2:0];
    assign temp_new_si = {1'b0, si} + {si[1:0], si[2]};
    assign new_si = temp_new_si[2:0] + {2'b0, temp_new_si[3]};
    assign state_out[2:0] = new_si;
    
    assign qi = state_in[5:3];
    assign new_qi[0] = qi[2];
    assign new_qi[1] = qi[0] ^ qi[2];
    assign new_qi[2] = qi[1];
    assign state_out[5:3] = new_qi;
    
    assign qi_plus_t3 = {1'b1, qi};
    
    // RC value computation based on si
    // VHDL: rc(0) is LSB, rc(9) is MSB of rc[9:0]
    // For si="001": rc(0)=0, rc(1)=qi_plus_t3(0), rc(2)=qi_plus_t3(1), 
    //               rc(3)=qi_plus_t3(2), rc(4)=qi_plus_t3(3), rc(9:5)=0
    // In Verilog: rc[0]=LSB, rc[9]=MSB
    // So rc[9:0] = {rc[9], rc[8], ..., rc[1], rc[0]} = {5'b0, qi_plus_t3[3], qi_plus_t3[2], qi_plus_t3[1], qi_plus_t3[0], 1'b0}
    assign rc[31:10] = 22'h0;
    assign rc[9:0] = (si == 3'b001) ? {5'b0, qi_plus_t3[3], qi_plus_t3[2], qi_plus_t3[1], qi_plus_t3[0], 1'b0} :
                     (si == 3'b010) ? {4'b0, qi_plus_t3[3], qi_plus_t3[2], qi_plus_t3[1], qi_plus_t3[0], 2'b0} :
                     (si == 3'b011) ? {3'b0, qi_plus_t3[3], qi_plus_t3[2], qi_plus_t3[1], qi_plus_t3[0], 3'b0} :
                     (si == 3'b100) ? {2'b0, qi_plus_t3[3], qi_plus_t3[2], qi_plus_t3[1], qi_plus_t3[0], 4'b0} :
                     (si == 3'b101) ? {1'b0, qi_plus_t3[3], qi_plus_t3[2], qi_plus_t3[1], qi_plus_t3[0], 5'b0} :
                     (si == 3'b110) ? {qi_plus_t3[3], qi_plus_t3[2], qi_plus_t3[1], qi_plus_t3[0], 6'b0} :
                     10'b0;
    
endmodule

