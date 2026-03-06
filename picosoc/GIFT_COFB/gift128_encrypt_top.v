// ============================================================
// GIFT-128 Encrypt TOP
// - 40 rounds
// - 1 round / cycle
// ============================================================
module gift128_encrypt_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,
    input  wire [127:0] plaintext,
    input  wire [127:0] key,

    output reg         busy,
    output reg         done,
    output reg  [127:0] ciphertext
);

    // --------------------------------------------------------
    // State registers
    // --------------------------------------------------------
    reg [31:0] S0, S1, S2, S3;
    reg [15:0] W0, W1, W2, W3, W4, W5, W6, W7;

    reg [5:0] round;

    // --------------------------------------------------------
    // Round constant ROM
    // --------------------------------------------------------
    reg [7:0] RC;
    always @(*) begin
        case (round)
            6'd0:  RC = 8'h01;  6'd1:  RC = 8'h03;
            6'd2:  RC = 8'h07;  6'd3:  RC = 8'h0F;
            6'd4:  RC = 8'h1F;  6'd5:  RC = 8'h3E;
            6'd6:  RC = 8'h3D;  6'd7:  RC = 8'h3B;
            6'd8:  RC = 8'h37;  6'd9:  RC = 8'h2F;
            6'd10: RC = 8'h1E;  6'd11: RC = 8'h3C;
            6'd12: RC = 8'h39;  6'd13: RC = 8'h33;
            6'd14: RC = 8'h27;  6'd15: RC = 8'h0E;
            6'd16: RC = 8'h1D;  6'd17: RC = 8'h3A;
            6'd18: RC = 8'h35;  6'd19: RC = 8'h2B;
            6'd20: RC = 8'h16;  6'd21: RC = 8'h2C;
            6'd22: RC = 8'h18;  6'd23: RC = 8'h30;
            6'd24: RC = 8'h21;  6'd25: RC = 8'h02;
            6'd26: RC = 8'h05;  6'd27: RC = 8'h0B;
            6'd28: RC = 8'h17;  6'd29: RC = 8'h2E;
            6'd30: RC = 8'h1C;  6'd31: RC = 8'h38;
            6'd32: RC = 8'h31;  6'd33: RC = 8'h23;
            6'd34: RC = 8'h06;  6'd35: RC = 8'h0D;
            6'd36: RC = 8'h1B;  6'd37: RC = 8'h36;
            6'd38: RC = 8'h2D;  6'd39: RC = 8'h1A;
            default: RC = 8'h00;
        endcase
    end

    // --------------------------------------------------------
    // Round datapath
    // --------------------------------------------------------
    wire [31:0] nS0, nS1, nS2, nS3;
    wire [15:0] nW0, nW1, nW2, nW3, nW4, nW5, nW6, nW7;

    gift128_round u_round (
        .S0(S0), .S1(S1), .S2(S2), .S3(S3),
        .W0(W0), .W1(W1), .W2(W2), .W3(W3),
        .W4(W4), .W5(W5), .W6(W6), .W7(W7),
        .RC(RC),
        .N0(nS0), .N1(nS1), .N2(nS2), .N3(nS3),
        .K0(nW0), .K1(nW1), .K2(nW2), .K3(nW3),
        .K4(nW4), .K5(nW5), .K6(nW6), .K7(nW7)
    );

    // --------------------------------------------------------
    // FSM / registers
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy  <= 1'b0;
            done  <= 1'b0;
            round <= 6'd0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                // load plaintext (big-endian)
                S0 <= plaintext[127:96];
                S1 <= plaintext[ 95:64];
                S2 <= plaintext[ 63:32];
                S3 <= plaintext[ 31: 0];

                // load key
                W0 <= key[127:112];
                W1 <= key[111:96];
                W2 <= key[ 95:80];
                W3 <= key[ 79:64];
                W4 <= key[ 63:48];
                W5 <= key[ 47:32];
                W6 <= key[ 31:16];
                W7 <= key[ 15: 0];

                round <= 6'd0;
                busy  <= 1'b1;
            end
            else if (busy) begin
                S0 <= nS0; S1 <= nS1; S2 <= nS2; S3 <= nS3;
                W0 <= nW0; W1 <= nW1; W2 <= nW2; W3 <= nW3;
                W4 <= nW4; W5 <= nW5; W6 <= nW6; W7 <= nW7;

                if (round == 6'd39) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    ciphertext <= {nS0, nS1, nS2, nS3};
                end

                round <= round + 6'd1;
            end
        end
    end

endmodule
