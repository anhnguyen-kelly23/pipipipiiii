module xor_block (
    input  [127:0] s1,           // input block s1
    input  [127:0] s2,           // input block s2
    input  [4:0]   no_of_bytes,  
    output [127:0] d              // output block
);
    reg [127:0] result;
    always @(*) begin
        case (no_of_bytes) 
            5'd0:
                result = 128'b0;
            5'd1:
                result = { s1[127:120] ^ s2[127:120], 120'b0 };
            5'd2:
                result = { s1[127:112] ^ s2[127:112], 112'b0 };
            5'd3:
                result = { s1[127:104] ^ s2[127:104], 104'b0 };
            5'd4:
                result = { s1[127:96] ^ s2[127:96], 96'b0 };
            5'd5:
                result = { s1[127:88] ^ s2[127:88], 88'b0 };
            5'd6:
                result = { s1[127:80] ^ s2[127:80], 80'b0 };
            5'd7:
                result = { s1[127:72] ^ s2[127:72], 72'b0 };
            5'd8:
                result = { s1[127:64] ^ s2[127:64], 64'b0 };
            5'd9:
                result = { s1[127:56] ^ s2[127:56], 56'b0 };
            5'd10:
                result = { s1[127:48] ^ s2[127:48], 48'b0 };
            5'd11:
                result = { s1[127:40] ^ s2[127:40], 40'b0 };
            5'd12:
                result = { s1[127:32] ^ s2[127:32], 32'b0 };
            5'd13:
                result = { s1[127:24] ^ s2[127:24], 24'b0 };
            5'd14:
                result = { s1[127:16] ^ s2[127:16], 16'b0 };
            5'd15:
                result = { s1[127:8] ^ s2[127:8], 8'b0 };
            5'd16:
                result = s1 ^ s2;
            default:
                result = 128'b0;
        endcase
    end
    assign d = result;

endmodule

