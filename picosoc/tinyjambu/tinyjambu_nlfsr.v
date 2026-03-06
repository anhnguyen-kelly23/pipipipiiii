// =============================================================================
// tinyjambu_nlfsr.v — TinyJAMBU NLFSR Permutation Engine (Optimized)
//
// Optimizations vs original:
//   1. XOR-delta interface: i_w1_xor / i_w3_xor instead of full-value write
//      → Eliminates FSM round-trip (read w1/w3 → XOR → write back)
//      → Saves 64-bit combinational feedback path between FSM and NLFSR
//   2. Reduced outputs: only o_w2 exported (FSM only needs w2 for tag/keystream)
//      → Removes 96 bits of output routing (o_w0, o_w1, o_w3 eliminated)
//   3. Internal state w0..w3 kept as local regs, not exposed
// =============================================================================
`timescale 1ns/1ps

module tinyjambu_nlfsr (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         i_init,       // Synchronous clear
    input  wire         i_run,        // Advance NLFSR one step (32 rounds)
    input  wire [31:0]  i_key_word,   // Current key word for feedback

    // XOR-delta write interface (no round-trip through FSM needed)
    input  wire         i_wr_w1,
    input  wire [31:0]  i_w1_xor,    // Value to XOR into w1 (e.g. frame bits)
    input  wire         i_wr_w3,
    input  wire [31:0]  i_w3_xor,    // Value to XOR into w3 (e.g. nonce/data word)

    output wire [31:0]  o_w2          // Only w2 needed: keystream & tag capture
);

  // ─── Internal state ──────────────────────────────────────────────────────
  reg [31:0] w0, w1, w2, w3;

  // ─── NLFSR feedback (32 parallel rounds, word-level shift) ───────────────
  // Taps at bit positions 47, 70, 85, 91 of 128-bit state {w3,w2,w1,w0}
  wire [31:0] t47 = (w1 >> 15) | (w2 << 17);
  wire [31:0] t70 = (w2 >>  6) | (w3 << 26);
  wire [31:0] t85 = (w2 >> 21) | (w3 << 11);
  wire [31:0] t91 = (w2 >> 27) | (w3 <<  5);
  wire [31:0] fb  = w0 ^ t47 ^ (~(t70 & t85)) ^ t91 ^ i_key_word;

  always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
          w0 <= 0; w1 <= 0; w2 <= 0; w3 <= 0;
      end else if (i_init) begin
          w0 <= 0; w1 <= 0; w2 <= 0; w3 <= 0;
      end else if (i_run) begin
          w0 <= w1;
          w1 <= w2;
          w2 <= w3;
          w3 <= fb;
      end else begin
          // XOR-delta updates (frame bits / data injection)
          if (i_wr_w1) w1 <= w1 ^ i_w1_xor;
          if (i_wr_w3) w3 <= w3 ^ i_w3_xor;
      end
  end

  assign o_w2 = w2;

endmodule
