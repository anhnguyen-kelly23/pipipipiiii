// ============================================================
// GIFT-128 AddRoundKey
// ============================================================
module gift128_addroundkey (
    input  wire [31:0] S1,
    input  wire [31:0] S2,
    input  wire [15:0] W2,
    input  wire [15:0] W3,
    input  wire [15:0] W6,
    input  wire [15:0] W7,
    output wire [31:0] Z1,
    output wire [31:0] Z2
);
    assign Z2 = S2 ^ {W2, W3};
    assign Z1 = S1 ^ {W6, W7};
endmodule
