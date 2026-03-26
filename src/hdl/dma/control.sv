module control #(
  parameter int N_STREAMS     = 4,
  parameter int M_MACROS      = 8,
  parameter int NB_READ_PORTS = 1,
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,

  localparam int MACRO_PTR_WIDTH = $clog2(M_MACROS)
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

  // Ingress IF
  output logic [N_STREAMS-1:0]        stream_en_o,
  output logic [ADDR_WIDTH-1:0]       window_size_o,
  output logic [MACRO_PTR_WIDTH-1:0]  start_macro_o  [N_STREAMS],
  output logic [MACRO_PTR_WIDTH-1:0]  next_pointer_o [M_MACROS]

  // Egress IF
  output logic                    cfg_push_o  [N_STREAMS],
  output logic [3*DATA_WIDTH-1:0] cfg_wdata_o [N_STREAMS]
);
  logic wr_en;
  assign wr_en = psel_i & penable_i & pwrite_i;
  assign pready_o = 1'b1;
  assign pslverr_o = 1'b0;

  logic [DATA_WIDTH-1:0] ingress_ctrl_q    [N_STREAMS];
  logic [DATA_WIDTH-1:0] window_size_q     [N_STREAMS];
  logic [DATA_WIDTH-1:0] egress_shadow_0_q [N_STREAMS];
  logic [DATA_WIDTH-1:0] egress_shadow_1_q [N_STREAMS];

  logic [MACRO_PTR_WIDTH-1:0] next_pointer_q [M_MACROS];

  logic [DATA_WIDTH-1:0] cq_base_addr_q [N_STREAMS];
  logic [DATA_WIDTH-1:0] cq_size_q      [N_STREAMS];


  // 0x1000 - 0x1FFF: Stream Configurations
  // 0x2000 - 0x2FFF: Topology Configuration
  logic is_stream_cfg, is_topology;
  assign is_stream_cfg = (paddr_i[31:12] == 20'h001);
  assign is_topology   = (paddr_i[31:12] == 20'h002);

  // Stream Configurations
  logic [5:0] stream_idx;
  logic [5:0] stream_offset;
  assign stream_idx    = paddr_i[11:6];
  assign stream_offset = paddr_i[5:0];

  // Topology Configuration
  logic [11:0] topology_word_idx;
  assign topology_word_idx = paddr_i[11:2];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ingress_ctrl_q    <= '(default: '0);
      window_size_q     <= '(default: '0);
      egress_shadow_0_q <= '(default: '0);
      egress_shadow_1_q <= '(default: '0);
      cq_base_addr_q    <= '(default: '0);
      cq_size_q         <= '(default: '0);

      next_pointer_q <= '(default: '0);
    end else if (wr_en) begin
      // Stream Configurations
      if (is_stream_cfg && (stream_idx < N_STREAMS)) begin
        case (stream_offset)
          6'h00: ingress_ctrl_q[stream_idx]    <= pwdata_i;
          6'h04: window_size_q[stream_idx]     <= pwdata_i;
          6'h10: egress_shadow_0_q[stream_idx] <= pwdata_i; 
          6'h14: egress_shadow_1_q[stream_idx] <= pwdata_i;

          6'h20: cq_base_addr_q[stream_idx] <= pwdata_i;
          6'h24: cq_size_q[stream_idx]      <= pwdata_i;

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

    end
  end

  generate
    for (genvar i = 0; i < N_STREAMS; i++) begin
      assign stream_en_o[i]   = ingress_ctrl_q[i][0];
      assign start_macro_o[i] = MACRO_PTR_WIDTH'(ingress_ctrl_q[i][31:16]);
      assign window_size_o[i] = window_size_q[i];

      assign cfg_push_o[i] = wr_en & is_stream_cfg & (stream_idx == i) & (stream_offset == 6'h18);

      assign cfg_wdata_o[i] = {pwdata_i, egress_shadow_1_q[i], egress_shadow_0_q[i]};

      for (genvar m = 0; m < M_MACROS; m++) begin
        assign next_pointer_o[m] = next_pointer_q[m][MACRO_PTR_WIDTH-1:0];
      end 
    end
  endgenerate

endmodule
