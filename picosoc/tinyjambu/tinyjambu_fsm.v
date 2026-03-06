// =============================================================================
// tinyjambu_fsm.v — TinyJAMBU FSM Controller (v2 — Shared Barrel Shifter)
//
// Changes vs tinyjambu_fsm.v:
//   - Added S_LATCH_AD and S_LATCH_DAT states to serialize barrel shifter use
//   - Added o_dp_latch_ad, o_dp_latch_dat control signals for datapath
//   - +2 cycle latency at start (negligible vs permutation cycles)
// =============================================================================
`timescale 1ns/1ps

module tinyjambu_fsm (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         i_ena,
    output reg          o_done,

    // NLFSR control (XOR-delta interface)
    output reg          o_nlfsr_init,
    output reg          o_nlfsr_run,
    output reg          o_nlfsr_wr_w1,
    output reg  [31:0]  o_nlfsr_w1_xor,
    output reg          o_nlfsr_wr_w3,
    output reg  [31:0]  o_nlfsr_w3_xor,
    input  wire [31:0]  i_w2,

    // Datapath control
    output reg          o_dp_latch,      // Latch non-shifted inputs
    output reg          o_dp_latch_ad,   // Latch shifted AD (barrel shifter cycle 1)
    output reg          o_dp_latch_dat,  // Latch shifted DATA (barrel shifter cycle 2)
    output reg  [1:0]   o_dp_key_idx,
    output reg  [1:0]   o_dp_nonce_idx,
    output reg  [1:0]   o_dp_ad_idx,
    output reg  [1:0]   o_dp_data_idx,
    output reg          o_dp_out_wr,
    output reg  [1:0]   o_dp_out_idx,
    output reg  [31:0]  o_dp_out_word,
    output reg          o_dp_finalize,
    output reg          o_dp_tag_wr,
    output reg  [31:0]  o_dp_tag_lo,
    output reg  [31:0]  o_dp_tag_hi,

    // Datapath data inputs
    input  wire [31:0]  i_dp_key_word,
    input  wire [31:0]  i_dp_nonce_word,
    input  wire [31:0]  i_dp_ad_word,
    input  wire [31:0]  i_dp_data_word,
    input  wire [2:0]   i_dp_ad_words,
    input  wire [2:0]   i_dp_data_words,
    input  wire [1:0]   i_dp_ad_partial,
    input  wire [1:0]   i_dp_data_partial,
    input  wire [31:0]  i_dp_ad_mask,
    input  wire [31:0]  i_dp_data_mask,
    input  wire [2:0]   i_dp_mode
);

  // ─── Constants ────────────────────────────────────────────────────────────
  localparam [5:0] STP_P1024 = 6'd32, STP_P640 = 6'd20;
  localparam [31:0] FR_N = 32'h0000_0010, FR_A = 32'h0000_0030,
                    FR_M = 32'h0000_0050, FR_F = 32'h0000_0070;
  localparam [2:0]  MODE_ENC = 3'b001;

  // ─── FSM States ───────────────────────────────────────────────────────────
  localparam [3:0]
      S_IDLE      = 4'd0,  S_LATCH_AD  = 4'd1,  S_LATCH_DAT = 4'd2,
      S_PERM      = 4'd3,  S_N_FRAME   = 4'd4,  S_N_XOR     = 4'd5,
      S_AD_FRAME  = 4'd6,  S_AD_XOR    = 4'd7,
      S_MSG_FRAME = 4'd8,  S_MSG_XOR   = 4'd9,
      S_FIN1      = 4'd10, S_FIN2      = 4'd11,
      S_DONE      = 4'd12;

  // ─── Registered state ─────────────────────────────────────────────────────
  reg [3:0]  fsm, perm_ret;
  reg [5:0]  steps, kidx;
  reg [1:0]  ncnt;
  reg [2:0]  wcnt;
  reg [31:0] tlo;

  // ─── Helper wires ─────────────────────────────────────────────────────────
  wire is_last_ad    = (wcnt == i_dp_ad_words - 1);
  wire is_last_msg   = (wcnt == i_dp_data_words - 1);
  wire ad_is_partial = (i_dp_ad_partial != 2'd0);
  wire msg_is_partial= (i_dp_data_partial != 2'd0);

  // ─── Sequential logic ─────────────────────────────────────────────────────
  always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
          fsm <= S_IDLE; perm_ret <= S_IDLE;
          steps <= 0; kidx <= 0; ncnt <= 0; wcnt <= 0; tlo <= 0;
          o_done <= 0;
      end else begin
          o_done <= 0;

          case (fsm)
          S_IDLE: if (i_ena) begin
              ncnt <= 0; wcnt <= 0; tlo <= 0;
              fsm  <= S_LATCH_AD;
          end

          // Serialized barrel shifter: AD first, then DATA
          S_LATCH_AD:  fsm <= S_LATCH_DAT;

          S_LATCH_DAT: begin
              // All inputs latched, start initial P1024
              steps    <= STP_P1024;
              kidx     <= 6'd0;
              perm_ret <= S_N_FRAME;
              fsm      <= S_PERM;
          end

          S_PERM: begin
              kidx  <= kidx + 1;
              steps <= steps - 1;
              if (steps == 6'd1) fsm <= perm_ret;
          end

          S_N_FRAME: begin
              steps <= STP_P640; kidx <= 6'd0;
              perm_ret <= S_N_XOR; fsm <= S_PERM;
          end

          S_N_XOR: begin
              ncnt <= ncnt + 1;
              if (ncnt < 2'd2)
                  fsm <= S_N_FRAME;
              else begin
                  wcnt <= 0;
                  if (i_dp_ad_words > 0) fsm <= S_AD_FRAME;
                  else if (i_dp_data_words > 0) fsm <= S_MSG_FRAME;
                  else begin
                      steps <= STP_P1024; kidx <= 6'd0;
                      perm_ret <= S_FIN1; fsm <= S_PERM;
                  end
              end
          end

          S_AD_FRAME: begin
              steps <= STP_P640; kidx <= 6'd0;
              perm_ret <= S_AD_XOR; fsm <= S_PERM;
          end

          S_AD_XOR: begin
              wcnt <= wcnt + 1;
              if (is_last_ad) begin
                  wcnt <= 0;
                  if (i_dp_data_words > 0) fsm <= S_MSG_FRAME;
                  else begin
                      steps <= STP_P1024; kidx <= 6'd0;
                      perm_ret <= S_FIN1; fsm <= S_PERM;
                  end
              end else fsm <= S_AD_FRAME;
          end

          S_MSG_FRAME: begin
              steps <= STP_P1024; kidx <= 6'd0;
              perm_ret <= S_MSG_XOR; fsm <= S_PERM;
          end

          S_MSG_XOR: begin
              wcnt <= wcnt + 1;
              if (is_last_msg) begin
                  steps <= STP_P1024; kidx <= 6'd0;
                  perm_ret <= S_FIN1; fsm <= S_PERM;
              end else fsm <= S_MSG_FRAME;
          end

          S_FIN1: begin
              tlo   <= i_w2;
              steps <= STP_P640; kidx <= 6'd0;
              perm_ret <= S_FIN2; fsm <= S_PERM;
          end

          S_FIN2: fsm <= S_DONE;

          S_DONE: begin
              o_done <= 1;
              fsm <= S_IDLE;
          end

          default: fsm <= S_IDLE;
          endcase
      end
  end

  // ─── Combinational outputs ─────────────────────────────────────────────────
  always @(*) begin
      // Defaults
      o_nlfsr_init    = 0;
      o_nlfsr_run     = 0;
      o_nlfsr_wr_w1   = 0;
      o_nlfsr_w1_xor  = 0;
      o_nlfsr_wr_w3   = 0;
      o_nlfsr_w3_xor  = 0;
      o_dp_latch      = 0;
      o_dp_latch_ad   = 0;
      o_dp_latch_dat  = 0;
      o_dp_key_idx    = kidx[1:0];
      o_dp_nonce_idx  = ncnt[1:0];
      o_dp_ad_idx     = wcnt[1:0];
      o_dp_data_idx   = wcnt[1:0];
      o_dp_out_wr     = 0;
      o_dp_out_idx    = 0;
      o_dp_out_word   = 0;
      o_dp_finalize   = 0;
      o_dp_tag_wr     = 0;
      o_dp_tag_lo     = 0;
      o_dp_tag_hi     = 0;

      case (fsm)
      S_IDLE: if (i_ena) begin
          o_dp_latch   = 1;       // Latch key, nonce, tag, lengths, mode
          o_nlfsr_init = 1;
      end

      S_LATCH_AD:  o_dp_latch_ad  = 1;  // Barrel shifter → ad_r
      S_LATCH_DAT: o_dp_latch_dat = 1;  // Barrel shifter → data_r

      S_PERM: o_nlfsr_run = 1;

      S_N_FRAME: begin
          o_nlfsr_wr_w1  = 1;
          o_nlfsr_w1_xor = FR_N;
      end

      S_N_XOR: begin
          o_dp_nonce_idx = ncnt[1:0];
          o_nlfsr_wr_w3  = 1;
          o_nlfsr_w3_xor = i_dp_nonce_word;
          if (ncnt >= 2'd2 && i_dp_ad_words == 0 && i_dp_data_words == 0) begin
              o_nlfsr_wr_w1  = 1;
              o_nlfsr_w1_xor = FR_F;
          end
      end

      S_AD_FRAME: begin
          o_nlfsr_wr_w1  = 1;
          o_nlfsr_w1_xor = FR_A;
      end

      S_AD_XOR: begin
          o_dp_ad_idx   = wcnt[1:0];
          o_nlfsr_wr_w3 = 1;
          o_nlfsr_w3_xor = (is_last_ad && ad_is_partial)
                           ? (i_dp_ad_word & i_dp_ad_mask)
                           : i_dp_ad_word;
          if (is_last_ad) begin
              if (i_dp_data_words > 0) begin
                  if (ad_is_partial) begin
                      o_nlfsr_wr_w1  = 1;
                      o_nlfsr_w1_xor = {30'd0, i_dp_ad_partial};
                  end
              end else begin
                  o_nlfsr_wr_w1  = 1;
                  o_nlfsr_w1_xor = ad_is_partial
                                   ? ({30'd0, i_dp_ad_partial} ^ FR_F)
                                   : FR_F;
              end
          end
      end

      S_MSG_FRAME: begin
          o_nlfsr_wr_w1  = 1;
          o_nlfsr_w1_xor = FR_M;
      end

      S_MSG_XOR: begin
          o_dp_data_idx = wcnt[1:0];
          o_dp_out_wr   = 1;
          o_dp_out_idx  = wcnt[1:0];
          o_nlfsr_wr_w3 = 1;

          if (is_last_msg && msg_is_partial) begin
              o_dp_out_word  = (i_w2 ^ i_dp_data_word) & i_dp_data_mask;
              o_nlfsr_w3_xor = (i_dp_mode == MODE_ENC)
                                ? (i_dp_data_word & i_dp_data_mask)
                                : ((i_w2 ^ i_dp_data_word) & i_dp_data_mask);
          end else begin
              o_dp_out_word  = i_w2 ^ i_dp_data_word;
              o_nlfsr_w3_xor = (i_dp_mode == MODE_ENC)
                                ? i_dp_data_word
                                : (i_w2 ^ i_dp_data_word);
          end

          if (is_last_msg) begin
              o_nlfsr_wr_w1  = 1;
              o_nlfsr_w1_xor = msg_is_partial
                               ? ({30'd0, i_dp_data_partial} ^ FR_F)
                               : FR_F;
          end
      end

      S_FIN1: begin
          o_nlfsr_wr_w1  = 1;
          o_nlfsr_w1_xor = FR_F;
      end

      S_FIN2: begin
          o_dp_tag_wr   = 1;
          o_dp_tag_lo   = tlo;
          o_dp_tag_hi   = i_w2;
          o_dp_finalize = 1;
      end

      default: ;
      endcase
  end

endmodule
