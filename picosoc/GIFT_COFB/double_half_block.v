module double_half_block (
    input  [63:0] s,      
    output [63:0] d       
); 
    wire msb;             
    wire [63:0] shifted;  
    wire [7:0] reduction; 
    
    assign msb = s[63];
    assign shifted = s << 1;
    assign reduction = msb ? 8'h1B : 8'h00; // 1b = 27 ( 0001_1011)
    assign d = {shifted[63:8], shifted[7:0] ^ reduction};

endmodule
