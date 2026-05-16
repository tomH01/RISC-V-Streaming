import macro_state_pkg::*;

module dma_top #(
  parameter int N_STREAMS   = 4,
  parameter int M_MACROS    = 8,
  parameter int DATA_WIDTH  = 32,
  parameter int ADDR_WIDTH  = 32,
  parameter int W_WORKERS   = 1,
  parameter int MACRO_DEPTH = 256,

  localparam int MACRO_PTR_WIDTH = $clog2(M_MACROS),
  localparam int STREAM_PTR_WIDTH = $clog2(N_STREAMS),
)(
  input logic clk_i,
  input logic rst_ni

  // Stream IF
  input logic [DATA_WIDTH-1:0] stream_data_i  [N_STREAMS],
  input logic                  stream_valid_i [N_STREAMS],
  output logic                 stream_ready_o [N_STREAMS],


  // APB Target IF
  input logic                       penable_i,
  input logic                       pwrite_i,
  input logic [APB_ADDR_WIDTH-1:0]  paddr_i,
  input logic                       psel_i,
  input logic [APB_DATA_WIDTH-1:0]  pwdata_i,
  output logic [APB_DATA_WIDTH-1:0] prdata_o,
  output logic                      pready_o,
  output logic                      pslverr_o

  // TCDM Bus IF
  input  logic                  bus_ready_i,
  output logic                  bus_valid_o, 
  output logic [ADDR_WIDTH-1:0] bus_addr_o,
  output logic [DATA_WIDTH-1:0] bus_wdata_o
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
    .NB_READ_PORTS(NB_READ_PORTS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
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
    .start_bank_idx_o(cfg_start_bank_idx_o),
    .l2_bank_base_o(cfg_l2_bank_base_o),
    .bank_limit_b_o(cfg_bank_limit_b_o),
    .bank_header_size_b_o(cfg_bank_header_size_b_o),

    .stream_en_o(cfg_stream_en),
    .window_size_o(cfg_window_size),
    .start_macro_o(cfg_start_macro),

    .cfg_push_o(cfg_push),
    .cfg_wdata_o(cfg_wdata),

    .next_pointer_o(cfg_next_pointer)
  );


  // ###########
  // Ingress

  logic [M_MACROS-1:0]   ingress_gnt;
  logic [M_MACROS-1:0]   ingress_done;
  logic [M_MACROS-1:0]   ingress_req;
  logic [ADDR_WIDTH-1:0] ingress_addr  [M_MACROS];
  logic [DATA_WIDTH-1:0] ingress_wdata [M_MACROS];
  logic [3:0]            ingress_be    [M_MACROS];

  logic [N_STREAMS-1:0]        notify_valid;
  logic [MACRO_PTR_WIDTH-1:0]  notify_start_macro [N_STREAMS];

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

    .bp_gnt_i(ingress_gnt),
    .bp_done_o(ingress_done),
    .bp_req_o(ingress_req),
    .bp_addr_o(ingress_addr),
    .bp_wdata_o(ingress_wdata),
    .bp_be_o(ingress_be),

    .cfg_stream_en_i(cfg_stream_en),
    .cfg_window_size_i(cfg_window_size),
    .cfg_start_macro_i(cfg_start_macro),
    .cfg_next_pointer_i(cfg_next_pointer),

    .notify_valid_o(notify_valid),
    .notify_start_macro_o(notify_start_macro)
  );


  // ##########
  // Egress

  logic [NB_READ_PORTS-1:0]    egress_gnt;
  logic [NB_READ_PORTS-1:0]    egress_r_opc;
  logic [DATA_WIDTH-1:0]       egress_r_rdata      [NB_READ_PORTS];
  logic [NB_READ_PORTS-1:0]    egress_r_valid;
  logic [M_MACROS-1:0]         egress_release;
  logic [NB_READ_PORTS-1:0]    egress_req;
  logic [ADDR_WIDTH-1:0]       egress_addr         [NB_READ_PORTS];
  logic [MACRO_PTR_WIDTH-1:0]  egress_macro_select [NB_READ_PORTS];

  egress_top #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .NB_READ_PORTS(NB_READ_PORTS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_egress_top (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .notify_valid_i(notify_valid),
    .notify_start_macro_i(notify_start_macro),

    .bp_gnt_i(egress_gnt),
    .bp_r_opc_o(egress_r_opc),
    .bp_r_rdata_o(egress_r_rdata),
    .bp_r_valid_o(egress_r_valid),
    .bp_release_o(egress_release),
    .bp_req_o(egress_req),
    .bp_addr_o(egress_addr),
    .bp_macro_select_o(egress_macro_select),
    .switch_state_o(),

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
    .NB_READ_PORTS(NB_READ_PORTS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .MACRO_DEPTH(MACRO_DEPTH)
  ) u_buffer_pool (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .ingress_done_i(ingress_done),
    .ingress_req_i(ingress_req),
    .ingress_addr_i(ingress_addr),
    .ingress_wdata_i(ingress_wdata),
    .ingress_be_i(ingress_be),
    .ingress_gnt_o(ingress_gnt),

    .egress_release_i(egress_release),
    .egress_req_i(egress_req),
    .egress_addr_i(egress_addr),
    .egress_macro_select_i(egress_macro_select),
    .egress_gnt_o(egress_gnt),
    .egress_r_opc_o(egress_r_opc),
    .egress_r_rdata_o(egress_r_rdata),
    .egress_r_valid_o(egress_r_valid)
  );
endmodule
