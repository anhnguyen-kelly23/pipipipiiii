//--------------------------------------------------------------------------------
// Single round computation module
// Matches xoodoo_round.vhd functionality
// Uses flattened 384-bit vectors for Verilog compatibility
//--------------------------------------------------------------------------------
module xoodoo_round(
    state_in,
    rc,
    state_out
);
    input  [383:0] state_in;
    input  [31:0]  rc;
    output [383:0] state_out;
    
    // Internal arrays for computation
    reg  [31:0] state_array [0:2][0:3];
    reg  [31:0] theta_out [0:2][0:3];
    reg  [31:0] rho_w_out [0:2][0:3];
    reg  [31:0] iota_out [0:2][0:3];
    reg  [31:0] chi_out [0:2][0:3];
    reg  [31:0] rho_e_out [0:2][0:3];
    
    // Theta step: parity and diffusion
    reg  [31:0] P [0:3];
    reg  [31:0] E [0:3];
    integer x, y;
    
    // Unpack input state
    always @(*) begin
        for (y = 0; y < 3; y = y + 1)
            for (x = 0; x < 4; x = x + 1)
                state_array[y][x] = state_in[128*y + 32*x +: 32];
    end
    
    // Theta: compute parity
    always @(*) begin
        for (x = 0; x < 4; x = x + 1)
            P[x] = state_array[0][x] ^ state_array[1][x] ^ state_array[2][x];
    end
    
    // Theta: compute E[x] = rotl(P[x-1], 5) XOR rotl(P[x-1], 14)
    function [31:0] rotl32;
        input [31:0] val;
        input [4:0]  shift;
        begin
            rotl32 = (val << shift) | (val >> (32 - shift));
        end
    endfunction

    always @(*) begin
        for (x = 0; x < 4; x = x + 1) begin
            E[x] = rotl32(P[(x+3) % 4], 5) ^ rotl32(P[(x+3) % 4], 14);
        end
    end
    
    // Theta: apply E
    always @(*) begin
            for (y = 0; y < 3; y = y + 1)
            for (x = 0; x < 4; x = x + 1)
                theta_out[y][x] = state_array[y][x] ^ E[x];
    end
    
    // Rho west
    always @(*) begin
            for (x = 0; x < 4; x = x + 1) begin
            rho_w_out[0][x] = theta_out[0][x];
            rho_w_out[1][x] = theta_out[1][(x+3) % 4];
            rho_w_out[2][x] = rotl32(theta_out[2][x], 11);
        end
    end
    
    // Iota: add round constant
    always @(*) begin
        for (y = 0; y < 3; y = y + 1)
            for (x = 0; x < 4; x = x + 1)
                if (y == 0 && x == 0)
                    iota_out[y][x] = rho_w_out[y][x] ^ rc;
                else
                    iota_out[y][x] = rho_w_out[y][x];
    end
    
    // Chi: non-linear layer
    reg [31:0] B0, B1, B2;
    always @(*) begin
        for (x = 0; x < 4; x = x + 1) begin
            B0 = (~iota_out[1][x]) & iota_out[2][x];
            B1 = (~iota_out[2][x]) & iota_out[0][x];
            B2 = (~iota_out[0][x]) & iota_out[1][x];
            chi_out[0][x] = iota_out[0][x] ^ B0;
            chi_out[1][x] = iota_out[1][x] ^ B1;
            chi_out[2][x] = iota_out[2][x] ^ B2;
        end
    end
    
    // Rho east
    always @(*) begin
        for (x = 0; x < 4; x = x + 1) begin
            rho_e_out[0][x] = chi_out[0][x];
            rho_e_out[1][x] = rotl32(chi_out[1][x], 1);
            rho_e_out[2][x] = rotl32(chi_out[2][(x+2) % 4], 8);
        end
    end
    
    // Pack output state - use internal reg then assign to output wire
    reg [383:0] state_out_reg;
    always @(*) begin
        for (y = 0; y < 3; y = y + 1)
            for (x = 0; x < 4; x = x + 1)
                state_out_reg[128*y + 32*x +: 32] = rho_e_out[y][x];
    end
    
    // Assign internal reg to output wire
    assign state_out = state_out_reg;
    
endmodule

