module job_manager #(
  parameter int N_STREAMS     = 4,
  parameter int M_MACROS      = 8,
  parameter int NB_READ_PORTS = 1,
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32
)(
  input logic clk_i,
  input logic rst_ni,

  // Notification IF
  input logic                        notify_valid_i       [N_STREAMS],
  input logic [$clog2(M_MACROS)-1:0] notify_start_macro_i [N_STREAMS],

  // Control IF
  input logic                  cfg_push_i  [N_STREAMS],
  input logic [DATA_WIDTH-1:0] cfg_wdata_i [N_STREAMS],
  
  input logic [ADDR_WIDTH-1:0] window_size_i      [N_STREAMS],
  input logic [ADDR_WIDTH-1:0] cfg_cq_base_addr_i [N_STREAMS],

  // Job IF
  input logic  job_ready_i [N_STREAMS],
  output logic job_valid_o [N_STREAMS],

  output logic [$clog2(M_MACROS)-1:0] job_start_macro_o [N_STREAMS],
  // rule irgendwie
  output logic [ADDR_WIDTH-1:0]       job_window_size_o [N_STREAMS], 
  output logic [15:0]                 job_window_id_o   [N_STREAMS]
);
  // Notification FIFOs
  logic                        notify_empty [N_STREAMS];
  logic                        notify_pop   [N_STREAMS];
  logic [$clog2(M_MACROS)-1:0] notify_data  [N_STREAMS];

  // Config FIFOs
  logic                  cfg_empty [N_STREAMS];
  logic                  cfg_pop   [N_STREAMS];
  logic [DATA_WIDTH-1:0] cfg_data  [N_STREAMS];


endmodule
