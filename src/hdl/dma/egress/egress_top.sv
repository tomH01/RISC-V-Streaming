module ingress_top #(
  parameter int N_STREAMS  = 4,
  parameter int M_MACROS   = 8,
  parameter int DATA_WIDTH = 32,
  parameter int ADD_WIDTH  = 32,
  parameter int NB_READ_PORTS = 1 
)(
  input logic clk_i,
  input logic rst_ni,

  // Ingress IF
  input logic [N_STREAMS-1:0]        notify_valid_i,
  input logic [$clog2(M_MACROS)-1:0] notify_start_macro_i [N_STREAMS],

  // Buffer Pool IF
  input logic  [NB_READ_PORTS-1:0]    bp_gnt_i,
  input logic  [NB_READ_PORTS-1:0]    bp_r_opc_o,
  input logic  [DATA_WIDTH-1:0]       bp_r_rdata_o      [NB_READ_PORTS],
  input logic  [NB_READ_PORTS-1:0]    bp_r_valid_o,
  output logic [NB_READ_PORTS-1:0]    bp_req_o,
  output logic [ADDR_WIDTH-1:0]       bp_addr_o         [NB_READ_PORTS],
  output logic [$clog2(M_MACROS)-1:0] bp_macro_select_o [NB_READ_PORTS],
);

  // ############
  // Job Manager

  

  job_manager #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .NB_READ_PORTS(NB_READ_PORTS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_job_manager (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .notify_valid_i(notify_valid_i),
    .notify_start_macro_i(notify_start_macro_i),

    .job_ready_i(),
    .job_fire_o(),

    .job_stream_id_o(),
    .job_start_macro_o(),
    .job_window_size_o(),
    .job_window_id_o(),

    .stride_x_o(),
    .count_x_o(),
    .stride_y_o(),
    .count_y_o(),
    .stride_z_o(),
    .count_z_o()
  );



  // ############
  // A Address Generators


endmodule