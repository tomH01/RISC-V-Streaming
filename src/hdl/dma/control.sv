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
  output logic                  dma_enable_o,
  output logic                  egress_enable_o,
  output logic [DATA_WIDTH-1:0] l2_bank_base_o,

  // Ingress IF
  output logic [N_STREAMS-1:0]       stream_en_o,
  output logic [ADDR_WIDTH-1:0]      window_size_o     [N_STREAMS],
  output logic [MACRO_PTR_WIDTH-1:0] start_macro_o     [N_STREAMS],

  // Egress IF
  output logic [N_STREAMS-1:0]    cfg_push_o,
  output logic [4*DATA_WIDTH-1:0] cfg_wdata_o [N_STREAMS],

  // Topology IF
  output logic [MACRO_PTR_WIDTH-1:0] next_pointer_o [M_MACROS],

  // Stream Generator IF
  output logic [DATA_WIDTH-1:0] stream_interval_o [N_STREAMS]
);
  logic  is_apb_space;
  assign is_apb_space = (paddr_i[27] == 1'b1);

  logic wr_en;
  assign pready_o  = is_apb_space & psel_i & penable_i;
  assign wr_en     = pready_o & pwrite_i;
  assign prdata_o  = '0;
  assign pslverr_o = 1'b0;

  logic [DATA_WIDTH-1:0] global_ctrl_q;
  logic [DATA_WIDTH-1:0] egress_enable_q;
  logic [DATA_WIDTH-1:0] l2_bank_base_q;

  logic [MACRO_PTR_WIDTH-1:0] start_macro_q     [N_STREAMS];
  logic [DATA_WIDTH-1:0]      window_size_q     [N_STREAMS];
  logic [N_STREAMS-1:0]       stream_en_q;
  logic [DATA_WIDTH-1:0]      egress_shadow_0_q [N_STREAMS];
  logic [DATA_WIDTH-1:0]      egress_shadow_1_q [N_STREAMS];
  logic [DATA_WIDTH-1:0]      egress_shadow_2_q [N_STREAMS];
  logic [N_STREAMS-1:0]       cfg_push_q;
  logic [4*DATA_WIDTH-1:0]    cfg_wdata_q       [N_STREAMS];

  logic [MACRO_PTR_WIDTH-1:0] next_pointer_q    [M_MACROS];

  logic [DATA_WIDTH-1:0] stream_interval_q [N_STREAMS];

  // 0x08000000 - 0x08000FFF: Global Configuration
  // 0x08001000 - 0x08001FFF: Stream Configurations
  // 0x08002000 - 0x08002FFF: Topology Configuration
  // 0x08003000 - 0x08003FFF: Stream Interval Configuration
  logic is_global_cfg, is_stream_cfg, is_topology, is_stream_interval;
  assign is_global_cfg      = (paddr_i[15:12] == 4'h0);
  assign is_stream_cfg      = (paddr_i[15:12] == 4'h1);
  assign is_topology        = (paddr_i[15:12] == 4'h2);
  assign is_stream_interval = (paddr_i[15:12] == 4'h3);

  logic [11:0] global_offset; 
  logic [6:0]  stream_idx;
  logic [4:0]  stream_offset;
  logic [9:0]  topology_word_idx;
  logic [9:0]  interval_word_idx;
  assign global_offset     = paddr_i[11:0];
  assign stream_idx        = paddr_i[11:5];
  assign stream_offset     = paddr_i[4:0];
  assign topology_word_idx = paddr_i[11:2];
  assign interval_word_idx = paddr_i[11:2];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      global_ctrl_q         <= '0;
      egress_enable_q       <= '0;
      l2_bank_base_q        <= '0;

      start_macro_q     <= '{default: '0};
      window_size_q     <= '{default: '0};
      stream_en_q       <= '{default: '0};
      egress_shadow_0_q <= '{default: '0};
      egress_shadow_1_q <= '{default: '0};
      egress_shadow_2_q <= '{default: '0};
      cfg_push_q        <= '{default: '0};
      cfg_wdata_q       <= '{default: '0};

      next_pointer_q    <= '{default: '0};

      stream_interval_q <= '{default: '0};
    end else begin
      cfg_push_q <= '{default: 1'b0}; 

      if (wr_en && is_apb_space) begin
        // Global Configuration
        if (is_global_cfg) begin
          case (global_offset)
            12'h00: global_ctrl_q         <= pwdata_i;
            12'h04: egress_enable_q       <= pwdata_i;
            12'h08: l2_bank_base_q        <= pwdata_i;
            default: ;
          endcase
        end

        // Stream Configurations
        else if (is_stream_cfg && (stream_idx < N_STREAMS)) begin
          case (stream_offset)
            5'h00: start_macro_q[stream_idx]     <= MACRO_PTR_WIDTH'(pwdata_i);
            5'h04: window_size_q[stream_idx]     <= pwdata_i;
            5'h08: stream_en_q[stream_idx]       <= pwdata_i[0];
            5'h10: egress_shadow_0_q[stream_idx] <= pwdata_i; 
            5'h14: egress_shadow_1_q[stream_idx] <= pwdata_i;
            5'h18: egress_shadow_2_q[stream_idx] <= pwdata_i;
            5'h1C: begin
              cfg_push_q[stream_idx]  <= 1'b1;
              cfg_wdata_q[stream_idx] <= {egress_shadow_0_q[stream_idx], egress_shadow_1_q[stream_idx], egress_shadow_2_q[stream_idx], pwdata_i};
            end
            default: ;
          endcase
        end

        // Topology Configuration
        else if (is_topology) begin
          automatic int macro_idx_0 = {topology_word_idx, 1'b0};
          automatic int macro_idx_1 = {topology_word_idx, 1'b1};

          if (macro_idx_0 < M_MACROS) next_pointer_q[macro_idx_0] <= MACRO_PTR_WIDTH'(pwdata_i[15:0]);
          if (macro_idx_1 < M_MACROS) next_pointer_q[macro_idx_1] <= MACRO_PTR_WIDTH'(pwdata_i[31:16]);
        end

        // Stream Interval Configuration
        else if (is_stream_interval) begin
          if (interval_word_idx < N_STREAMS) begin
            stream_interval_q[interval_word_idx] <= pwdata_i;
          end
        end

      end
    end
  end

  assign dma_enable_o    = global_ctrl_q[31];
  assign egress_enable_o = egress_enable_q[31];
  assign l2_bank_base_o  = l2_bank_base_q;

  assign stream_en_o   = stream_en_q;
  assign start_macro_o = start_macro_q;
  assign window_size_o = window_size_q;
  assign cfg_push_o    = cfg_push_q;
  assign cfg_wdata_o   = cfg_wdata_q;

  assign next_pointer_o = next_pointer_q;

  assign stream_interval_o = stream_interval_q;

endmodule
