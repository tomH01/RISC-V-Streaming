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

  // Job dispatched IRQ
  output logic job_dispatched_o
);

  logic is_perf_mon;
  assign is_perf_mon = (paddr_i[15:12] == 4'h4);

  logic psel_dma, psel_perf;
  assign psel_dma  = psel_i & !is_perf_mon;
  assign psel_perf = psel_i &  is_perf_mon;

  logic [DATA_WIDTH-1:0] dma_prdata, perf_prdata;
  logic                  dma_pready, perf_pready;
  logic                  dma_pslverr, perf_pslverr;

  assign prdata_o  = is_perf_mon ? perf_prdata  : dma_prdata;
  assign pready_o  = is_perf_mon ? perf_pready  : dma_pready;
  assign pslverr_o = is_perf_mon ? perf_pslverr : dma_pslverr;

  logic dma_setup_started_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dma_setup_started_q <= 1'b0;
    end else if (psel_dma && penable_i && dma_pready) begin
      dma_setup_started_q <= 1'b1;
    end
  end

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

  logic                 perf_dma_enable;
  logic [N_STREAMS-1:0] perf_ingr_stm_in_valid;
  logic [N_STREAMS-1:0] perf_ingr_stm_in_ready;
  logic                 perf_egr_job_req_valid;
  logic                 perf_egr_job_req_ready;
  logic                 perf_egr_meta_disp_valid;
  logic                 perf_egr_meta_disp_ready;
  logic [W_WORKERS-1:0] perf_egr_wkr_bp_req;
  logic [W_WORKERS-1:0] perf_egr_wkr_bp_gnt;
  logic [W_WORKERS-1:0] perf_egr_wkr_bus_valid;
  logic [W_WORKERS-1:0] perf_egr_wkr_bus_ready;
  logic                 perf_data_l2_valid;
  logic                 perf_data_l2_ready;
  logic                 perf_data_meta_req;
  logic                 perf_data_meta_gnt;

  assign perf_data_l2_valid = data_req_i && !meta_req;
  assign perf_data_l2_ready = data_gnt_o && !meta_req;
  assign perf_data_meta_req = meta_req;
  assign perf_data_meta_gnt = meta_gnt;

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
    .psel_i(psel_dma),
    .pwdata_i(pwdata_i),
    .prdata_o(dma_prdata),
    .pready_o(dma_pready),
    .pslverr_o(dma_pslverr),

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
    .meta_r_valid_o(meta_r_valid),

    .perf_dma_enable_o(perf_dma_enable),
    .perf_ingr_stm_in_valid_o(perf_ingr_stm_in_valid),
    .perf_ingr_stm_in_ready_o(perf_ingr_stm_in_ready),
    .perf_egr_job_req_valid_o(perf_egr_job_req_valid),
    .perf_egr_job_req_ready_o(perf_egr_job_req_ready),
    .perf_egr_meta_disp_valid_o(perf_egr_meta_disp_valid),
    .perf_egr_meta_disp_ready_o(perf_egr_meta_disp_ready),
    .perf_egr_wkr_bp_req_o(perf_egr_wkr_bp_req),
    .perf_egr_wkr_bp_gnt_o(perf_egr_wkr_bp_gnt),
    .perf_egr_wkr_bus_valid_o(perf_egr_wkr_bus_valid),
    .perf_egr_wkr_bus_ready_o(perf_egr_wkr_bus_ready)
  );


  // L2 Subsystem

  logic internal_wen;
  assign internal_wen = ~data_we_i;

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

    .cpu_ready_o(data_gnt_o),
    .cpu_valid_i(data_req_i),
    .cpu_addr_i(data_addr_i),
    .cpu_wdata_i(data_wdata_i),
    .cpu_be_i(data_be_i),
    .cpu_wen_i(internal_wen),

    .cpu_r_rdata_o(data_r_rdata_o),
    .cpu_r_valid_o(data_r_valid_o),

    .meta_req_o(meta_req),
    .meta_addr_o(meta_addr),
    .meta_gnt_i(meta_gnt),
    .meta_wen_o(meta_wen),
    .meta_wdata_o(meta_wdata),
    .meta_be_o(meta_be),

    .meta_r_rdata_i(meta_r_rdata),
    .meta_r_valid_i(meta_r_valid)
  );


  // Performance Monitor
  performance_monitor #(
    .N_STREAMS(N_STREAMS),
    .W_WORKERS(W_WORKERS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_performance_monitor (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .penable_i(penable_i),
    .pwrite_i(pwrite_i),
    .paddr_i(paddr_i),
    .psel_i(psel_perf),
    .pwdata_i(pwdata_i),
    .prdata_o(perf_prdata),
    .pready_o(perf_pready),
    .pslverr_o(perf_pslverr),

    .dma_enable_i(perf_dma_enable),
    .dma_setup_start_i(dma_setup_started_q),

    .ingr_stm_in_valid_i(perf_ingr_stm_in_valid),
    .ingr_stm_in_ready_i(perf_ingr_stm_in_ready),

    .egr_job_req_valid_i(perf_egr_job_req_valid),
    .egr_job_req_ready_i(perf_egr_job_req_ready),
    .egr_meta_disp_valid_i(perf_egr_meta_disp_valid),
    .egr_meta_disp_ready_i(perf_egr_meta_disp_ready),
    .egr_wkr_bp_req_i(perf_egr_wkr_bp_req),
    .egr_wkr_bp_gnt_i(perf_egr_wkr_bp_gnt),
    .egr_wkr_bus_valid_i(perf_egr_wkr_bus_valid),
    .egr_wkr_bus_ready_i(perf_egr_wkr_bus_ready),

    .cpu_l2_valid_i(perf_data_l2_valid),
    .cpu_l2_ready_i(perf_data_l2_ready),
    .cpu_meta_req_i(perf_data_meta_req),
    .cpu_meta_gnt_i(perf_data_meta_gnt)
  );

endmodule
