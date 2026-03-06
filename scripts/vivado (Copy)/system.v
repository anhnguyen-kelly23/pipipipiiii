`timescale 1 ns / 1 ps
 
module system (
	input            clk,
	input            resetn_btn,
	output           trap,
	output reg [7:0] out_byte,
	output reg       out_byte_en,
 
	input      [3:0] sw,
	input      [3:0] btn,
 
	output           uart_tx,
	input            uart_rx
);
	parameter FAST_MEMORY = 1;
	parameter MEM_SIZE = 4096;
 
	// ============================================
	// MEMORY MAP:
	//   0x0000_0000 .. 0x0000_3FFF  RAM (16KB)          R/W
	//   0x1000_0000                  out_byte -> LED      W
	//   0x1000_0004                  UART TX Data         W
	//   0x1000_0008                  UART RX Data         R
	//   0x1000_000C                  UART Status          R
	//   0x1000_0010                  UART Baud Divider    R/W
	//   0x2000_0000                  Switch Register      R
	//   0x2000_0004                  Button Register      R
	// ============================================
 
	// ============================================
	// POWER-ON RESET GENERATOR
	// ============================================
	reg [5:0] reset_cnt = 0;
	reg [2:0] resetn_sync = 3'b000;
 
	always @(posedge clk) begin
		resetn_sync <= {resetn_sync[1:0], resetn_btn};
	end
 
	always @(posedge clk) begin
		if (!resetn_sync[2])
			reset_cnt <= 0;
		else if (!(&reset_cnt))
			reset_cnt <= reset_cnt + 1;
	end
 
	wire resetn = &reset_cnt;
 
	// ============================================
	// Synchronizer cho switch/button
	// ============================================
	reg [3:0] sw_sync1, sw_sync2;
	reg [3:0] btn_sync1, btn_sync2;
 
	always @(posedge clk) begin
		sw_sync1  <= sw;
		sw_sync2  <= sw_sync1;
		btn_sync1 <= btn;
		btn_sync2 <= btn_sync1;
	end
 
	// ============================================
	// UART Module (simpleuart)
	// ============================================
	wire        uart_dat_wait;
	wire [31:0] uart_dat_do;
	wire [31:0] uart_div_do;
 
	wire uart_rx_valid = (uart_dat_do != 32'hFFFFFFFF);
 
	reg        uart_we;
	reg        uart_rx_rd;
	reg [7:0]  uart_tx_data;
	reg [3:0]  uart_div_we;
	reg [31:0] uart_div_di;
 
	// TX busy tracking:
	//   uart_we is pulsed HIGH for exactly 1 cycle (simpleuart latches byte).
	//   Then tx_countdown counts the full byte transmission time.
	//   This prevents holding uart_we HIGH which causes re-latch bug.
	//   10 bits * (868 + 2) = 8700 cycles, use 9000 for margin.
	reg tx_busy;
	reg [15:0] tx_countdown;
	wire uart_tx_ready = !tx_busy;
 
	simpleuart #(
		.DEFAULT_DIV(868)
	) uart_inst (
		.clk          (clk),
		.resetn       (resetn),
		.ser_tx       (uart_tx),
		.ser_rx       (uart_rx),
		.reg_div_we   (uart_div_we),
		.reg_div_di   (uart_div_di),
		.reg_div_do   (uart_div_do),
		.reg_dat_we   (uart_we),
		.reg_dat_re   (uart_rx_rd),
		.reg_dat_di   ({24'b0, uart_tx_data}),
		.reg_dat_do   (uart_dat_do),
		.reg_dat_wait (uart_dat_wait)
	);
 
	// ============================================
	// PicoRV32 CPU
	// ============================================
	wire mem_valid;
	wire mem_instr;
	reg mem_ready;
	wire [31:0] mem_addr;
	wire [31:0] mem_wdata;
	wire [3:0] mem_wstrb;
	reg [31:0] mem_rdata;
 
	wire mem_la_read;
	wire mem_la_write;
	wire [31:0] mem_la_addr;
	wire [31:0] mem_la_wdata;
	wire [3:0] mem_la_wstrb;
 
	picorv32 picorv32_core (
		.clk         (clk         ),
		.resetn      (resetn      ),
		.trap        (trap        ),
		.mem_valid   (mem_valid   ),
		.mem_instr   (mem_instr   ),
		.mem_ready   (mem_ready   ),
		.mem_addr    (mem_addr    ),
		.mem_wdata   (mem_wdata   ),
		.mem_wstrb   (mem_wstrb   ),
		.mem_rdata   (mem_rdata   ),
		.mem_la_read (mem_la_read ),
		.mem_la_write(mem_la_write),
		.mem_la_addr (mem_la_addr ),
		.mem_la_wdata(mem_la_wdata),
		.mem_la_wstrb(mem_la_wstrb)
	);
 
	reg [31:0] memory [0:MEM_SIZE-1];
	initial $readmemh("firmware.hex", memory);
 
	reg [31:0] m_read_data;
	reg m_read_en;
 
	// ============================================
	// FAST_MEMORY mode
	// ============================================
	generate if (FAST_MEMORY) begin
 
		always @(posedge clk) begin
			if (!resetn) begin
				mem_ready <= 0;
				out_byte_en <= 0;
				uart_we <= 0;
				uart_rx_rd <= 0;
				uart_div_we <= 4'b0000;
				uart_div_di <= 32'b0;
				tx_busy <= 0;
				tx_countdown <= 0;
			end else begin
				mem_ready <= 1;
				out_byte_en <= 0;
				uart_rx_rd  <= 0;
				uart_div_we <= 4'b0000;
				uart_div_di <= 32'b0;
 
				// --- TX busy state machine ---
				// uart_we auto-clears every cycle (1-cycle pulse)
				// tx_countdown counts down until byte fully sent
				uart_we <= 0;
				if (tx_busy) begin
					if (tx_countdown != 0)
						tx_countdown <= tx_countdown - 1;
					else
						tx_busy <= 0;
				end
 
				// --- Default: read from RAM ---
				mem_rdata <= memory[mem_la_addr >> 2];
 
				// --- Read peripherals ---
				if (mem_la_read) begin
					case (mem_la_addr)
						32'h2000_0000: begin
							mem_rdata <= {28'b0, sw_sync2};
						end
						32'h2000_0004: begin
							mem_rdata <= {28'b0, btn_sync2};
						end
						32'h1000_0008: begin
							mem_rdata <= uart_dat_do;
							uart_rx_rd <= 1;
						end
						32'h1000_000C: begin
							mem_rdata <= {30'b0, uart_rx_valid, uart_tx_ready};
						end
						32'h1000_0010: begin
							mem_rdata <= uart_div_do;
						end
						default: begin
							mem_rdata <= memory[mem_la_addr >> 2];
						end
					endcase
				end
 
				// --- Write to RAM ---
				if (mem_la_write && (mem_la_addr >> 2) < MEM_SIZE) begin
					if (mem_la_wstrb[0]) memory[mem_la_addr >> 2][ 7: 0] <= mem_la_wdata[ 7: 0];
					if (mem_la_wstrb[1]) memory[mem_la_addr >> 2][15: 8] <= mem_la_wdata[15: 8];
					if (mem_la_wstrb[2]) memory[mem_la_addr >> 2][23:16] <= mem_la_wdata[23:16];
					if (mem_la_wstrb[3]) memory[mem_la_addr >> 2][31:24] <= mem_la_wdata[31:24];
				end
				else if (mem_la_write) begin
					case (mem_la_addr)
						32'h1000_0000: begin
							out_byte_en <= 1;
							out_byte <= mem_la_wdata[7:0];
						end
						32'h1000_0004: begin
							if (!tx_busy) begin
								uart_tx_data <= mem_la_wdata[7:0];
								uart_we <= 1;     // 1-cycle pulse
								tx_busy <= 1;
								tx_countdown <= 16'd9000;  // 10bits * 870 + margin
							end
						end
						32'h1000_0010: begin
							uart_div_we <= mem_la_wstrb;
							uart_div_di <= mem_la_wdata;
						end
						default: ;
					endcase
				end
			end
		end
 
	// ============================================
	// SLOW_MEMORY mode
	// ============================================
	end else begin
 
		always @(posedge clk) begin
			if (!resetn) begin
				m_read_en <= 0;
				mem_ready <= 0;
				out_byte_en <= 0;
				uart_we <= 0;
				uart_rx_rd <= 0;
				uart_div_we <= 4'b0000;
				uart_div_di <= 32'b0;
				tx_busy <= 0;
				tx_countdown <= 0;
			end else begin
				m_read_en <= 0;
				mem_ready <= mem_valid && !mem_ready && m_read_en;
 
				m_read_data <= memory[mem_addr >> 2];
				mem_rdata <= m_read_data;
 
				out_byte_en <= 0;
				uart_rx_rd  <= 0;
				uart_div_we <= 4'b0000;
				uart_div_di <= 32'b0;
 
				// --- TX busy state machine ---
				uart_we <= 0;
				if (tx_busy) begin
					if (tx_countdown != 0)
						tx_countdown <= tx_countdown - 1;
					else
						tx_busy <= 0;
				end
 
				(* parallel_case *)
				case (1)
					mem_valid && !mem_ready && !mem_wstrb && (mem_addr >> 2) < MEM_SIZE: begin
						m_read_en <= 1;
					end
 
					mem_valid && !mem_ready && !mem_wstrb && mem_addr == 32'h2000_0000: begin
						mem_rdata <= {28'b0, sw_sync2};
						mem_ready <= 1;
					end
 
					mem_valid && !mem_ready && !mem_wstrb && mem_addr == 32'h2000_0004: begin
						mem_rdata <= {28'b0, btn_sync2};
						mem_ready <= 1;
					end
 
					mem_valid && !mem_ready && !mem_wstrb && mem_addr == 32'h1000_0008: begin
						mem_rdata <= uart_dat_do;
						uart_rx_rd <= 1;
						mem_ready <= 1;
					end
 
					mem_valid && !mem_ready && !mem_wstrb && mem_addr == 32'h1000_000C: begin
						mem_rdata <= {30'b0, uart_rx_valid, uart_tx_ready};
						mem_ready <= 1;
					end
 
					mem_valid && !mem_ready && !mem_wstrb && mem_addr == 32'h1000_0010: begin
						mem_rdata <= uart_div_do;
						mem_ready <= 1;
					end
 
					mem_valid && !mem_ready && |mem_wstrb && (mem_addr >> 2) < MEM_SIZE: begin
						if (mem_wstrb[0]) memory[mem_addr >> 2][ 7: 0] <= mem_wdata[ 7: 0];
						if (mem_wstrb[1]) memory[mem_addr >> 2][15: 8] <= mem_wdata[15: 8];
						if (mem_wstrb[2]) memory[mem_addr >> 2][23:16] <= mem_wdata[23:16];
						if (mem_wstrb[3]) memory[mem_addr >> 2][31:24] <= mem_wdata[31:24];
						mem_ready <= 1;
					end
 
					mem_valid && !mem_ready && |mem_wstrb && mem_addr == 32'h1000_0000: begin
						out_byte_en <= 1;
						out_byte <= mem_wdata[7:0];
						mem_ready <= 1;
					end
 
					mem_valid && !mem_ready && |mem_wstrb && mem_addr == 32'h1000_0004: begin
						if (!tx_busy) begin
							uart_tx_data <= mem_wdata[7:0];
							uart_we <= 1;
							tx_busy <= 1;
							tx_countdown <= 16'd9000;
						end
						mem_ready <= 1;
					end
 
					mem_valid && !mem_ready && |mem_wstrb && mem_addr == 32'h1000_0010: begin
						uart_div_we <= mem_wstrb;
						uart_div_di <= mem_wdata;
						mem_ready <= 1;
					end
 
					default: ;
				endcase
			end
		end
 
	end endgenerate
endmodule
