module top #(
  parameter int N_STREAMS           = 4,
  parameter int M_MACROS            = 8,
  parameter int DATA_WIDTH          = 32,
  parameter int ADDR_WIDTH          = 32,
  parameter int W_WORKERS           = 1,
  parameter int B_BANKS             = 2,
  parameter int MACRO_DEPTH         = 256,
  parameter int STREAM_OFFSET_WIDTH = 10,
  parameter int CPU_MASTERS         = 1,

  localparam int MACRO_PTR_WIDTH    = $clog2(M_MACROS),
  localparam int BANK_PTR_WIDTH     = $clog2(B_BANKS),
    localparam int DATA_WIDTH_BYTES = DATA_WIDTH / 8,
  localparam int META_MASTER        = 1,
  localparam int DMA_MASTERS        = W_WORKERS + META_MASTER,
  localparam int NUM_MASTERS        = DMA_MASTERS + CPU_MASTERS,
  localparam int MASTER_PTR_WIDTH   = $clog2(NUM_MASTERS)
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
  output logic [CPU_MASTERS-1:0] cpu_ready_o,
  input  logic [CPU_MASTERS-1:0] cpu_valid_i,
  input  logic [ADDR_WIDTH-1:0]  cpu_addr_i    [CPU_MASTERS],

  output logic [DATA_WIDTH-1:0]  cpu_r_rdata_o [CPU_MASTERS],
  output logic [CPU_MASTERS-1:0] cpu_r_valid_o
);

  // DMA

  logic [DMA_MASTERS-1:0]      dma_ready;
  logic [DMA_MASTERS-1:0]      dma_valid;
  logic [BANK_PTR_WIDTH-1:0]   dma_bank   [DMA_MASTERS];
  logic [ADDR_WIDTH-1:0]       dma_addr   [DMA_MASTERS];
  logic [DATA_WIDTH-1:0]       dma_wdata  [DMA_MASTERS];

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

    .bus_ready_i(dma_ready),
    .bus_valid_o(dma_valid),
    .bus_bank_o(dma_bank),
    .bus_addr_o(dma_addr),
    .bus_wdata_o(dma_wdata)
  );

  // SRAM Interconnect

  logic [B_BANKS-1:0]          sram_req;
  logic [ADDR_WIDTH-1:0]       sram_addr  [B_BANKS];
  logic [B_BANKS-1:0]          sram_wen; 
  logic [DATA_WIDTH-1:0]       sram_wdata [B_BANKS];
  logic [DATA_WIDTH_BYTES-1:0] sram_be    [B_BANKS];
  logic [B_BANKS-1:0]          sram_gnt;
  logic [DATA_WIDTH-1:0]       sram_r_rdata [B_BANKS];
  logic [B_BANKS-1:0]          sram_r_valid;

  logic [DMA_MASTERS-1:0]      dma_wen_static;
  logic [DATA_WIDTH_BYTES-1:0] dma_be_static    [DMA_MASTERS];
  logic [CPU_MASTERS-1:0]      cpu_wen_static;
  logic [DATA_WIDTH-1:0]       cpu_wdata_static [CPU_MASTERS];
  logic [DATA_WIDTH_BYTES-1:0] cpu_be_static    [CPU_MASTERS];

  always_comb begin
    dma_wen_static   = '1;
    dma_be_static    = '{default: '1};
    cpu_wen_static   = '0;
    cpu_wdata_static = '{default: '0};
    cpu_be_static    = '{default: '1};
  end

  sram_interconnect #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .W_WORKERS(W_WORKERS),
    .B_BANKS(B_BANKS),
    .CPU_MASTERS(CPU_MASTERS)
  ) u_sram_interconnect (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .dma_ready_o(dma_ready),
    .dma_valid_i(dma_valid),
    .dma_bank_i(dma_bank),
    .dma_addr_i(dma_addr),
    .dma_wen_i(dma_wen_static),  
    .dma_wdata_i(dma_wdata),
    .dma_be_i(dma_be_static),

    .cpu_ready_o(cpu_ready_o),
    .cpu_valid_i(cpu_valid_i),
    .cpu_addr_i(cpu_addr_i),
    .cpu_wen_i(cpu_wen_static),
    .cpu_wdata_i(cpu_wdata_static),
    .cpu_be_i(cpu_be_static),

    .cpu_r_rdata_o(cpu_r_rdata_o),
    .cpu_r_valid_o(cpu_r_valid_o),

    .sram_req_o(sram_req),
    .sram_addr_o(sram_addr),
    .sram_wen_o(sram_wen),
    .sram_wdata_o(sram_wdata),
    .sram_be_o(sram_be),
    .sram_gnt_i(sram_gnt),
    .sram_r_rdata_i(sram_r_rdata),
    .sram_r_valid_i(sram_r_valid)
  );

  // SRAMs

  generate
    for (genvar b = 0; b < B_BANKS; b++) begin : gen_sram
      l2_sram_macro u_sram (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .req(sram_req[b]),
        .add(sram_addr[b]),
        .wen(sram_wen[b]),
        .wdata(sram_wdata[b]),
        .be(sram_be[b]),
        .gnt(sram_gnt[b]),

        .r_rdata(sram_r_rdata[b]),
        .r_valid(sram_r_valid[b])
      );
    end
  endgenerate

endmodule
