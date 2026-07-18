module l2_allocator_wrapper #(
  parameter int N_STREAMS     = 4,
  parameter int M_MACROS      = 8,
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,
  parameter int W_WORKERS     = 2,
  parameter int B_BANKS       = 2,

  localparam int WORKER_PTR_WIDTH = (W_WORKERS > 1) ? $clog2(W_WORKERS) : 1,
  localparam int BANK_PTR_WIDTH   = $clog2(B_BANKS),
  localparam int STREAM_PTR_WIDTH = (N_STREAMS > 1) ? $clog2(N_STREAMS) : 1,
  localparam int MACRO_PTR_WIDTH  = $clog2(M_MACROS)
)(
  input logic clk_i,
  input logic rst_ni,

  // Job Req IF (unpacked)
  input logic [STREAM_PTR_WIDTH-1:0] stream_id_i,
  input logic [MACRO_PTR_WIDTH-1:0]  start_macro_i,
  input logic [ADDR_WIDTH-1:0]       window_size_i,
  input logic [3:0]                  mode_i,
  input logic [95:0]                 payload_i,
  input logic                        job_valid_i,
  output logic                       job_ready_o,

  // Control IF
  input  logic                 enable_i,
  input logic [DATA_WIDTH-1:0] l2_bank_base_i,

  // Worker IF
  input  logic [W_WORKERS-1:0]        worker_done_i,
  output logic                        job_valid_o,
  output logic [WORKER_PTR_WIDTH-1:0] job_wid_o,
  output logic [ADDR_WIDTH-1:0]       job_addr_o,

  // Job Assign IF (unpacked)
  output logic [STREAM_PTR_WIDTH-1:0] stream_id_o,
  output logic [MACRO_PTR_WIDTH-1:0]  start_macro_o,
  output logic [ADDR_WIDTH-1:0]       window_size_o,
  output logic [3:0]                  mode_o,
  output logic [95:0]                 payload_o,

  // Meta IF:
  input  logic                  fifo_ready_i,
  output logic                  fifo_valid_o,
  output logic [DATA_WIDTH-1:0] fifo_data_o,
  input logic  [ADDR_WIDTH-1:0] cpu_done_ptr_i
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

  meta_if #(
    .DATA_WIDTH(DATA_WIDTH),
    .B_BANKS(B_BANKS)
  ) u_meta_req_if();

  assign u_job_req_if.pkt.stream_id   = stream_id_i;
  assign u_job_req_if.pkt.start_macro = start_macro_i;
  assign u_job_req_if.pkt.window_size = window_size_i;
  assign u_job_req_if.pkt.mode        = mode_i;
  assign u_job_req_if.pkt.payload     = payload_i;
  assign u_job_req_if.valid           = job_valid_i;
  assign job_ready_o                  = u_job_req_if.ready;

  assign stream_id_o   = u_job_assign_if.pkt.stream_id;
  assign start_macro_o = u_job_assign_if.pkt.start_macro;
  assign window_size_o = u_job_assign_if.pkt.window_size;
  assign mode_o        = u_job_assign_if.pkt.mode;
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

    .enable_i(enable_i),
    .l2_bank_base_i(l2_bank_base_i),

    .worker_done_i(worker_done_i),
    .job_wid_o(job_wid_o),
    .job_addr_o(job_addr_o),
    .job_assign_o(u_job_assign_if.tx_push),

    .fifo_ready_i(fifo_ready_i),
    .fifo_valid_o(fifo_valid_o),
    .fifo_data_o(fifo_data_o),
    .cpu_done_ptr_i(cpu_done_ptr_i)
  );

endmodule
