module pho1 (
    input  [127:0] Y_in,         // chaining value in
    input  [127:0] M_in,         // message / plaintext block
    input  [4:0]   no_of_bytes,  // valid bytes in M
    output [127:0] d        
);

    wire [127:0] G_result;
    wire [127:0] M_padded;
    wire [127:0] tmpM;
    	feedback_G g_inst (
        	.Y_in  (Y_in),
        	.G_out (G_result)
    	);

    	padding pad_inst (
        	.data_in   (M_in),
        	.num_bytes (no_of_bytes),
        	.data_out  (M_padded)
    	);

	xor_block xor_inst (
		.s1(G_result),
		.s2(M_padded),
		.no_of_bytes(5'd16),
		.d(d)
	);
endmodule
