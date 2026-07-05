module alloc_manager #(
  parameter int N_STREAMS   = 4,
  parameter int M_MACROS    = 16,
  parameter int DATA_WIDTH  = 32,
  parameter int ADDR_WIDTH  = 32,
  parameter int MACRO_DEPTH = 256,

  localparam int MACRO_PTR_WIDTH = $clog2(M_MACROS),
  localparam int DATA_WIDTH_BYTES = DATA_WIDTH / 8
)(
  input logic clk_i,
  input logic rst_ni,

  // Control IF
  input logic [N_STREAMS-1:0]       cfg_stream_en_i,
  input logic [DATA_WIDTH-1:0]      cfg_window_size_i  [N_STREAMS],
  input logic [MACRO_PTR_WIDTH-1:0] cfg_start_macro_i  [N_STREAMS],
  input logic [MACRO_PTR_WIDTH-1:0] cfg_next_pointer_i [M_MACROS],

  // Stream IF
  input logic [N_STREAMS-1:0]        stream_valid_i,
  input logic [N_STREAMS-1:0]        stream_gnt_i,

  // Ingress Crossbar IF
  output logic [MACRO_PTR_WIDTH-1:0] am_macro_sel_o [N_STREAMS],
  output logic [N_STREAMS-1:0]       am_req_o,
  output logic [ADDR_WIDTH-1:0]      am_addr_o       [N_STREAMS],

  // Buffer Pool IF
  output logic  [M_MACROS-1:0] done_o,

  // Egress IF
  output logic [N_STREAMS-1:0]       window_valid_o,
  output logic [MACRO_PTR_WIDTH-1:0] window_start_o [N_STREAMS]
);

  logic [MACRO_PTR_WIDTH-1:0]              current_macro_q        [N_STREAMS];
  logic [MACRO_PTR_WIDTH-1:0]              current_window_start_q [N_STREAMS];
  logic [$clog2(MACRO_DEPTH)-1:0]          macro_word_cnt_q       [N_STREAMS];
  logic [$clog2(MACRO_DEPTH*M_MACROS)-1:0] window_word_cnt_q      [N_STREAMS];
  logic [N_STREAMS-1:0]                    is_initialized_q;

  logic [N_STREAMS-1:0] handshake;
  logic [N_STREAMS-1:0] window_end;
  logic [N_STREAMS-1:0] macro_end;

  // Done Logic
  always_comb begin
    done_o = '0;

    for (int n = 0; n < N_STREAMS; n++) begin
      if (cfg_stream_en_i[n] && is_initialized_q[n] && window_end[n]) begin
        done_o[current_macro_q[n]] = 1'b1;
      end
    end
  end

  // Allocation Logic
  genvar n;
  generate
    for (n = 0; n < N_STREAMS; n++) begin

      always_comb begin
        handshake[n]  = stream_valid_i[n] & stream_gnt_i[n];
        macro_end[n]  = handshake[n] && (macro_word_cnt_q[n] == MACRO_DEPTH - 1);
        window_end[n] = handshake[n] && (window_word_cnt_q[n] == cfg_window_size_i[n] - 1);

        am_req_o[n]       = stream_valid_i[n] & cfg_stream_en_i[n] & is_initialized_q[n];
        am_addr_o[n]      = ADDR_WIDTH'(macro_word_cnt_q[n]) * DATA_WIDTH_BYTES;
        am_macro_sel_o[n] = current_macro_q[n];
      end

      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          current_macro_q[n] <= '{default: '0};
          current_window_start_q[n] <= '{default: '0};
          macro_word_cnt_q[n] <= '{default: '0};
          window_word_cnt_q[n] <= '{default: '0};
          is_initialized_q[n] <= 1'b0;
          window_valid_o[n] <= 1'b0;
          window_start_o[n] <= '{default: '0};

        end else begin
          // Init
          if (cfg_stream_en_i[n] && !is_initialized_q[n] && cfg_window_size_i[n] != '0) begin
            current_macro_q[n]        <= cfg_start_macro_i[n];
            current_window_start_q[n] <= cfg_start_macro_i[n];
            macro_word_cnt_q[n]       <= '{default: '0};
            window_word_cnt_q[n]      <= '{default: '0};
            is_initialized_q[n]       <= 1'b1;
            window_valid_o[n]         <= 1'b0;
            window_start_o[n]         <= '{default: '0};
          end

          // Deactivate Stream 
          else if (!cfg_stream_en_i[n]) begin
            is_initialized_q[n] <= 1'b0; 
          end

          // Default Operation
          else if (is_initialized_q[n]) begin
            window_valid_o[n] <= 1'b0;
            window_start_o[n] <= '{default: '0};

            if (window_end[n]) begin
              // Window full
              window_valid_o[n] <= 1'b1;
              window_start_o[n] <= current_window_start_q[n];

              current_macro_q[n]        <= cfg_next_pointer_i[current_macro_q[n]];
              current_window_start_q[n] <= cfg_next_pointer_i[current_macro_q[n]];
              
              macro_word_cnt_q[n] <= '0;
              window_word_cnt_q[n] <= '0;
          
            end else if (macro_end[n]) begin
              // Macro full
              current_macro_q[n] <= cfg_next_pointer_i[current_macro_q[n]];
              macro_word_cnt_q[n] <= '0;
              window_word_cnt_q[n] <= window_word_cnt_q[n] + 1;

            end else if (handshake[n]) begin
              // Default Write
              macro_word_cnt_q[n] <= macro_word_cnt_q[n] + 1;
              window_word_cnt_q[n] <= window_word_cnt_q[n] + 1;
            end    
          
          end
        end
      end
    end    
  endgenerate
endmodule