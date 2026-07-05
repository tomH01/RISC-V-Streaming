module sram_interconnect #(
  parameter int DATA_WIDTH  = 32,
  parameter int ADDR_WIDTH  = 32,
  parameter int W_WORKERS   = 1,
  parameter int B_BANKS     = 2,
  parameter int CPU_MASTERS = 1,

  localparam int BANK_PTR_WIDTH   = $clog2(B_BANKS),
  localparam int DATA_WIDTH_BYTES = DATA_WIDTH / 8,
  localparam int META_MASTER      = 1,
  localparam int DMA_MASTERS      = W_WORKERS + META_MASTER,
  localparam int NUM_MASTERS      = DMA_MASTERS + CPU_MASTERS,
  localparam int MASTER_PTR_WIDTH = $clog2(NUM_MASTERS)
)(
  input logic clk_i,
  input logic rst_ni,

  // DMA IF
  output logic [DMA_MASTERS-1:0]      dma_ready_o,
  input  logic [DMA_MASTERS-1:0]      dma_valid_i,
  input  logic [BANK_PTR_WIDTH-1:0]   dma_bank_i    [DMA_MASTERS],
  input  logic [ADDR_WIDTH-1:0]       dma_addr_i    [DMA_MASTERS],
  input  logic [DMA_MASTERS-1:0]      dma_wen_i,  
  input  logic [DATA_WIDTH-1:0]       dma_wdata_i   [DMA_MASTERS],
  input  logic [DATA_WIDTH_BYTES-1:0] dma_be_i      [DMA_MASTERS],

  output logic [DATA_WIDTH-1:0]       dma_r_rdata_o [DMA_MASTERS],
  output logic [DMA_MASTERS-1:0]      dma_r_valid_o,

  // CPU IF
  output logic [CPU_MASTERS-1:0]      cpu_ready_o,
  input  logic [CPU_MASTERS-1:0]      cpu_valid_i,
  input  logic [ADDR_WIDTH-1:0]       cpu_addr_i    [CPU_MASTERS],
  input  logic [CPU_MASTERS-1:0]      cpu_wen_i,  
  input  logic [DATA_WIDTH-1:0]       cpu_wdata_i   [CPU_MASTERS],
  input  logic [DATA_WIDTH_BYTES-1:0] cpu_be_i      [CPU_MASTERS],

  output logic [DATA_WIDTH-1:0]       cpu_r_rdata_o [CPU_MASTERS],
  output logic [CPU_MASTERS-1:0]      cpu_r_valid_o,

  // SRAM IF
  output logic [B_BANKS-1:0]          sram_req_o ,
  output logic [ADDR_WIDTH-1:0]       sram_addr_o  [B_BANKS],
  output logic [B_BANKS-1:0]          sram_wen_o ,
  output logic [DATA_WIDTH-1:0]       sram_wdata_o [B_BANKS],
  output logic [DATA_WIDTH_BYTES-1:0] sram_be_o    [B_BANKS],
  input  logic [B_BANKS-1:0]          sram_gnt_i ,

  input  logic [DATA_WIDTH-1:0] sram_r_rdata_i [B_BANKS],
  input  logic [B_BANKS-1:0]    sram_r_valid_i
);
  typedef struct packed {
    logic [ADDR_WIDTH-1:0]       addr;
    logic [DATA_WIDTH-1:0]       wdata;
    logic                        wen;
    logic [DATA_WIDTH_BYTES-1:0] be;
  } sram_pkt_t;

  sram_pkt_t [NUM_MASTERS-1:0]                     xbar_din;
  logic      [NUM_MASTERS-1:0][BANK_PTR_WIDTH-1:0] xbar_bank_sel_in;
  logic      [NUM_MASTERS-1:0]                     xbar_valid_in;
  logic      [NUM_MASTERS-1:0]                     xbar_ready_out;

  sram_pkt_t [B_BANKS-1:0]                       xbar_dout;
  logic      [B_BANKS-1:0][MASTER_PTR_WIDTH-1:0] xbar_idx_out;
  logic      [B_BANKS-1:0]                       xbar_valid_out;    
  logic      [B_BANKS-1:0]                       xbar_ready_in;

  // Input Mapping
  always_comb begin
    for (int i = 0; i < DMA_MASTERS; i++) begin
      xbar_din[i].addr    = dma_addr_i[i];
      xbar_din[i].wdata   = dma_wdata_i[i];
      xbar_din[i].wen     = dma_wen_i[i];
      xbar_din[i].be      = dma_be_i[i];
      xbar_bank_sel_in[i] = dma_bank_i[i];
      xbar_valid_in[i]    = dma_valid_i[i];
      dma_ready_o[i]      = xbar_ready_out[i];
    end

    for (int i = 0; i < CPU_MASTERS; i++) begin
      automatic int idx = i + DMA_MASTERS;

      xbar_din[idx].addr    = cpu_addr_i[i];
      xbar_din[idx].wdata   = cpu_wdata_i[i];
      xbar_din[idx].wen     = cpu_wen_i[i];
      xbar_din[idx].be      = cpu_be_i[i];
      xbar_bank_sel_in[idx] = '0;
      xbar_valid_in[idx]    = cpu_valid_i[i];
      cpu_ready_o[i]        = xbar_ready_out[idx];
    end
  end

  cc_stream_xbar #(
    .NumInp(NUM_MASTERS),
    .NumOut(B_BANKS),
    .DataWidth(DATA_WIDTH),
    .payload_t(sram_pkt_t),
    .OutSpillReg(1'b0),
    .ExtPrio(1'b0),
    .AxiVldRdy(1'b1),
    .LockIn(1'b1)
  ) u_xbar (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .clr_i(1'b0),
    .clr_arb_i(1'b0),
    .rr_i('0),

    .data_i(xbar_din),
    .sel_i(xbar_bank_sel_in),
    .valid_i(xbar_valid_in),
    .ready_o(xbar_ready_out),

    .data_o(xbar_dout),
    .idx_o(xbar_idx_out),
    .valid_o(xbar_valid_out),
    .ready_i(xbar_ready_in)
  );

  // Output Mapping
  always_comb begin
    for (int b = 0; b < B_BANKS; b++) begin
      sram_req_o[b]    = xbar_valid_out[b];
      sram_addr_o[b]   = xbar_dout[b].addr;
      sram_wen_o[b]    = xbar_dout[b].wen;
      sram_wdata_o[b]  = xbar_dout[b].wdata;
      sram_be_o[b]     = xbar_dout[b].be;
      xbar_ready_in[b] = sram_gnt_i[b];
    end
  end

  // Read Data Mapping
  logic [MASTER_PTR_WIDTH-1:0] bank_master_q [B_BANKS];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      bank_master_q <= '{default:'0};
    end else begin
      for (int b = 0; b < B_BANKS; b++) begin
        if (sram_req_o[b] && sram_gnt_i[b]) begin
          bank_master_q[b] <= xbar_idx_out[b];
        end
      end
    end
  end

  always_comb begin
    dma_r_rdata_o = '{default: '0};
    dma_r_valid_o = '0;
    cpu_r_rdata_o = '{default: '0};
    cpu_r_valid_o = '0;

    for (int b = 0; b < B_BANKS; b++) begin
      if (sram_r_valid_i[b]) begin
        automatic int master_idx = int'(bank_master_q[b]);

        if (master_idx < DMA_MASTERS) begin
          dma_r_rdata_o[master_idx] = sram_r_rdata_i[b];
          dma_r_valid_o[master_idx] = 1'b1;
        end else begin
          automatic int cpu_idx  = master_idx - DMA_MASTERS;
          cpu_r_rdata_o[cpu_idx] = sram_r_rdata_i[b];
          cpu_r_valid_o[cpu_idx] = 1'b1;
        end
      end
    end
  end

endmodule
