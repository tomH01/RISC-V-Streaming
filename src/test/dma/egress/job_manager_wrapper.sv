module job_manager_wrapper #(
  parameter int N_STREAMS     = 4,
  parameter int M_MACROS      = 8,
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,
  parameter int FIFO_DEPTH    = 8,

  localparam int MACRO_PTR_WIDTH  = $clog2(M_MACROS),
  localparam int STREAM_PTR_WIDTH = $clog2(N_STREAMS)
)(
  input logic clk_i,
  input logic rst_ni,

  // Notification IF
  input logic                       notif_valid_i       [N_STREAMS],
  input logic [MACRO_PTR_WIDTH-1:0] notif_start_macro_i [N_STREAMS],

  // Control IF
  input logic                    cfg_push_i    [N_STREAMS],
  input logic [4*DATA_WIDTH-1:0] cfg_wdata_i   [N_STREAMS],
  
  input logic [ADDR_WIDTH-1:0]   window_size_i [N_STREAMS],

  // Job IF
  input  logic job_ready_i,
  output logic job_valid_o,

  output logic [STREAM_PTR_WIDTH-1:0] job_stream_id_o,
  output logic [MACRO_PTR_WIDTH-1:0]  job_start_macro_o,
  output logic [ADDR_WIDTH-1:0]       job_window_size_o, 
  output logic [3:0]                  job_mode_o,
  output logic [15:0]                 job_window_id_o,
  output logic [95:0]                 job_payload_o
);

  job_if #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_job_req_if();

  job_manager #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH)
  ) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .notif_valid_i(notif_valid_i),
    .notif_start_macro_i(notif_start_macro_i),

    .cfg_push_i(cfg_push_i),
    .cfg_wdata_i(cfg_wdata_i),
    
    .window_size_i(window_size_i),

    .job_req_o(u_job_req_if.tx_ready)
  );

  assign job_valid_o        = u_job_req_if.valid;
  assign u_job_req_if.ready = job_ready_i;

  assign job_stream_id_o    = u_job_req_if.pkt.stream_id;
  assign job_start_macro_o  = u_job_req_if.pkt.start_macro;
  assign job_window_size_o  = u_job_req_if.pkt.window_size; 
  assign job_mode_o         = u_job_req_if.pkt.mode;
  assign job_window_id_o    = u_job_req_if.pkt.window_id;
  assign job_payload_o      = u_job_req_if.pkt.payload;

endmodule
