// ============================================================
// GIFT-128 Round Constant
// ============================================================
module gift128_roundconst (
    input  wire [31:0] S3,
    input  wire [7:0]  RC,
    output wire [31:0] Z3
);
    assign Z3 = S3 ^ 32'h80000000 ^ {24'b0, RC};
endmodule
