// =============================================================================
// tinyjambu_core.v — TinyJAMBU AEAD Core (Maximum Area Optimization)
//
// Architecture: 3-module decomposition with shared barrel shifter
//   - tinyjambu_nlfsr: NLFSR permutation engine with XOR-delta interface
//   - tinyjambu_fsm: FSM controller (outputs XOR deltas, not full values)
//   - tinyjambu_datapath: Data processing with ONE shared barrel shifter
//
// Area savings vs original monolithic (1495 LUTs, 932 FFs):
//   - Shared barrel shifter:     -400 to -600 LUTs (2 of 3 shifters eliminated)
//   - XOR-delta NLFSR interface: -50  to -100 LUTs (no w0/w1/w3 feedback bus)
//   - Bit-concat shift amount:   -50  to -100 LUTs (no multiplier)
//   - Direct output accumulate:  -128 FFs
//   Expected: ~800-1000 LUTs, ~800 FFs
//
// Latency: +2 cycles (serialized AD/DATA latch), negligible vs permutation
// Interface: Drop-in compatible with original tinyjambu_core
// =============================================================================
`timescale 1ns/1ps

module tinyjambu_core (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         ena,
    input  wire [2:0]   sel_type,
    input  wire [127:0] key,
    input  wire [95:0]  nonce,
    input  wire [127:0] ad,
    input  wire [4:0]   ad_length,
    input  wire [4:0]   data_length,
    input  wire [127:0] data_in,
    input  wire [63:0]  tag_in,

    output wire         valid,
    output wire [63:0]  tag,
    output wire [127:0] data_out,
    output wire         done
);

  // ─── Internal wires: FSM ↔ NLFSR ─────────────────────────────────────────
  wire        nlfsr_init, nlfsr_run;
  wire        nlfsr_wr_w1, nlfsr_wr_w3;
  wire [31:0] nlfsr_w1_xor, nlfsr_w3_xor;
  wire [31:0] w2_out;

  // ─── Internal wires: FSM ↔ Datapath ──────────────────────────────────────
  wire        dp_latch, dp_latch_ad, dp_latch_dat;
  wire [1:0]  dp_key_idx, dp_nonce_idx, dp_ad_idx, dp_data_idx;
  wire        dp_out_wr;
  wire [1:0]  dp_out_idx;
  wire [31:0] dp_out_word;
  wire        dp_finalize, dp_tag_wr;
  wire [31:0] dp_tag_lo, dp_tag_hi;

  wire [31:0] key_word, nonce_word, ad_word, data_word;
  wire [2:0]  ad_words_w, data_words_w;
  wire [1:0]  ad_partial_w, data_partial_w;
  wire [31:0] ad_mask_w, data_mask_w;
  wire [2:0]  mode_w;

  // ─── NLFSR (uses existing optimized module) ───────────────────────────────
  tinyjambu_nlfsr u_nlfsr (
      .clk        (clk),
      .rst_n      (rst_n),
      .i_init     (nlfsr_init),
      .i_run      (nlfsr_run),
      .i_key_word (key_word),
      .i_wr_w1    (nlfsr_wr_w1),
      .i_w1_xor   (nlfsr_w1_xor),
      .i_wr_w3    (nlfsr_wr_w3),
      .i_w3_xor   (nlfsr_w3_xor),
      .o_w2       (w2_out)
  );

  // ─── FSM (with serialized latch states) ───────────────────────────────────
  tinyjambu_fsm u_fsm (
      .clk            (clk),
      .rst_n          (rst_n),
      .i_ena          (ena),
      .o_done         (done),
      // NLFSR control
      .o_nlfsr_init   (nlfsr_init),
      .o_nlfsr_run    (nlfsr_run),
      .o_nlfsr_wr_w1  (nlfsr_wr_w1),
      .o_nlfsr_w1_xor (nlfsr_w1_xor),
      .o_nlfsr_wr_w3  (nlfsr_wr_w3),
      .o_nlfsr_w3_xor (nlfsr_w3_xor),
      .i_w2           (w2_out),
      // Datapath control
      .o_dp_latch     (dp_latch),
      .o_dp_latch_ad  (dp_latch_ad),
      .o_dp_latch_dat (dp_latch_dat),
      .o_dp_key_idx   (dp_key_idx),
      .o_dp_nonce_idx (dp_nonce_idx),
      .o_dp_ad_idx    (dp_ad_idx),
      .o_dp_data_idx  (dp_data_idx),
      .o_dp_out_wr    (dp_out_wr),
      .o_dp_out_idx   (dp_out_idx),
      .o_dp_out_word  (dp_out_word),
      .o_dp_finalize  (dp_finalize),
      .o_dp_tag_wr    (dp_tag_wr),
      .o_dp_tag_lo    (dp_tag_lo),
      .o_dp_tag_hi    (dp_tag_hi),
      // Datapath data
      .i_dp_key_word     (key_word),
      .i_dp_nonce_word   (nonce_word),
      .i_dp_ad_word      (ad_word),
      .i_dp_data_word    (data_word),
      .i_dp_ad_words     (ad_words_w),
      .i_dp_data_words   (data_words_w),
      .i_dp_ad_partial   (ad_partial_w),
      .i_dp_data_partial (data_partial_w),
      .i_dp_ad_mask      (ad_mask_w),
      .i_dp_data_mask    (data_mask_w),
      .i_dp_mode         (mode_w)
  );

  // ─── Datapath (shared barrel shifter version) ─────────────────────────────
  tinyjambu_datapath u_dp (
      .clk           (clk),
      .rst_n         (rst_n),
      // Raw inputs
      .i_key         (key),
      .i_nonce       (nonce),
      .i_ad          (ad),
      .i_ad_length   (ad_length),
      .i_data_in     (data_in),
      .i_data_length (data_length),
      .i_tag_in      (tag_in),
      .i_sel_type    (sel_type),
      // Latch control (serialized: latch_all → latch_ad → latch_dat)
      .i_latch       (dp_latch),
      .i_latch_ad    (dp_latch_ad),
      .i_latch_dat   (dp_latch_dat),
      // Word selection
      .i_key_idx     (dp_key_idx),
      .i_nonce_idx   (dp_nonce_idx),
      .i_ad_idx      (dp_ad_idx),
      .i_data_idx    (dp_data_idx),
      // Word outputs
      .o_key_word    (key_word),
      .o_nonce_word  (nonce_word),
      .o_ad_word     (ad_word),
      .o_data_word   (data_word),
      // Properties
      .o_ad_words    (ad_words_w),
      .o_data_words  (data_words_w),
      .o_ad_partial  (ad_partial_w),
      .o_data_partial(data_partial_w),
      .o_ad_mask     (ad_mask_w),
      .o_data_mask   (data_mask_w),
      .o_mode        (mode_w),
      // Output accumulation
      .i_out_wr      (dp_out_wr),
      .i_out_idx     (dp_out_idx),
      .i_out_word    (dp_out_word),
      .i_finalize    (dp_finalize),
      // Tag
      .i_tag_wr      (dp_tag_wr),
      .i_tag_lo      (dp_tag_lo),
      .i_tag_hi      (dp_tag_hi),
      // Final outputs
      .o_data_out    (data_out),
      .o_tag         (tag),
      .o_valid       (valid)
  );

endmodule
