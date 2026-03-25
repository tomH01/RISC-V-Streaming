module dma_top #(
  parameter int N_STREAMS     = 4,
  parameter int M_MACROS      = 8,
  parameter int NB_READ_PORTS = 1,
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,
  parameter int MACRO_DEPTH   = 256
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

  // TCDM Initiator IF



);
// #######
// Control

logic [N_STREAMS-1:0]                    cfg_stream_en;
logic [$clog2(MACRO_DEPTH*M_MACROS)-1:0] cfg_window_size  [N_STREAMS];
logic [$clog2(M_MACROS)-1:0]             cfg_start_macro  [N_STREAMS];
logic [$clog2(M_MACROS)-1:0]             cfg_next_pointer [M_MACROS];

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

  .stream_en_o(cfg_stream_en),
  .window_size_o(cfg_window_size),
  .start_macro_o(cfg_start_macro),
  .next_point_o(cfg_next_pointer)

  // Egress IF
);


// ###########
// Ingress

logic [M_MACROS-1:0]   ingress_gnt;
logic [M_MACROS-1:0]   ingress_req;
logic [ADDR_WIDTH-1:0] ingress_addr  [M_MACROS];
logic [DATA_WIDTH-1:0] ingress_wdata [M_MACROS];
logic [3:0]            ingress_be    [M_MACROS];

logic [N_STREAMS-1:0]        notify_valid;
logic [$clog2(M_MACROS)-1:0] notify_start_macro [N_STREAMS];

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
logic [NB_READ_PORTS-1:0]    egress_req;
logic [ADDR_WIDTH-1:0]       egress_addr         [NB_READ_PORTS];
logic [$clog2(M_MACROS)-1:0] egress_macro_select [NB_READ_PORTS];

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
  .bp_req_o(egress_req),
  .bp_addr_o(egress_addr),
  .bp_macro_select_o(egress_macro_select)  
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

  .macro_owner_i(), 

  .ingress_req_i(ingress_req),
  .ingress_addr_i(ingress_addr),
  .ingress_wdata_i(ingress_wdata),
  .ingress_be_i(ingress_be),
  .ingress_gnt_o(ingress_gnt)

  .egress_req_i(egress_req),
  .egress_addr_i(egress_addr),
  .egress_macro_select_i(egress_macro_select),
  .egress_gnt_o(egress_gnt),
  .egress_r_opc_o(egress_r_opc),
  .egress_r_rdata_o(egress_r_rdata),
  .egress_r_valid_o(egress_r_valid)
);
endmodule
