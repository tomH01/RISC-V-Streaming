module dma_top #(
  parameter int N_STREAMS   = 4,
  parameter int M_MACROS    = 8,
  parameter int DATA_WIDTH  = 32,
  parameter int ADDR_WIDTH  = 32,
  parameter int W_WORKERS   = 1,
  parameter int B_BANKS     = 2,
  parameter int MACRO_DEPTH = 256,

  localparam int MACRO_PTR_WIDTH  = $clog2(M_MACROS),
  localparam int STREAM_PTR_WIDTH = $clog2(N_STREAMS),
  localparam int BANK_PTR_WIDTH   = $clog2(B_BANKS)
)(
  input logic clk_i,
  input logic rst_ni,

  // Stream IF
  input logic [DATA_WIDTH-1:0] stream_data_i  [N_STREAMS],
  input logic                  stream_valid_i [N_STREAMS],
  output logic                 stream_ready_o [N_STREAMS],


  // APB Target IF
  input logic                   penable_i,
  input logic                   pwrite_i,
  input logic  [ADDR_WIDTH-1:0] paddr_i,
  input logic                   psel_i,
  input logic  [DATA_WIDTH-1:0] pwdata_i,
  output logic [DATA_WIDTH-1:0] prdata_o,
  output logic                  pready_o,
  output logic                  pslverr_o,

  // TCDM Bus IF
  input  logic                  bus_ready_i [W_WORKERS],
  output logic                  bus_valid_o [W_WORKERS],
  output logic [ADDR_WIDTH-1:0] bus_addr_o  [W_WORKERS],
  output logic [DATA_WIDTH-1:0] bus_wdata_o [W_WORKERS]
);

  // #######
  // Control

  logic                       cfg_dma_enable;  
  logic [BANK_PTR_WIDTH-1:0]  cfg_start_bank_idx;
  logic [DATA_WIDTH-1:0]      cfg_l2_bank_base [B_BANKS];
  logic [DATA_WIDTH-1:0]      cfg_bank_limit_b;
  logic [DATA_WIDTH-1:0]      cfg_bank_header_size_b;
  logic [N_STREAMS-1:0]       cfg_stream_en;
  logic [ADDR_WIDTH-1:0]      cfg_window_size  [N_STREAMS];
  logic [MACRO_PTR_WIDTH-1:0] cfg_start_macro  [N_STREAMS];
  logic [N_STREAMS-1:0]       cfg_push;
  logic [4*DATA_WIDTH-1:0]    cfg_wdata        [N_STREAMS];
  logic [MACRO_PTR_WIDTH-1:0] cfg_next_pointer [M_MACROS];

  control #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .MACRO_DEPTH(MACRO_DEPTH),
    .B_BANKS(B_BANKS)
  ) u_control (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .penable_i(penable_i),
    .pwrite_i(pwrite_i),
    .paddr_i(paddr_i),
    .psel_i(psel_i),
    .pwdata_i(pwdata_i),
    .prdata_o(prdata_o),
    .pready_o(pready_o),
    .pslverr_o(pslverr_o),

    .dma_enable_o(cfg_dma_enable),
    .start_bank_idx_o(cfg_start_bank_idx),
    .l2_bank_base_o(cfg_l2_bank_base),
    .bank_limit_b_o(cfg_bank_limit_b),
    .bank_header_size_b_o(cfg_bank_header_size_b),

    .stream_en_o(cfg_stream_en),
    .window_size_o(cfg_window_size),
    .start_macro_o(cfg_start_macro),

    .cfg_push_o(cfg_push),
    .cfg_wdata_o(cfg_wdata),

    .next_pointer_o(cfg_next_pointer)
  );


  // ###########
  // Ingress

  logic [M_MACROS-1:0]   ingr_gnt;
  logic [M_MACROS-1:0]   ingr_done;
  logic [M_MACROS-1:0]   ingr_req;
  logic [ADDR_WIDTH-1:0] ingr_addr  [M_MACROS];
  logic [DATA_WIDTH-1:0] ingr_wdata [M_MACROS];
  logic [3:0]            ingr_be    [M_MACROS];

  logic [N_STREAMS-1:0]        notif_valid;
  logic [MACRO_PTR_WIDTH-1:0]  notif_start_macro [N_STREAMS];

  ingress_top #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .MACRO_DEPTH(MACRO_DEPTH)
  ) u_ingress_top (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .stream_data_i(stream_data_i),
    .stream_valid_i(stream_valid_i),
    .stream_ready_o(stream_ready_o),

    .bp_gnt_i(ingr_gnt),
    .bp_done_o(ingr_done),
    .bp_req_o(ingr_req),
    .bp_addr_o(ingr_addr),
    .bp_wdata_o(ingr_wdata),
    .bp_be_o(ingr_be),

    .cfg_stream_en_i(cfg_stream_en),
    .cfg_window_size_i(cfg_window_size),
    .cfg_start_macro_i(cfg_start_macro),
    .cfg_next_pointer_i(cfg_next_pointer),

    .notif_valid_o(notif_valid),
    .notif_start_macro_o(notif_start_macro)
  );


  // ##########
  // Egress

  logic [W_WORKERS-1:0]       egr_gnt;
  logic [DATA_WIDTH-1:0]      egr_r_rdata      [W_WORKERS];
  logic [W_WORKERS-1:0]       egr_r_valid;
  logic [M_MACROS-1:0]        egr_release;
  logic [W_WORKERS-1:0]       egr_req;
  logic [ADDR_WIDTH-1:0]      egr_addr         [W_WORKERS];
  logic [MACRO_PTR_WIDTH-1:0] egr_macro_select [W_WORKERS];

  egress_top #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .W_WORKERS(W_WORKERS),
    .B_BANKS(B_BANKS)
  ) u_egress_top (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .notif_valid_i(notif_valid),
    .notif_start_macro_i(notif_start_macro),

    .bp_gnt_i(egr_gnt),
    .bp_r_rdata_o(egr_r_rdata),
    .bp_r_valid_o(egr_r_valid),
    .bp_release_o(egr_release),
    .bp_req_o(egr_req),
    .bp_addr_o(egr_addr),
    .bp_macro_sel_o(egr_macro_select),

    .start_bank_idx_i(cfg_start_bank_idx),
    .l2_bank_base_i(cfg_l2_bank_base),
    .bank_limit_b_i(cfg_bank_limit_b),
    .bank_header_size_b_i(cfg_bank_header_size_b),

    .stream_en_i(cfg_stream_en),
    .window_size_i(cfg_window_size),
    .start_macro_i(cfg_start_macro),
    .next_pointer_i(cfg_next_pointer),

    .cfg_push_i(cfg_push),
    .cfg_wdata_i(cfg_wdata),

    .bus_ready_i(bus_ready_i),
    .bus_valid_o(bus_valid_o),
    .bus_addr_o(bus_addr_o),
    .bus_wdata_o(bus_wdata_o)
  );


  // ###########
  // Buffer Pool
  buffer_pool #(
    .M_MACROS(M_MACROS),
    .NUM_READ_PORTS(W_WORKERS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .MACRO_DEPTH(MACRO_DEPTH)
  ) u_buffer_pool (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .ingr_done_i(ingr_done),
    .ingr_req_i(ingr_req),
    .ingr_addr_i(ingr_addr),
    .ingr_wdata_i(ingr_wdata),
    .ingr_be_i(ingr_be),
    .ingr_gnt_o(ingr_gnt),

    .egr_release_i(egr_release),
    .egr_req_i(egr_req),
    .egr_addr_i(egr_addr),
    .egr_macro_select_i(egr_macro_select),
    .egr_gnt_o(egr_gnt),
    .egr_r_rdata_o(egr_r_rdata),
    .egr_r_valid_o(egr_r_valid)
  );
endmodule
