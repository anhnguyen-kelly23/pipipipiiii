//--------------------------------------------------------------------------------
// Xoodoo permutation with configurable rounds per cycle
// Matches functionality of xoodoo.vhd
//--------------------------------------------------------------------------------

module xoodoo(
    clk_i,
    rst_i,
    start_i,
    state_valid_o,
    init_reg,
    word_in,
    word_index_in,
    word_enable_in,
    domain_i,
    domain_enable_i,
    word_out
);
    // Port declarations
    input               clk_i;
    input               rst_i;
    input               start_i;
    output reg          state_valid_o;
    input               init_reg;
    input      [31:0]   word_in;
    input      [3:0]    word_index_in;  // 0 to 11
    input               word_enable_in;
    input      [31:0]   domain_i;
    input               domain_enable_i;
    output     [31:0]   word_out;

    // Parameters
    parameter roundPerCycle = 3;
    parameter active_rst = 1'b1;

    // Internal state representation: 3 planes x 4 words x 32 bits = 384 bits
    // State layout: state[plane][word] where plane=0..2, word=0..3
    // Packed representation: [383:0] = [plane2, plane1, plane0]
    // Word at plane y, word x is at bit position: 128*y + 32*x + bit
    reg  [383:0] reg_value;
    wire [383:0] round_in_state;
    wire [383:0] round_out_state;
    
    // Round constant state machine (6 bits)
    reg  [5:0]  rc_state_in;
    wire [5:0]  rc_state_out;
    
    // Control signals
    reg         done;
    reg         running;
    
    // Compute state with XOR applied (combinational)
    // This ensures XOR inputs are applied before permutation
    wire [383:0] state_with_xor;
    
    genvar i;
    generate
        for (i = 0; i < 12; i = i + 1) begin : gen_word_xor
            assign state_with_xor[i*32 +: 32] = 
                reg_value[i*32 +: 32] ^
                ((word_enable_in == 1'b1 && word_index_in == i) ? word_in : 32'h0) ^
                ((i == 11 && domain_enable_i == 1'b1) ? domain_i : 32'h0);
        end
    endgenerate
    
    // N rounds computation module (uses state with XOR applied)
    xoodoo_n_rounds #(.roundPerCycle(roundPerCycle)) rounds_inst(
        .state_in(state_with_xor),
        .state_out(round_out_state),
        .rc_state_in(rc_state_in),
        .rc_state_out(rc_state_out)
    );
    
    // State register: simplified to just update from round output or XORed state
    always @(posedge clk_i) begin
        if (rst_i == active_rst) begin
            // Reset all state to zero
            reg_value <= 384'h0;
        end else begin
            if (init_reg == 1'b1) begin
                // Initialize all state to zero
                reg_value <= 384'h0;
            end else if (running == 1'b1 || start_i == 1'b1) begin
                // Update state from round output (which is based on state_with_xor)
                reg_value <= round_out_state;
            end else begin
                // Apply XOR when idle (not running and not starting)
                reg_value <= state_with_xor;
            end
        end
    end
    
    // Word output: read from register
    assign word_out = reg_value[word_index_in*32 +: 32];
    
    // Main FSM controller
    always @(posedge clk_i) begin
        if (rst_i == active_rst) begin
            done <= 1'b0;
            running <= 1'b0;
            rc_state_in <= 6'b011011;  // Initial RC state
            state_valid_o <= 1'b0;
        end else begin
            // Check if permutation is complete (RC state = "010011")
            if (rc_state_out == 6'b010011) begin
                done <= 1'b1;
                running <= 1'b0;
                rc_state_in <= 6'b011011;  // Reset RC state for next permutation
                state_valid_o <= 1'b1;
            end else if (start_i == 1'b1) begin
                // Start new permutation: clear valid signal
                done <= 1'b0;
                running <= 1'b1;
                rc_state_in <= rc_state_out;
                state_valid_o <= 1'b0;
            end else if (running == 1'b1) begin
                // Permutation in progress: keep valid low
                done <= 1'b0;
                running <= 1'b1;
                rc_state_in <= rc_state_out;
                state_valid_o <= 1'b0;
            end else begin
                // Not running and not complete: keep state_valid_o as is (stays high until next start)
                // This preserves state_valid_o when permutation is done
                state_valid_o <= state_valid_o;
            end
        end
    end
    
endmodule

