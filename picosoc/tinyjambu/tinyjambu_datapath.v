// =============================================================================
// tinyjambu_datapath.v — TinyJAMBU Data Processing (Shared Barrel Shifter)
//
// Key optimization: ONE barrel shifter instance, time-multiplexed across:
//   Cycle 1 (i_latch_ad):  shift bswap128(ad)       → ad_r
//   Cycle 2 (i_latch_dat): shift bswap128(data_in)  → data_r
//   Cycle 3 (i_finalize):  shift bswap128(data_out) → o_data_out (final)
//
// Barrel shifter savings: 2 × ~200-300 LUTs = 400-600 LUTs eliminated
// Additional: bit-concat shift amount eliminates multiplier
// =============================================================================
`timescale 1ns/1ps

module tinyjambu_datapath (
    input  wire         clk,
    input  wire         rst_n,

    // === Raw inputs from top-level (active during latch) ===
    input  wire [127:0] i_key,
    input  wire [95:0]  i_nonce,
    input  wire [127:0] i_ad,
    input  wire [4:0]   i_ad_length,
    input  wire [127:0] i_data_in,
    input  wire [4:0]   i_data_length,
    input  wire [63:0]  i_tag_in,
    input  wire [2:0]   i_sel_type,

    // === Serialized latch control ===
    input  wire         i_latch,       // Latch non-shifted: key, nonce, tag, lengths, mode
    input  wire         i_latch_ad,    // Barrel shifter cycle 1: latch aligned AD
    input  wire         i_latch_dat,   // Barrel shifter cycle 2: latch aligned DATA

    // === Word selection ===
    input  wire [1:0]   i_key_idx,
    input  wire [1:0]   i_nonce_idx,
    input  wire [1:0]   i_ad_idx,
    input  wire [1:0]   i_data_idx,

    // === Combinational word outputs ===
    output wire [31:0]  o_key_word,
    output wire [31:0]  o_nonce_word,
    output wire [31:0]  o_ad_word,
    output wire [31:0]  o_data_word,

    // === Computed properties ===
    output wire [2:0]   o_ad_words,
    output wire [2:0]   o_data_words,
    output wire [1:0]   o_ad_partial,
    output wire [1:0]   o_data_partial,
    output wire [31:0]  o_ad_mask,
    output wire [31:0]  o_data_mask,
    output wire [2:0]   o_mode,

    // === Output accumulation ===
    input  wire         i_out_wr,
    input  wire [1:0]   i_out_idx,
    input  wire [31:0]  i_out_word,
    input  wire         i_finalize,

    // === Tag ===
    input  wire         i_tag_wr,
    input  wire [31:0]  i_tag_lo,
    input  wire [31:0]  i_tag_hi,

    // === Final outputs ===
    output reg  [127:0] o_data_out,
    output reg  [63:0]  o_tag,
    output reg          o_valid
);

  // ─── Byte swap (wiring only, zero LUTs) ──────────────────────────────────
  function [127:0] bswap128;
      input [127:0] x;
      bswap128 = {x[7:0],x[15:8],x[23:16],x[31:24],
                  x[39:32],x[47:40],x[55:48],x[63:56],
                  x[71:64],x[79:72],x[87:80],x[95:88],
                  x[103:96],x[111:104],x[119:112],x[127:120]};
  endfunction

  function [95:0] bswap96;
      input [95:0] x;
      bswap96 = {x[7:0],x[15:8],x[23:16],x[31:24],
                 x[39:32],x[47:40],x[55:48],x[63:56],
                 x[71:64],x[79:72],x[87:80],x[95:88]};
  endfunction

  function [63:0] bswap64;
      input [63:0] x;
      bswap64 = {x[7:0],x[15:8],x[23:16],x[31:24],
                 x[39:32],x[47:40],x[55:48],x[63:56]};
  endfunction

  // ─── Word extraction ─────────────────────────────────────────────────────
  function [31:0] get_word;
      input [127:0] data;
      input [1:0]   idx;
      case (idx)
          2'd0: get_word = data[31:0];
          2'd1: get_word = data[63:32];
          2'd2: get_word = data[95:64];
          2'd3: get_word = data[127:96];
      endcase
  endfunction

  function [31:0] get_nonce_word;
      input [95:0] data;
      input [1:0]  idx;
      case (idx)
          2'd0: get_nonce_word = data[31:0];
          2'd1: get_nonce_word = data[63:32];
          2'd2: get_nonce_word = data[95:64];
          default: get_nonce_word = 32'd0;
      endcase
  endfunction

  function [31:0] byte_mask;
      input [1:0] len_mod;
      case (len_mod)
          2'd0: byte_mask = 32'hFFFFFFFF;
          2'd1: byte_mask = 32'h000000FF;
          2'd2: byte_mask = 32'h0000FFFF;
          2'd3: byte_mask = 32'h00FFFFFF;
      endcase
  endfunction

  function [2:0] calc_words;
      input [4:0] byte_len;
      if (byte_len == 0)
          calc_words = 3'd0;
      else
          calc_words = byte_len[4:2] + (byte_len[1:0] != 2'b00 ? 3'd1 : 3'd0);
  endfunction

  // ─── Latched registers ────────────────────────────────────────────────────
  reg [127:0] key_r;
  reg [95:0]  nonce_r;
  reg [127:0] ad_r;
  reg [127:0] data_r;
  reg [63:0]  tag_in_r;
  reg [4:0]   ad_len_r, data_len_r;
  reg [2:0]   mode_r;
  reg [2:0]   ad_words_r, data_words_r;

  // ─── SHARED BARREL SHIFTER ────────────────────────────────────────────────
  // Single 128-bit right-shift instance, MUXed input/shift-amount
  // Time-multiplexed across 3 phases (never overlapping):
  //   Phase 1: i_latch_ad  → bswap128(i_ad) >> (16-ad_len)*8
  //   Phase 2: i_latch_dat → bswap128(i_data_in) >> (16-data_len)*8
  //   Phase 3: i_finalize  → bswap128(o_data_out) >> (16-data_len_r)*8

  reg  [127:0] bs_input;
  reg  [4:0]   bs_len;
  wire [7:0]   bs_shift = {(5'd16 - bs_len), 3'b000};  // bit-concat: no multiplier
  wire [127:0] bs_output = bs_input >> bs_shift;

  // Barrel shifter input MUX (combinational)
  always @(*) begin
      bs_input = 128'd0;
      bs_len   = 5'd16;   // shift by 0 (default, safe)
      if (i_latch_ad) begin
          bs_input = bswap128(i_ad);
          bs_len   = i_ad_length;
      end else if (i_latch_dat) begin
          bs_input = bswap128(i_data_in);
          bs_len   = i_data_length;
      end else if (i_finalize) begin
          bs_input = bswap128(o_data_out);
          bs_len   = data_len_r;
      end
  end

  // ─── Register logic ───────────────────────────────────────────────────────
  always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
          key_r <= 0; nonce_r <= 0; ad_r <= 0; data_r <= 0; tag_in_r <= 0;
          ad_len_r <= 0; data_len_r <= 0; mode_r <= 0;
          ad_words_r <= 0; data_words_r <= 0;
          o_data_out <= 0; o_tag <= 0; o_valid <= 0;
      end else begin
          // Phase 0: Latch non-shifted inputs
          if (i_latch) begin
              key_r        <= bswap128(i_key);
              nonce_r      <= bswap96(i_nonce);
              tag_in_r     <= bswap64(i_tag_in);
              ad_len_r     <= i_ad_length;
              data_len_r   <= i_data_length;
              mode_r       <= i_sel_type;
              ad_words_r   <= calc_words(i_ad_length);
              data_words_r <= calc_words(i_data_length);
              o_data_out   <= 0;
              o_tag        <= 0;
              o_valid      <= 0;
          end

          // Phase 1: Barrel shifter → AD register
          if (i_latch_ad)
              ad_r <= bs_output;

          // Phase 2: Barrel shifter → DATA register
          if (i_latch_dat)
              data_r <= bs_output;

          // Accumulate output words
          if (i_out_wr)
              o_data_out[{i_out_idx, 5'd0} +: 32] <= i_out_word;

          // Phase 3: Barrel shifter → final output (byte-swap + align)
          if (i_finalize)
              o_data_out <= bs_output;

          // Tag
          if (i_tag_wr) begin
              o_tag   <= bswap64({i_tag_hi, i_tag_lo});
              o_valid <= (mode_r == 3'b010) ? ({i_tag_hi, i_tag_lo} == tag_in_r) : 1'b1;
          end
      end
  end

  // ─── Combinational word outputs ───────────────────────────────────────────
  assign o_key_word     = key_r[{i_key_idx, 5'd0} +: 32];
  assign o_nonce_word   = get_nonce_word(nonce_r, i_nonce_idx);
  assign o_ad_word      = get_word(ad_r, i_ad_idx);
  assign o_data_word    = get_word(data_r, i_data_idx);
  assign o_ad_words     = ad_words_r;
  assign o_data_words   = data_words_r;
  assign o_ad_partial   = ad_len_r[1:0];
  assign o_data_partial = data_len_r[1:0];
  assign o_ad_mask      = byte_mask(ad_len_r[1:0]);
  assign o_data_mask    = byte_mask(data_len_r[1:0]);
  assign o_mode         = mode_r;

endmodule
