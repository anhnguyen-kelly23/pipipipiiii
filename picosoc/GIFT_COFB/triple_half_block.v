module triple_half_block (
    input  [63:0] s,
    output [63:0] d
);
    wire [63:0] tmp;
    double_half_block u_double (
        .s(s),
        .d(tmp)
    );
    assign d = s ^ tmp;
endmodule
