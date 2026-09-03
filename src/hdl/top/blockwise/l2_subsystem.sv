module l2_subsystem #(
  parameter int DATA_WIDTH   = 32,
  parameter int ADDR_WIDTH   = 32,
  parameter int W_WORKERS    = 1,
  parameter int B_BANKS      = 2,
  parameter int BANK_DEPTH   = 16384,
  parameter int DMA_MANAGERS = W_WORKERS,

  localparam int DATA_WIDTH_BYTES = DATA_WIDTH / 8
)(
  input logic clk_i,
  input logic rst_ni,

  output logic [DMA_MANAGERS-1:0] dma_ready_o,
  input  logic [DMA_MANAGERS-1:0] dma_valid_i,
  input  logic [ADDR_WIDTH-1:0]   dma_addr_i  [DMA_MANAGERS],
  input  logic [DATA_WIDTH-1:0]   dma_wdata_i [DMA_MANAGERS],

  output logic                        cpu_ready_o,
  input  logic                        cpu_valid_i,
  input  logic [ADDR_WIDTH-1:0]       cpu_addr_i,
  input  logic [DATA_WIDTH-1:0]       cpu_wdata_i,
  input  logic [DATA_WIDTH_BYTES-1:0] cpu_be_i,
  input  logic                        cpu_wen_i,

  output logic [DATA_WIDTH-1:0] cpu_r_rdata_o,
  output logic                  cpu_r_valid_o
);

  // SRAM Interconnect

  logic [B_BANKS-1:0]          sram_req;
  logic [ADDR_WIDTH-1:0]       sram_addr    [B_BANKS];
  logic [B_BANKS-1:0]          sram_wen; 
  logic [DATA_WIDTH-1:0]       sram_wdata   [B_BANKS];
  logic [DATA_WIDTH_BYTES-1:0] sram_be      [B_BANKS];
  logic [B_BANKS-1:0]          sram_gnt;
  logic [DATA_WIDTH-1:0]       sram_r_rdata [B_BANKS];
  logic [B_BANKS-1:0]          sram_r_valid;

  logic [DMA_MANAGERS-1:0]     dma_wen_static;
  logic [DATA_WIDTH_BYTES-1:0] dma_be_static    [DMA_MANAGERS];

  always_comb begin
    // 0 = write, 1 = read
    dma_wen_static    = '0;
    dma_be_static     = '{default: '1};
  end

  sram_interconnect #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .W_WORKERS(W_WORKERS),
    .B_BANKS(B_BANKS),
    .BANK_DEPTH(BANK_DEPTH)
  ) u_sram_interconnect (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .dma_ready_o(dma_ready_o),
    .dma_valid_i(dma_valid_i),
    .dma_addr_i(dma_addr_i),
    .dma_wen_i(dma_wen_static),  
    .dma_wdata_i(dma_wdata_i),
    .dma_be_i(dma_be_static),

    .dma_r_rdata_o(),
    .dma_r_valid_o(),

    .cpu_ready_o(cpu_ready_o),
    .cpu_valid_i(cpu_valid_i),
    .cpu_addr_i(cpu_addr_i),
    .cpu_wen_i(cpu_wen_i),
    .cpu_wdata_i(cpu_wdata_i),
    .cpu_be_i(cpu_be_i),

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

  l2_sram_macro #(
    .B_BANKS(B_BANKS),
    .BANK_DEPTH(BANK_DEPTH)
  ) u_sram (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .req_i(sram_req),
    .addr_i(sram_addr),
    .wen_i(sram_wen),
    .wdata_i(sram_wdata),
    .be_i(sram_be),
    .gnt_o(sram_gnt),

    .r_rdata_o(sram_r_rdata),
    .r_valid_o(sram_r_valid)
  );

endmodule
