module feedback_G (
    input  [127:0] Y_in,
    output [127:0] G_out
);
    wire [63:0] Y1 = Y_in[127:64];  // Y[1] - Upper half
    wire [63:0] Y2 = Y_in[63:0];    // Y[2] - Lower half
    
    // G(Y) = Y[2] || (Y[1] <<< 1)
    assign G_out = {Y2, {Y1[62:0], Y1[63]}};
    
endmodule