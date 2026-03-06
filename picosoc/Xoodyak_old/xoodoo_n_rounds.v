//--------------------------------------------------------------------------------
// N rounds computation module
// Uses Verilog generate to instantiate configurable number of rounds
// roundPerCycle parameter controls unrolling (1, 2, 3, 4, 6, or 12)
//--------------------------------------------------------------------------------
module xoodoo_n_rounds(
    state_in,
    state_out,
    rc_state_in,
    rc_state_out
);
    parameter roundPerCycle = 3;
    
    input  [383:0] state_in;
    output [383:0] state_out;
    input  [5:0]   rc_state_in;
    output [5:0]   rc_state_out;
    
    // Internal wires for chaining rounds (roundPerCycle + 1 entries)
    wire [383:0] state_chain [0:roundPerCycle];
    wire [5:0]   rc_chain [0:roundPerCycle];
    wire [31:0]  rc_val [0:roundPerCycle-1];
    
    // Connect inputs to first chain element
    assign state_chain[0] = state_in;
    assign rc_chain[0] = rc_state_in;
    
    // Generate N rounds dynamically based on roundPerCycle parameter
    genvar i;
    generate
        for (i = 0; i < roundPerCycle; i = i + 1) begin : round_gen
            // Round constant generator
            xoodoo_rc rc_inst(
                .state_in(rc_chain[i]),
                .state_out(rc_chain[i+1]),
                .rc(rc_val[i])
            );
            
            // Round computation
            xoodoo_round round_inst(
                .state_in(state_chain[i]),
                .rc(rc_val[i]),
                .state_out(state_chain[i+1])
            );
        end
    endgenerate
    
    // Connect outputs from last chain element
    assign state_out = state_chain[roundPerCycle];
    assign rc_state_out = rc_chain[roundPerCycle];
    
endmodule

