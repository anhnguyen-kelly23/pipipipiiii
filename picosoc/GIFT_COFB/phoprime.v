module phoprime (
    input  [127:0] Y,
    input  [127:0] C,
    input  [4:0]   no_of_bytes,
    output [127:0] M,
    output [127:0] X
);
    xor_block xor_inst (
        .s1(Y),
        .s2(C),
        .no_of_bytes(no_of_bytes),
        .d(M)
    );
    pho1 pho1_inst (
        .Y_in(Y),
        .M_in(M),
        .no_of_bytes(no_of_bytes),
        .d(X)
    );
endmodule
