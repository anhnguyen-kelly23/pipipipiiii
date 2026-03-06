module padding (
    input  [127:0] data_in,      
    input  [4:0]   num_bytes,    // Number of valid bytes (0-16) --> 2^5 =32 
    output [127:0] data_out      
);

    reg [127:0] padded_data;
    
    always @(*) begin
        case (num_bytes)
            5'd0: begin
                padded_data = 128'h80000000000000000000000000000000;
            end
            5'd1: begin
                padded_data = {data_in[127:120], 1'b1, 119'b0};
            end
            5'd2: begin
                padded_data = {data_in[127:112], 1'b1, 111'b0};
            end
            5'd3: begin
                padded_data = {data_in[127:104], 1'b1, 103'b0};
            end
            5'd4: begin
                padded_data = {data_in[127:96], 1'b1, 95'b0};
            end
            5'd5: begin
                padded_data = {data_in[127:88], 1'b1, 87'b0};
            end
            5'd6: begin
                padded_data = {data_in[127:80], 1'b1, 79'b0};
            end
            5'd7: begin
                padded_data = {data_in[127:72], 1'b1, 71'b0};
            end
            5'd8: begin
                padded_data = {data_in[127:64], 1'b1, 63'b0};
            end
            5'd9: begin
                padded_data = {data_in[127:56], 1'b1, 55'b0};
            end
            5'd10: begin
                padded_data = {data_in[127:48], 1'b1, 47'b0};
            end
            5'd11: begin
                padded_data = {data_in[127:40], 1'b1, 39'b0};
            end
            5'd12: begin
                padded_data = {data_in[127:32], 1'b1, 31'b0};
            end
            5'd13: begin
                padded_data = {data_in[127:24], 1'b1, 23'b0};
            end
            5'd14: begin
                padded_data = {data_in[127:16], 1'b1, 15'b0};
            end          
            5'd15: begin
                padded_data = {data_in[127:8], 1'b1, 7'b0};
            end            
            5'd16: begin
                padded_data = data_in;
            end           
            default: begin
                padded_data = 128'h0;
            end
        endcase
    end  
    assign data_out = padded_data;

endmodule