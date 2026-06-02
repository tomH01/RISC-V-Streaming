module l2_allocator_wrapper #(
  parameter int N_STREAMS     = 4,
  parameter int M_MACROS      = 8,
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,
  parameter int W_WORKERS     = 2,
  parameter int B_BANKS       = 2,

  localparam int WORKER_PTR_WIDTH = (W_WORKERS > 1) ? $clog2(W_WORKERS) : 1,
  localparam int BANK_PTR_WIDTH   = $clog2(B_BANKS),
  localparam int STREAM_PTR_WIDTH = $clog2(N_STREAMS),
  localparam int MACRO_PTR_WIDTH  = $clog2(M_MACROS)
)(
  input logic clk_i,
  input logic rst_ni,

  // Job Req IF (unpacked)
  input logic [STREAM_PTR_WIDTH-1:0] stream_id_i,
  input logic [MACRO_PTR_WIDTH-1:0]  start_macro_i,
  input logic [ADDR_WIDTH-1:0]       window_size_i,
  input logic [3:0]                  mode_i,
  input logic [15:0]                 window_id_i,
  input logic [95:0]                 payload_i,
  input logic                        job_valid_i,
  output logic                       job_ready_o,

  // Control IF
  input logic [BANK_PTR_WIDTH-1:0] start_bank_idx_i,
  input logic [DATA_WIDTH-1:0]     l2_bank_base_i [B_BANKS],
  input logic [DATA_WIDTH-1:0]     bank_limit_b_i,
  input logic [DATA_WIDTH-1:0]     bank_header_size_b_i,

  // Worker IF
  input  logic [W_WORKERS-1:0]        worker_done_i,
  output logic                        job_valid_o,
  output logic [WORKER_PTR_WIDTH-1:0] job_wid_o,
  output logic [ADDR_WIDTH-1:0]       job_addr_o,
  output logic [BANK_PTR_WIDTH-1:0]   job_bank_o,

  // Job Assign IF (unpacked)
  output logic [STREAM_PTR_WIDTH-1:0] stream_id_o,
  output logic [MACRO_PTR_WIDTH-1:0]  start_macro_o,
  output logic [ADDR_WIDTH-1:0]       window_size_o,
  output logic [3:0]                  mode_o,
  output logic [15:0]                 window_id_o,
  output logic [95:0]                 payload_o

  // BUS IF:
  // TODO
  
);

  job_if #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_job_req_if();

  job_if #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_job_assign_if();

  assign u_job_req_if.pkt.stream_id    = stream_id_i;
  assign u_job_req_if.pkt.start_macro = start_macro_i;
  assign u_job_req_if.pkt.window_size = window_size_i;
  assign u_job_req_if.pkt.mode        = mode_i;
  assign u_job_req_if.pkt.window_id   = window_id_i;
  assign u_job_req_if.pkt.payload     = payload_i;
  assign u_job_req_if.valid           = job_valid_i;
  assign job_ready_o                  = u_job_req_if.ready;

  assign stream_id_o   = u_job_assign_if.pkt.stream_id;
  assign start_macro_o = u_job_assign_if.pkt.start_macro;
  assign window_size_o = u_job_assign_if.pkt.window_size;
  assign mode_o        = u_job_assign_if.pkt.mode;
  assign window_id_o   = u_job_assign_if.pkt.window_id;
  assign payload_o     = u_job_assign_if.pkt.payload;
  assign job_valid_o   = u_job_assign_if.valid;

  l2_allocator #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .W_WORKERS(W_WORKERS),
    .B_BANKS(B_BANKS)
  ) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .job_req_i(u_job_req_if.rx_ready),

    .start_bank_idx_i(start_bank_idx_i),
    .l2_bank_base_i(l2_bank_base_i),
    .bank_limit_b_i(bank_limit_b_i),
    .bank_header_size_b_i(bank_header_size_b_i),

    .worker_done_i(worker_done_i),
    .job_assign_o(u_job_assign_if.tx_push),
    .job_wid_o(job_wid_o),
    .job_addr_o(job_addr_o),
    .job_bank_o(job_bank_o)
  );

endmodule
