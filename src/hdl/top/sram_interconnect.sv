module sram_interconnect #(
  parameter int DATA_WIDTH  = 32,
  parameter int ADDR_WIDTH  = 32,
  parameter int W_WORKERS   = 1,
  parameter int B_BANKS     = 2,

  localparam int BANK_PTR_WIDTH    = $clog2(B_BANKS),
  localparam int DATA_WIDTH_BYTES  = DATA_WIDTH / 8,
  localparam int DMA_MANAGERS      = W_WORKERS,
  localparam int CPU_MANAGERS      = 1,
  localparam int NUM_MANAGERS      = DMA_MANAGERS + CPU_MANAGERS,
  localparam int NUM_SUBORDINATES  = B_BANKS,
  localparam int MANAGER_PTR_WIDTH = $clog2(NUM_MANAGERS)
)(
  input logic clk_i,
  input logic rst_ni,

  // DMA IF
  output logic [DMA_MANAGERS-1:0]     dma_ready_o,
  input  logic [DMA_MANAGERS-1:0]     dma_valid_i,
  input  logic [ADDR_WIDTH-1:0]       dma_addr_i    [DMA_MANAGERS],
  input  logic [DMA_MANAGERS-1:0]     dma_wen_i,  
  input  logic [DATA_WIDTH-1:0]       dma_wdata_i   [DMA_MANAGERS],
  input  logic [DATA_WIDTH_BYTES-1:0] dma_be_i      [DMA_MANAGERS],

  output logic [DATA_WIDTH-1:0]   dma_r_rdata_o [DMA_MANAGERS],
  output logic [DMA_MANAGERS-1:0] dma_r_valid_o,

  // CPU IF
  output logic                        cpu_ready_o,
  input  logic                        cpu_valid_i,
  input  logic [ADDR_WIDTH-1:0]       cpu_addr_i,
  input  logic                        cpu_wen_i,
  input  logic [DATA_WIDTH-1:0]       cpu_wdata_i,
  input  logic [DATA_WIDTH_BYTES-1:0] cpu_be_i,

  output logic [DATA_WIDTH-1:0]   cpu_r_rdata_o,
  output logic                    cpu_r_valid_o,

  // SRAM IF
  output logic [B_BANKS-1:0]          sram_req_o ,
  output logic [ADDR_WIDTH-1:0]       sram_addr_o  [B_BANKS],
  output logic [B_BANKS-1:0]          sram_wen_o ,
  output logic [DATA_WIDTH-1:0]       sram_wdata_o [B_BANKS],
  output logic [DATA_WIDTH_BYTES-1:0] sram_be_o    [B_BANKS],
  input  logic [B_BANKS-1:0]          sram_gnt_i ,

  input  logic [DATA_WIDTH-1:0] sram_r_rdata_i [B_BANKS],
  input  logic [B_BANKS-1:0]    sram_r_valid_i,

  // Meta IF
  output logic                        meta_req_o ,
  output logic [ADDR_WIDTH-1:0]       meta_addr_o,
  output logic                        meta_wen_o ,
  output logic [DATA_WIDTH-1:0]       meta_wdata_o,
  output logic [DATA_WIDTH_BYTES-1:0] meta_be_o,
  input  logic                        meta_gnt_i ,

  input  logic [DATA_WIDTH-1:0] meta_r_rdata_i,
  input  logic                  meta_r_valid_i
);
  typedef struct packed {
    logic [ADDR_WIDTH-1:0]       addr;
    logic [DATA_WIDTH-1:0]       wdata;
    logic                        wen;
    logic [DATA_WIDTH_BYTES-1:0] be;
  } sram_pkt_t;

  sram_pkt_t [NUM_MANAGERS-1:0]                     xbar_din;
  logic      [NUM_MANAGERS-1:0][BANK_PTR_WIDTH-1:0] xbar_bank_sel_in;
  logic      [NUM_MANAGERS-1:0]                     xbar_valid_in;
  logic      [NUM_MANAGERS-1:0]                     xbar_ready_out;

  sram_pkt_t [NUM_SUBORDINATES-1:0]                        xbar_dout;
  logic      [NUM_SUBORDINATES-1:0][MANAGER_PTR_WIDTH-1:0] xbar_idx_out;
  logic      [NUM_SUBORDINATES-1:0]                        xbar_valid_out;    
  logic      [NUM_SUBORDINATES-1:0]                        xbar_ready_in;

  logic  cpu_to_meta_req;
  assign cpu_to_meta_req = cpu_valid_i && (cpu_addr_i >= 32'h0010_0000);

  // Input Mapping
  always_comb begin
    for (int i = 0; i < DMA_MANAGERS; i++) begin
      xbar_din[i].addr    = dma_addr_i[i];
      xbar_din[i].wdata   = dma_wdata_i[i];
      xbar_din[i].wen     = dma_wen_i[i];
      xbar_din[i].be      = dma_be_i[i];
      xbar_bank_sel_in[i] = dma_addr_i[i][BANK_PTR_WIDTH+2-1:2];
      xbar_valid_in[i]    = dma_valid_i[i];
      dma_ready_o[i]      = xbar_ready_out[i];
    end
    
    xbar_din[DMA_MANAGERS].addr    = cpu_addr_i;
    xbar_din[DMA_MANAGERS].wdata   = cpu_wdata_i;
    xbar_din[DMA_MANAGERS].wen     = cpu_wen_i;
    xbar_din[DMA_MANAGERS].be      = cpu_be_i;
    xbar_bank_sel_in[DMA_MANAGERS] = cpu_addr_i[BANK_PTR_WIDTH+2-1:2];

    if (cpu_to_meta_req) begin
      xbar_valid_in[DMA_MANAGERS] = 1'b0;
      cpu_ready_o                 = meta_gnt_i;
    end else begin
      xbar_valid_in[DMA_MANAGERS] = cpu_valid_i;
      cpu_ready_o                 = xbar_ready_out[DMA_MANAGERS];
    end
  end

  always_comb begin
    meta_req_o   = cpu_to_meta_req;
    if (cpu_to_meta_req) begin
      meta_addr_o  = cpu_addr_i;
      meta_wdata_o = cpu_wdata_i;
      meta_wen_o   = cpu_wen_i;
      meta_be_o    = cpu_be_i;
    end else begin
      meta_addr_o  = '0;
      meta_wdata_o = '0;
      meta_wen_o   = '0;
      meta_be_o    = '0;
    end 
  end

  cc_stream_xbar #(
    .NumInp(NUM_MANAGERS),
    .NumOut(NUM_SUBORDINATES),
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
    for (int b = 0; b < NUM_SUBORDINATES; b++) begin
      sram_req_o[b]    = xbar_valid_out[b];
      sram_addr_o[b]   = xbar_dout[b].addr;
      sram_wen_o[b]    = xbar_dout[b].wen;
      sram_wdata_o[b]  = xbar_dout[b].wdata;
      sram_be_o[b]     = xbar_dout[b].be;
      xbar_ready_in[b] = sram_gnt_i[b];
    end
  end

  // Read Data Mapping
  logic [MANAGER_PTR_WIDTH-1:0] bank_manager_q [B_BANKS];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      bank_manager_q <= '{default:'0};
    end else begin
      for (int b = 0; b < NUM_SUBORDINATES; b++) begin
        if (sram_req_o[b] && sram_gnt_i[b]) begin
          bank_manager_q[b] <= xbar_idx_out[b];
        end
      end
    end
  end

  always_comb begin
    dma_r_rdata_o = '{default: '0};
    dma_r_valid_o = '0;
    cpu_r_rdata_o = '0;
    cpu_r_valid_o = '0;

    for (int b = 0; b < NUM_SUBORDINATES; b++) begin
      if (sram_r_valid_i[b]) begin
        automatic int manager_idx = int'(bank_manager_q[b]);

        if (manager_idx < DMA_MANAGERS) begin
          dma_r_rdata_o[manager_idx] = sram_r_rdata_i[b];
          dma_r_valid_o[manager_idx] = 1'b1;
        end else begin
          cpu_r_rdata_o = sram_r_rdata_i[b];
          cpu_r_valid_o = 1'b1;
        end
      end
    end

    if (meta_r_valid_i) begin
      cpu_r_rdata_o = meta_r_rdata_i;
      cpu_r_valid_o = 1'b1;
    end
  end

endmodule
