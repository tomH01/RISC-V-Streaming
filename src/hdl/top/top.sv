module top #(
  parameter int N_STREAMS           = 4,
  parameter int M_MACROS            = 8,
  parameter int DATA_WIDTH          = 32,
  parameter int ADDR_WIDTH          = 32,
  parameter int W_WORKERS           = 1,
  parameter int B_BANKS             = 2,
  parameter int MACRO_DEPTH         = 256,
  parameter int BANK_DEPTH          = 16384,
  parameter int STREAM_OFFSET_WIDTH = 10,

  localparam int MACRO_PTR_WIDTH   = $clog2(M_MACROS),
  localparam int BANK_PTR_WIDTH    = $clog2(B_BANKS),
  localparam int DATA_WIDTH_BYTES  = DATA_WIDTH / 8,
  localparam int DMA_MANAGERS      = W_WORKERS
)(
  input logic clk_i,
  input logic rst_ni,

  // APB Target IF
  input logic                   penable_i,
  input logic                   pwrite_i,
  input logic  [ADDR_WIDTH-1:0] paddr_i,
  input logic                   psel_i,
  input logic  [DATA_WIDTH-1:0] pwdata_i,
  output logic [DATA_WIDTH-1:0] prdata_o,
  output logic                  pready_o,
  output logic                  pslverr_o,

  // CPU IF
  output logic                    cpu_ready_o,
  input  logic                    cpu_valid_i,
  input  logic [ADDR_WIDTH-1:0]   cpu_addr_i,
  input  logic [DATA_WIDTH-1:0]   cpu_wdata_i,
  input  logic                    cpu_wen_i,

  output logic [DATA_WIDTH-1:0]   cpu_r_rdata_o,
  output logic                    cpu_r_valid_o,

  output logic job_dispatched_o
);

  // DMA

  logic [DMA_MANAGERS-1:0] dma_ready;
  logic [DMA_MANAGERS-1:0] dma_valid;
  logic [ADDR_WIDTH-1:0]   dma_addr  [DMA_MANAGERS];
  logic [DATA_WIDTH-1:0]   dma_wdata [DMA_MANAGERS];

  logic                        meta_req;
  logic [ADDR_WIDTH-1:0]       meta_addr;
  logic                        meta_gnt;
  logic                        meta_wen;
  logic [DATA_WIDTH-1:0]       meta_wdata;
  logic [DATA_WIDTH_BYTES-1:0] meta_be;

  logic [DATA_WIDTH-1:0] meta_r_rdata;
  logic                  meta_r_valid;

  dma_top #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .W_WORKERS(W_WORKERS),
    .B_BANKS(B_BANKS),
    .MACRO_DEPTH(MACRO_DEPTH),
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

    .job_dispatched_o(job_dispatched_o),

    .bus_ready_i(dma_ready),
    .bus_valid_o(dma_valid),
    .bus_addr_o(dma_addr),
    .bus_wdata_o(dma_wdata),

    .meta_req_i(meta_req),
    .meta_addr_i(meta_addr),
    .meta_gnt_o(meta_gnt),
    .meta_wen_i (meta_wen),
    .meta_wdata_i(meta_wdata),
    .meta_be_i(meta_be),

    .meta_r_rdata_o(meta_r_rdata),
    .meta_r_valid_o(meta_r_valid)
  );

  // L2 Subsystem

  l2_subsystem #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .W_WORKERS(W_WORKERS),
    .B_BANKS(B_BANKS),
    .BANK_DEPTH(BANK_DEPTH)
  ) u_l2_subsystem (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .dma_ready_o(dma_ready),
    .dma_valid_i(dma_valid),
    .dma_addr_i(dma_addr),
    .dma_wdata_i(dma_wdata),

    .cpu_ready_o(cpu_ready_o),
    .cpu_valid_i(cpu_valid_i),
    .cpu_addr_i(cpu_addr_i),
    .cpu_wdata_i(cpu_wdata_i),
    .cpu_wen_i(cpu_wen_i),

    .cpu_r_rdata_o(cpu_r_rdata_o),
    .cpu_r_valid_o(cpu_r_valid_o),

    .meta_req_o(meta_req),
    .meta_addr_o(meta_addr),
    .meta_gnt_i(meta_gnt),
    .meta_wen_o(meta_wen),
    .meta_wdata_o(meta_wdata),
    .meta_be_o(meta_be),

    .meta_r_rdata_i(meta_r_rdata),
    .meta_r_valid_i(meta_r_valid)
  );

endmodule
