// ============================================================
// GIFT-128 Key Schedule
// ============================================================
module gift128_keyschedule (
    input  wire [15:0] W0, W1, W2, W3, W4, W5, W6, W7,
    output wire [15:0] N0, N1, N2, N3, N4, N5, N6, N7
);
    assign N0 = {W6[1:0],  W6[15:2]};   // ROR2
    assign N1 = {W7[11:0], W7[15:12]};  // ROR12
    assign N2 = W0;
    assign N3 = W1;
    assign N4 = W2;
    assign N5 = W3;
    assign N6 = W4;
    assign N7 = W5;
endmodule
