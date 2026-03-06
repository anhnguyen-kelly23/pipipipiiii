// ============================================================
// GIFT-128 Round Datapath
// ============================================================
module gift128_round (
    input  wire [31:0] S0,S1,S2,S3,
    input  wire [15:0] W0,W1,W2,W3,W4,W5,W6,W7,
    input  wire [7:0]  RC,
    output wire [31:0] N0,N1,N2,N3,
    output wire [15:0] K0,K1,K2,K3,K4,K5,K6,K7
);
    wire [31:0] a0,a1,a2,a3;
    wire [31:0] b0,b1,b2,b3;
    wire [31:0] c1,c2,c3;

    gift128_subcells u_sub (S0,S1,S2,S3,a0,a1,a2,a3);
    gift128_permbits u_perm (a0,a1,a2,a3,b0,b1,b2,b3);
    gift128_addroundkey u_ark (b1,b2,W2,W3,W6,W7,c1,c2);
    gift128_roundconst u_rc (b3,RC,c3);
    gift128_keyschedule u_key (W0,W1,W2,W3,W4,W5,W6,W7,
                               K0,K1,K2,K3,K4,K5,K6,K7);

    assign N0 = b0;
    assign N1 = c1;
    assign N2 = c2;
    assign N3 = c3;
endmodule
