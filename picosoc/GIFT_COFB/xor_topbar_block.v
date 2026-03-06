module xor_topbar_block (
    input  [127:0] s1,      // Input block (128-bit)
    input  [63:0]  s2,      // Half block (64-bit) - top bar
    output [127:0] d        // Output block (128-bit)
);
    assign d = {s1[127:64] ^ s2, s1[63:0]};

endmodule
