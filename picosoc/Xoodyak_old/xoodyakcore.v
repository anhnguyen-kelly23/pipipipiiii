//--------------------------------------------------------------------------------
// @file       xoodyakcore.v
// @brief      Xoodyak cipher with simplified parallel interface
// @description Full featured: AEAD Enc/Dec with AD, Hash, Tag verification
//--------------------------------------------------------------------------------

`timescale 1ns/1ps

module xoodyakcore (
    // Clock and Reset
    input  wire         clk,
    input  wire         rst_n,              // Active low reset

    // Control
    input  wire         ena,                // Enable - start processing
    input  wire         restart,            // Restart for new encryption
    input  wire [2:0]   sel_type,           // Mode: 001=Encrypt, 010=Decrypt, 011=Hash

    // Inputs
    input  wire [127:0] key,                // 128-bit key (AEAD only)
    input  wire [127:0] nonce,              // 128-bit nonce (AEAD only)
    input  wire [127:0] ad,                 // 128-bit Associated Data
    input  wire [4:0]   ad_length,          // AD length in bytes (0-16)
    input  wire [4:0]   data_length,        // Data length in bytes (0-16)
    input  wire [127:0] data_in,            // Data input (PT/CT/HashMsg)
    input  wire [127:0] tag_in,             // Tag for verification (decrypt)

    // Outputs
    output reg          valid,              // Tag verification result (decoder)
    output reg  [127:0] tag,                // 128-bit tag output
    output reg  [127:0] data_out,           // CT/PT/Hash output
    output reg          done                // Done signal
  );

  // =========================================================================
  // Parameters
  // =========================================================================
  parameter roundsPerCycle = 1;

  parameter CCW = 32;
  parameter KEY_WORDS = 4;
  parameter NPUB_WORDS = 4;
  parameter TAG_WORDS = 4;
  parameter RHASH_WORDS = 4;
  parameter AD_WORDS = 4;

  // Mode constants for sel_type[2:0]
  localparam [2:0] MODE_AEAD_ENC = 3'b001;
  localparam [2:0] MODE_AEAD_DEC = 3'b010;
  localparam [2:0] MODE_HASH     = 3'b011;

  // Domain constants
  localparam [31:0] DOMAIN_ABSORB_HASH = 32'h01000000;
  localparam [31:0] DOMAIN_ABSORB_KEY  = 32'h02000000;
  localparam [31:0] DOMAIN_ABSORB      = 32'h03000000;
  localparam [31:0] DOMAIN_ZERO        = 32'h00000000;
  localparam [31:0] DOMAIN_SQUEEZE     = 32'h40000000;
  localparam [31:0] DOMAIN_CRYPT       = 32'h80000000;
  localparam [31:0] PADD_01            = 32'h00000001;
  localparam [31:0] PADD_01_KEY_NONCE  = {16'h0, 1'b1, 3'h0, 1'b1, 4'h0}; // Match CryptoCore.v exactly (Bits 8 and 4)

  // =========================================================================
  // FSM States
  // =========================================================================
  localparam [4:0] S_IDLE         = 5'd0,
             S_LOAD_KEY     = 5'd1,
             S_LOAD_NONCE   = 5'd2,
             S_PAD_NONCE    = 5'd3,
             S_PERM_NONCE   = 5'd4,
             // AD states
             S_LOAD_AD      = 5'd5,
             S_PAD_AD       = 5'd6,
             S_PERM_AD      = 5'd7,
             // Data states
             S_LOAD_DATA    = 5'd8,
             S_PAD_DATA     = 5'd9,
             S_PERM_DATA    = 5'd10,
             S_EXTRACT_TAG  = 5'd11,
             S_VERIFY_TAG   = 5'd12,
             S_DONE         = 5'd13,
             // Hash states
             S_HASH_LOAD    = 5'd14,
             S_HASH_PAD     = 5'd15,
             S_HASH_PERM1   = 5'd16,
             S_HASH_SQUEEZE1= 5'd17,
             S_HASH_PAD2    = 5'd18,
             S_HASH_PERM2   = 5'd19,
             S_HASH_SQUEEZE2= 5'd20;

  // =========================================================================
  // Registers
  // =========================================================================
  reg [4:0]   state_r, state_next;
  reg [3:0]   word_cnt_r;

  // Latched inputs
  reg [127:0] key_r, nonce_r, ad_r, data_in_r, tag_in_r;
  reg [4:0]   ad_length_r, data_length_r;
  reg [2:0]   sel_type_r;

  // Output buffers
  reg [127:0] data_out_r, tag_r;
  reg         valid_r;

  // Domain register
  reg [31:0]  domain_r;

  // Internal reset (active high for xoodoo)
  wire rst = ~rst_n;

  // =========================================================================
  // Xoodoo Interface
  // =========================================================================
  reg         xoodoo_start_next;  // Combinational - request to start permutation
  reg         xoodoo_start_r;     // Registered - actual start signal to xoodoo
  reg         xoodoo_init;
  reg  [31:0] xoodoo_word_in;
  reg  [3:0]  xoodoo_word_idx;
  reg         xoodoo_word_en;
  reg  [31:0] xoodoo_domain;
  reg         xoodoo_domain_en;
  wire        xoodoo_valid;
  wire [31:0] xoodoo_word_out;

  // Register xoodoo_start to ensure word/domain loading happens BEFORE start
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      xoodoo_start_r <= 1'b0;
    else if (restart)
      xoodoo_start_r <= 1'b0;
    else
      xoodoo_start_r <= xoodoo_start_next;
  end

  xoodoo #(.roundPerCycle(roundsPerCycle)) u_xoodoo (
           .clk_i(clk),
           .rst_i(rst),
           .start_i(xoodoo_start_r),    // Use registered start signal
           .state_valid_o(xoodoo_valid),
           .init_reg(xoodoo_init),
           .word_in(xoodoo_word_in),
           .word_index_in(xoodoo_word_idx),
           .word_enable_in(xoodoo_word_en),
           .domain_i(xoodoo_domain),
           .domain_enable_i(xoodoo_domain_en),
           .word_out(xoodoo_word_out)
         );

  // =========================================================================
  // Byte swap function
  // =========================================================================
  function [31:0] byte_swap;
    input [31:0] word;
    begin
      byte_swap = {word[7:0], word[15:8], word[23:16], word[31:24]};
    end
  endfunction

  function [31:0] get_word;
    input [127:0] data;
    input [1:0] idx;
    begin
      case (idx)
        2'd0:
          get_word = byte_swap(data[127:96]);
        2'd1:
          get_word = byte_swap(data[95:64]);
        2'd2:
          get_word = byte_swap(data[63:32]);
        2'd3:
          get_word = byte_swap(data[31:0]);
      endcase
    end
  endfunction

  // =========================================================================
  // State Machine
  // =========================================================================
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      state_r <= S_IDLE;
    else if (restart)
      state_r <= S_IDLE;
    else
      state_r <= state_next;
  end

  always @(*)
  begin
    state_next = state_r;

    case (state_r)
      S_IDLE:
      begin
        if (ena)
        begin
          if (sel_type == MODE_HASH)
            state_next = S_HASH_LOAD;
          else
            state_next = S_LOAD_KEY;
        end
      end

      // Key loading
      S_LOAD_KEY:
        if (word_cnt_r == KEY_WORDS - 1)
          state_next = S_LOAD_NONCE;

      // Nonce loading
      S_LOAD_NONCE:
        if (word_cnt_r == KEY_WORDS + NPUB_WORDS - 1)
          state_next = S_PAD_NONCE;

      S_PAD_NONCE:
        state_next = S_PERM_NONCE;

      S_PERM_NONCE:
      begin
        if (xoodoo_valid && !xoodoo_start_r)
        begin
          // Always go through AD processing (even if empty)
          if (ad_length_r > 0)
            state_next = S_LOAD_AD;
          else
            state_next = S_PAD_AD;  // Empty AD still needs padding/permutation
        end
      end

      // AD loading
      S_LOAD_AD:
      begin
        if (word_cnt_r >= ((ad_length_r + 3) >> 2) - 1 || word_cnt_r == AD_WORDS - 1)
          state_next = S_PAD_AD;
      end

      S_PAD_AD:
        state_next = S_PERM_AD;

      S_PERM_AD:
      begin
        if (xoodoo_valid && !xoodoo_start_r)
        begin
          // Now go to data processing
          if (data_length_r > 0)
            state_next = S_LOAD_DATA;
          else
            state_next = S_PAD_DATA;  // Empty data still needs padding
        end
      end

      // Data loading
      S_LOAD_DATA:
      begin
        if (word_cnt_r >= ((data_length_r + 3) >> 2) - 1 || word_cnt_r == 3)
          state_next = S_PAD_DATA;
      end

      S_PAD_DATA:
        state_next = S_PERM_DATA;

      S_PERM_DATA:
      begin
        if (xoodoo_valid && !xoodoo_start_r)
        begin
          if (sel_type_r == MODE_AEAD_ENC)
            state_next = S_EXTRACT_TAG;
          else
            state_next = S_VERIFY_TAG;
        end
      end

      // Tag extraction (Encrypt)
      S_EXTRACT_TAG:
        if (word_cnt_r == TAG_WORDS - 1)
          state_next = S_DONE;

      // Tag verification (Decrypt)
      S_VERIFY_TAG:
        if (word_cnt_r == TAG_WORDS - 1)
          state_next = S_DONE;

      // Hash mode
      S_HASH_LOAD:
      begin
        if (data_length_r == 0 || word_cnt_r >= RHASH_WORDS - 1)
          state_next = S_HASH_PAD;
      end

      S_HASH_PAD:
        state_next = S_HASH_PERM1;

      S_HASH_PERM1:
        if (xoodoo_valid && !xoodoo_start_r)
          state_next = S_HASH_SQUEEZE1;

      S_HASH_SQUEEZE1:
        if (word_cnt_r == RHASH_WORDS - 1)
          state_next = S_HASH_PAD2;

      S_HASH_PAD2:
        state_next = S_HASH_PERM2;

      S_HASH_PERM2:
        if (xoodoo_valid && !xoodoo_start_r)
          state_next = S_HASH_SQUEEZE2;

      S_HASH_SQUEEZE2:
        if (word_cnt_r == RHASH_WORDS - 1)
          state_next = S_DONE;

      S_DONE:
        state_next = S_IDLE;

      default:
        state_next = S_IDLE;
    endcase
  end

  // =========================================================================
  // Word Counter
  // =========================================================================
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      word_cnt_r <= 0;
    end
    else if (restart)
    begin
      word_cnt_r <= 0;
    end
    else
    begin
      case (state_r)
        S_IDLE, S_PAD_NONCE, S_PAD_AD, S_PAD_DATA, S_HASH_PAD, S_HASH_PAD2,
        S_PERM_NONCE, S_PERM_AD, S_PERM_DATA, S_HASH_PERM1, S_HASH_PERM2, S_DONE:
          word_cnt_r <= 0;

        S_LOAD_KEY, S_LOAD_NONCE, S_LOAD_AD, S_LOAD_DATA,
        S_EXTRACT_TAG, S_VERIFY_TAG, S_HASH_LOAD, S_HASH_SQUEEZE1, S_HASH_SQUEEZE2:
          word_cnt_r <= word_cnt_r + 1;

        default:
          word_cnt_r <= word_cnt_r;
      endcase
    end
  end

  // =========================================================================
  // Latch Inputs
  // =========================================================================
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      key_r <= 128'b0;
      nonce_r <= 128'b0;
      ad_r <= 128'b0;
      data_in_r <= 128'b0;
      tag_in_r <= 128'b0;
      ad_length_r <= 0;
      data_length_r <= 0;
      sel_type_r <= 3'b0;
      domain_r <= 32'b0;
    end
    else if (restart)
    begin
      key_r <= 128'b0;
      nonce_r <= 128'b0;
      ad_r <= 128'b0;
      data_in_r <= 128'b0;
      tag_in_r <= 128'b0;
      ad_length_r <= 0;
      data_length_r <= 0;
      sel_type_r <= 3'b0;
      domain_r <= 32'b0;
    end
    else if (state_r == S_IDLE && ena)
    begin
      key_r <= key;
      nonce_r <= nonce;
      ad_r <= ad;
      data_in_r <= data_in;
      tag_in_r <= tag_in;
      ad_length_r <= ad_length;
      data_length_r <= data_length;
      sel_type_r <= sel_type;
      domain_r <= (sel_type == MODE_HASH) ? DOMAIN_ABSORB_HASH : DOMAIN_ABSORB_KEY;
    end
    else if (state_r == S_PAD_NONCE)
    begin
      // After nonce padding, domain transitions to DOMAIN_ABSORB for AD processing
      domain_r <= DOMAIN_ABSORB;
    end
    else if (state_r == S_PAD_AD)
    begin
      // After AD padding, domain transitions to DOMAIN_ZERO
      domain_r <= DOMAIN_ZERO;
    end
  end

  // =========================================================================
  // Xoodoo Control
  // =========================================================================
  always @(*)
  begin
    xoodoo_init = 1'b0;
    xoodoo_start_next = 1'b0;
    xoodoo_word_in = 32'b0;
    xoodoo_word_idx = word_cnt_r;
    xoodoo_word_en = 1'b0;
    xoodoo_domain = 32'b0;
    xoodoo_domain_en = 1'b0;

    case (state_r)
      S_IDLE:
      begin
        if (ena)
          xoodoo_init = 1'b1;
      end

      S_LOAD_KEY:
      begin
        xoodoo_word_in = get_word(key_r, word_cnt_r[1:0]);
        xoodoo_word_idx = word_cnt_r;
        xoodoo_word_en = 1'b1;
      end

      S_LOAD_NONCE:
      begin
        xoodoo_word_in = get_word(nonce_r, word_cnt_r[1:0]);
        xoodoo_word_idx = word_cnt_r;
        xoodoo_word_en = 1'b1;
      end

      S_PAD_NONCE:
      begin
        xoodoo_word_in = PADD_01_KEY_NONCE; // 0x110 - bits 4 and 8
        xoodoo_word_idx = KEY_WORDS + NPUB_WORDS;
        xoodoo_word_en = 1'b1;
        xoodoo_domain = domain_r;  // DOMAIN_ABSORB_KEY = 0x02
        xoodoo_domain_en = 1'b1;
        xoodoo_start_next = 1'b1;
        // Note: domain_r transitions to DOMAIN_ABSORB after this (handled in sequential)
      end

      S_LOAD_AD:
      begin
        xoodoo_word_in = get_word(ad_r, word_cnt_r[1:0]);
        xoodoo_word_idx = word_cnt_r;
        xoodoo_word_en = 1'b1;
      end

      S_PAD_AD:
      begin
        // PADD_01 goes to word at padding position, shifted to correct byte
        // For empty AD (ad_length_r=0), this puts 0x01 at word 0, byte 0
        xoodoo_word_in = 32'h01 << ({ad_length_r[1:0], 3'b000});
        xoodoo_word_idx = ad_length_r >> 2;
        xoodoo_word_en = 1'b1;
        // Domain: DOMAIN_ABSORB (0x03) XOR DOMAIN_CRYPT (0x80) = 0x83
        // After PADD_NONCE, domain_r should be DOMAIN_ABSORB
        xoodoo_domain = domain_r ^ DOMAIN_CRYPT;
        xoodoo_domain_en = 1'b1;
        xoodoo_start_next = 1'b1;
      end

      S_LOAD_DATA:
      begin
        // Encrypt: absorb PT; Decrypt: absorb PT = state XOR CT
        if (sel_type_r == MODE_AEAD_DEC)
          xoodoo_word_in = xoodoo_word_out ^ get_word(data_in_r, word_cnt_r[1:0]);
        else
          xoodoo_word_in = get_word(data_in_r, word_cnt_r[1:0]);
        xoodoo_word_idx = word_cnt_r;
        xoodoo_word_en = 1'b1;
      end

      S_PAD_DATA:
      begin
        // PADD_01 goes to word at padding position, shifted to correct byte
        xoodoo_word_in = 32'h01 << ({data_length_r[1:0], 3'b000});
        xoodoo_word_idx = data_length_r >> 2;
        xoodoo_word_en = 1'b1;
        xoodoo_domain = DOMAIN_SQUEEZE;  // 0x40
        xoodoo_domain_en = 1'b1;
        xoodoo_start_next = 1'b1;
      end

      S_HASH_LOAD:
      begin
        xoodoo_word_in = get_word(data_in_r, word_cnt_r[1:0]);
        xoodoo_word_idx = word_cnt_r;
        // Only enable if this is a full word-aligned load OR we are loading the partial last word
        // Actually S_HASH_PAD handles partial data MERGING via XOR if we write to same word
        // So always enable is fine, S_HASH_PAD will XOR 0x01 atop.
        xoodoo_word_en = (word_cnt_r < ((data_length_r + 3) >> 2));
      end

      S_HASH_PAD:
      begin
        // PADD_01 goes to word at padding position, shifted to correct byte
        xoodoo_word_in = 32'h01 << ({data_length_r[1:0], 3'b000});
        xoodoo_word_idx = data_length_r >> 2;
        xoodoo_word_en = 1'b1;
        xoodoo_domain = domain_r;  // Domain only
        xoodoo_domain_en = 1'b1;
        xoodoo_start_next = 1'b1;
      end

      S_HASH_PAD2:
      begin
        xoodoo_word_in = PADD_01;
        xoodoo_word_idx = 0;
        xoodoo_word_en = 1'b1;
        xoodoo_start_next = 1'b1;
      end

      default:
      begin
      end
    endcase
  end

  // =========================================================================
  // Collect Output Data (Encrypt/Decrypt)
  // =========================================================================
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      data_out_r <= 128'b0;
    end
    else if (restart)
    begin
      data_out_r <= 128'b0;
    end
    else if (state_r == S_LOAD_DATA)
    begin
      case (word_cnt_r[1:0])
        2'd0:
          data_out_r[127:96] <= byte_swap(xoodoo_word_out ^ get_word(data_in_r, 2'd0));
        2'd1:
          data_out_r[95:64]  <= byte_swap(xoodoo_word_out ^ get_word(data_in_r, 2'd1));
        2'd2:
          data_out_r[63:32]  <= byte_swap(xoodoo_word_out ^ get_word(data_in_r, 2'd2));
        2'd3:
          data_out_r[31:0]   <= byte_swap(xoodoo_word_out ^ get_word(data_in_r, 2'd3));
      endcase
    end
    else if (state_r == S_HASH_SQUEEZE2)
    begin
      case (word_cnt_r[1:0])
        2'd0:
          data_out_r[127:96] <= byte_swap(xoodoo_word_out);
        2'd1:
          data_out_r[95:64]  <= byte_swap(xoodoo_word_out);
        2'd2:
          data_out_r[63:32]  <= byte_swap(xoodoo_word_out);
        2'd3:
          data_out_r[31:0]   <= byte_swap(xoodoo_word_out);
      endcase
    end
  end

  // =========================================================================
  // Collect Tag Output
  // =========================================================================
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      tag_r <= 128'b0;
    end
    else if (restart)
    begin
      tag_r <= 128'b0;
    end
    else if (state_r == S_EXTRACT_TAG || state_r == S_VERIFY_TAG || state_r == S_HASH_SQUEEZE1)
    begin
      case (word_cnt_r[1:0])
        2'd0:
          tag_r[127:96] <= byte_swap(xoodoo_word_out);
        2'd1:
          tag_r[95:64]  <= byte_swap(xoodoo_word_out);
        2'd2:
          tag_r[63:32]  <= byte_swap(xoodoo_word_out);
        2'd3:
          tag_r[31:0]   <= byte_swap(xoodoo_word_out);
      endcase
    end
  end

  // =========================================================================
  // Tag Verification (Decrypt mode)
  // =========================================================================
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      valid_r <= 1'b1;
    end
    else if (restart)
    begin
      valid_r <= 1'b1;
    end
    else if (state_r == S_IDLE && ena)
    begin
      valid_r <= 1'b1;
    end
    else if (state_r == S_VERIFY_TAG)
    begin
      // Compare extracted tag word with input tag word
      // tag_in is in big-endian format (same as tag output)
      // xoodoo_word_out needs byte_swap to match
      case (word_cnt_r[1:0])
        2'd0:
          if (byte_swap(xoodoo_word_out) != tag_in_r[127:96])
            valid_r <= 1'b0;
        2'd1:
          if (byte_swap(xoodoo_word_out) != tag_in_r[95:64])
            valid_r <= 1'b0;
        2'd2:
          if (byte_swap(xoodoo_word_out) != tag_in_r[63:32])
            valid_r <= 1'b0;
        2'd3:
          if (byte_swap(xoodoo_word_out) != tag_in_r[31:0])
            valid_r <= 1'b0;
      endcase
    end
  end

  // =========================================================================
  // Output Registers
  // =========================================================================
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      done <= 1'b0;
      valid <= 1'b0;
      data_out <= 128'b0;
      tag <= 128'b0;
    end
    else if (restart)
    begin
      done <= 1'b0;
      valid <= 1'b0;
      data_out <= 128'b0;
      tag <= 128'b0;
    end
    else if (state_r == S_DONE)
    begin
      done <= 1'b1;
      valid <= (sel_type_r == MODE_AEAD_DEC) ? valid_r : 1'b1;
      data_out <= data_out_r;
      tag <= tag_r;
    end
    else if (state_r == S_IDLE)
    begin
      done <= 1'b0;
    end
  end

endmodule
