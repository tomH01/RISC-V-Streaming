module control #(
  parameter int N_STREAMS     = 4,
  parameter int M_MACROS      = 8,
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,
  parameter int MACRO_DEPTH   = 256,
  parameter int B_BANKS       = 2,

  localparam int MACRO_PTR_WIDTH = $clog2(M_MACROS),
  localparam int BANK_PTR_WIDTH  = $clog2(B_BANKS)
)(
  input logic clk_i,
  input logic rst_ni,

  // APB IF
  input logic 					        penable_i,
  input logic 					        pwrite_i,
  input logic  [ADDR_WIDTH-1:0] paddr_i,
  input logic                   psel_i,
  input logic  [DATA_WIDTH-1:0] pwdata_i,
  output logic [DATA_WIDTH-1:0] prdata_o,
  output logic 					        pready_o,
  output logic 					        pslverr_o,

  // Global Control IF
  output logic                      dma_enable_o,
  output logic [BANK_PTR_WIDTH-1:0] start_bank_idx_o,
  output logic [DATA_WIDTH-1:0]     l2_bank_base_o [B_BANKS],
  output logic [DATA_WIDTH-1:0]     bank_limit_b_o,
  output logic [DATA_WIDTH-1:0]     bank_header_size_b_o,

  // Ingress IF
  output logic [N_STREAMS-1:0]       stream_en_o,
  output logic [ADDR_WIDTH-1:0]      window_size_o  [N_STREAMS],
  output logic [MACRO_PTR_WIDTH-1:0] start_macro_o  [N_STREAMS],

  // Egress IF
  output logic [N_STREAMS-1:0]    cfg_push_o,
  output logic [4*DATA_WIDTH-1:0] cfg_wdata_o [N_STREAMS],

  // Topology IF
  output logic [MACRO_PTR_WIDTH-1:0] next_pointer_o [M_MACROS]
);

  logic wr_en;
  assign wr_en = psel_i & penable_i & pwrite_i;
  assign pready_o = 1'b1;
  assign pslverr_o = 1'b0;

  logic [DATA_WIDTH-1:0] global_ctrl_q;
  logic [DATA_WIDTH-1:0] l2_bank_base_q [B_BANKS];
  logic [DATA_WIDTH-1:0] bank_limit_b_q;
  logic [DATA_WIDTH-1:0] bank_header_size_b_q;

  logic [MACRO_PTR_WIDTH-1:0] start_macro_q     [N_STREAMS];
  logic [DATA_WIDTH-1:0]      window_size_q     [N_STREAMS];
  logic [N_STREAMS-1:0]       stream_en_q;
  logic [DATA_WIDTH-1:0]      egress_shadow_0_q [N_STREAMS];
  logic [DATA_WIDTH-1:0]      egress_shadow_1_q [N_STREAMS];
  logic [DATA_WIDTH-1:0]      egress_shadow_2_q [N_STREAMS];
  logic [N_STREAMS-1:0]       cfg_push_q;
  logic [4*DATA_WIDTH-1:0]    cfg_wdata_q       [N_STREAMS];

  logic [MACRO_PTR_WIDTH-1:0] next_pointer_q    [M_MACROS];

  // 0x0000 - 0x0FFF: Global Configuration
  // 0x1000 - 0x1FFF: Stream Configurations
  // 0x2000 - 0x2FFF: Topology Configuration
  logic is_global_cfg, is_stream_cfg, is_topology;
  assign is_global_cfg = (paddr_i[31:12] == 20'h000);
  assign is_stream_cfg = (paddr_i[31:12] == 20'h001);
  assign is_topology   = (paddr_i[31:12] == 20'h002);

  logic [11:0] global_offset; 
  logic [5:0]  stream_idx;
  logic [5:0]  stream_offset;
  logic [9:0] topology_word_idx;
  assign global_offset     = paddr_i[11:0];
  assign stream_idx        = paddr_i[11:6];
  assign stream_offset     = paddr_i[5:0];
  assign topology_word_idx = paddr_i[11:2];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      global_ctrl_q        <= '0;
      l2_bank_base_q       <= '{default: '0};
      bank_limit_b_q       <= '0;
      bank_header_size_b_q <= '0; 

      start_macro_q     <= '{default: '0};
      window_size_q     <= '{default: '0};
      stream_en_q       <= '{default: '0};
      egress_shadow_0_q <= '{default: '0};
      egress_shadow_1_q <= '{default: '0};
      egress_shadow_2_q <= '{default: '0};
      cfg_push_q        <= '{default: '0};
      cfg_wdata_q       <= '{default: '0};

      next_pointer_q    <= '{default: '0};
    end else begin
      cfg_push_q <= '{default: 1'b0}; 
      if (wr_en) begin
        // Global Configuration
        if (is_global_cfg) begin
          case (global_offset)
            12'h00: global_ctrl_q        <= pwdata_i;
            12'h04: l2_bank_base_q[0]    <= pwdata_i;
            12'h08: l2_bank_base_q[1]    <= pwdata_i;
            12'h0C: bank_limit_b_q       <= pwdata_i;
            12'h10: bank_header_size_b_q <= pwdata_i;
            default: ;
          endcase
        end

        // Stream Configurations
        else if (is_stream_cfg && (stream_idx < N_STREAMS)) begin
          case (stream_offset)
            6'h00: start_macro_q[stream_idx]     <= MACRO_PTR_WIDTH'(pwdata_i);
            6'h04: window_size_q[stream_idx]     <= pwdata_i;
            6'h08: stream_en_q[stream_idx]       <= pwdata_i[0];
            6'h10: egress_shadow_0_q[stream_idx] <= pwdata_i; 
            6'h14: egress_shadow_1_q[stream_idx] <= pwdata_i;
            6'h18: egress_shadow_2_q[stream_idx] <= pwdata_i;
            default: ;
          endcase

          if (stream_offset == 6'h1C) begin
            cfg_push_q[stream_idx]  <= 1'b1;
            cfg_wdata_q[stream_idx] <= {egress_shadow_0_q[stream_idx], egress_shadow_1_q[stream_idx], egress_shadow_2_q[stream_idx], pwdata_i};
          end else begin
            cfg_push_q[stream_idx]  <= 1'b0;
          end
        end

        // Topology Configuration
        else if (is_topology) begin
          automatic int macro_idx_0 = {topology_word_idx, 1'b0};
          automatic int macro_idx_1 = {topology_word_idx, 1'b1};

          if (macro_idx_0 < M_MACROS) next_pointer_q[macro_idx_0] <= MACRO_PTR_WIDTH'(pwdata_i[15:0]);
          if (macro_idx_1 < M_MACROS) next_pointer_q[macro_idx_1] <= MACRO_PTR_WIDTH'(pwdata_i[31:16]);
        end

      end
    end
  end

  assign dma_enable_o         = global_ctrl_q[0];
  assign start_bank_idx_o     = global_ctrl_q[1];
  assign l2_bank_base_o       = l2_bank_base_q;
  assign bank_limit_b_o       = bank_limit_b_q;
  assign bank_header_size_b_o = bank_header_size_b_q;

  assign stream_en_o   = stream_en_q;
  assign start_macro_o = start_macro_q;
  assign window_size_o = window_size_q;
  assign cfg_push_o    = cfg_push_q;
  assign cfg_wdata_o   = cfg_wdata_q;

  assign next_pointer_o = next_pointer_q;

endmodule
