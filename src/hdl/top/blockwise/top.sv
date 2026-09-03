module top_blockwise #(
  parameter int N_STREAMS           = 4,
  parameter int M_MACROS            = 8,
  parameter int DATA_WIDTH          = 32,
  parameter int ADDR_WIDTH          = 32,
  parameter int W_WORKERS           = 1,
  parameter int B_BANKS             = 2,
  parameter int MACRO_DEPTH         = 256,
  parameter int BANK_DEPTH          = 16384,
  parameter int STREAM_OFFSET_WIDTH = 10,

  localparam int MACRO_PTR_WIDTH    = $clog2(M_MACROS),
  localparam int BANK_PTR_WIDTH     = $clog2(B_BANKS),
  localparam int DATA_WIDTH_BYTES   = DATA_WIDTH / 8,
  localparam int CPU_MANAGER        = 1,
  localparam int META_MANAGER       = 1,
  localparam int DMA_MANAGERS       = W_WORKERS + META_MANAGER,
  localparam int NUM_MANAGERS       = DMA_MANAGERS + CPU_MANAGER,
  localparam int MASTER_PTR_WIDTH   = $clog2(NUM_MANAGERS)
)(
  input logic clk_i,
  input logic rst_ni,

  // APB Subordinate IF
  input logic                   penable_i,
  input logic                   pwrite_i,
  input logic  [ADDR_WIDTH-1:0] paddr_i,
  input logic                   psel_i,
  input logic  [DATA_WIDTH-1:0] pwdata_i,
  output logic [DATA_WIDTH-1:0] prdata_o,
  output logic                  pready_o,
  output logic                  pslverr_o,

  // Data IF
  input  logic                        data_req_i,
  output logic                        data_gnt_o,
  input  logic [ADDR_WIDTH-1:0]       data_addr_i,
  input  logic [DATA_WIDTH-1:0]       data_wdata_i,
  input  logic [DATA_WIDTH_BYTES-1:0] data_be_i,
  input  logic                        data_we_i,

  output logic [DATA_WIDTH-1:0] data_r_rdata_o,
  output logic                  data_r_valid_o,

  // Bank Full IRQ
  output logic [B_BANKS-1:0] bank_full_o
);

  // DMA

  logic [DMA_MANAGERS-1:0] dma_ready;
  logic [DMA_MANAGERS-1:0] dma_valid;
  logic [ADDR_WIDTH-1:0]   dma_addr  [DMA_MANAGERS];
  logic [DATA_WIDTH-1:0]   dma_wdata [DMA_MANAGERS];

  dma_top #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .W_WORKERS(W_WORKERS),
    .B_BANKS(B_BANKS),
    .MACRO_DEPTH(MACRO_DEPTH),
    .BANK_DEPTH(BANK_DEPTH),
    .STREAM_OFFSET_WIDTH(STREAM_OFFSET_WIDTH)
  ) u_dma_top (
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

    .bus_ready_i(dma_ready),
    .bus_valid_o(dma_valid),
    .bus_addr_o(dma_addr),
    .bus_wdata_o(dma_wdata),

    .bank_full_o(bank_full_o)
  );

  // L2 Subsystem

  logic internal_wen;
  assign internal_wen = ~data_we_i;

  l2_subsystem #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .W_WORKERS(W_WORKERS),
    .B_BANKS(B_BANKS),
    .BANK_DEPTH(BANK_DEPTH),
    .DMA_MANAGERS(DMA_MANAGERS)
  ) u_l2_subsystem (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .dma_ready_o(dma_ready),
    .dma_valid_i(dma_valid),
    .dma_addr_i(dma_addr),
    .dma_wdata_i(dma_wdata),

    .cpu_ready_o(data_gnt_o),
    .cpu_valid_i(data_req_i),
    .cpu_addr_i(data_addr_i),
    .cpu_wdata_i(data_wdata_i),
    .cpu_be_i(data_be_i),
    .cpu_wen_i(internal_wen),

    .cpu_r_rdata_o(data_r_rdata_o),
    .cpu_r_valid_o(data_r_valid_o)
  );


endmodule
