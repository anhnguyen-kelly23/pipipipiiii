`timescale 1ns / 1ps

module ram_arbiter(

    input clk,

    input boot_phase,

    // bootloader port
    input [31:0] boot_addr,
    input [7:0]  boot_wdata,
    input        boot_we,

    // CPU port
    input [31:0] cpu_addr,
    input [31:0] cpu_wdata,
    input [3:0]  cpu_wstrb,

    // RAM port
    output reg [31:0] ram_addr,
    output reg [31:0] ram_wdata,
    output reg [3:0]  ram_wstrb
);

always @(*) begin

    if(boot_phase) begin

        ram_addr  = {boot_addr[31:2], 2'b00};  // word-aligned

        case(boot_addr[1:0])
            2'b00: begin ram_wdata = {24'b0, boot_wdata};        ram_wstrb = boot_we ? 4'b0001 : 4'b0000; end
            2'b01: begin ram_wdata = {16'b0, boot_wdata,  8'b0}; ram_wstrb = boot_we ? 4'b0010 : 4'b0000; end
            2'b10: begin ram_wdata = { 8'b0, boot_wdata, 16'b0}; ram_wstrb = boot_we ? 4'b0100 : 4'b0000; end
            2'b11: begin ram_wdata = {boot_wdata,        24'b0}; ram_wstrb = boot_we ? 4'b1000 : 4'b0000; end
        endcase

    end
    else begin

        ram_addr  = cpu_addr;
        ram_wdata = cpu_wdata;
        ram_wstrb = cpu_wstrb;

    end

end

endmodule