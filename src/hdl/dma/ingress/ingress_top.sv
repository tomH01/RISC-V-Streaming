module ingress_top #(
  parameter int N_STREAMS   = 4,
  parameter int M_MACROS    = 8,
  parameter int DATA_WIDTH  = 32,
  parameter int ADDR_WIDTH  = 32,
  parameter int MACRO_DEPTH = 256,

  localparam int MACRO_PTR_WIDTH = $clog2(M_MACROS)
)(
  input logic clk_i,
  input logic rst_ni,

  // Stream IF
  input  logic                  stream_valid_i [N_STREAMS],
  input  logic [DATA_WIDTH-1:0] stream_data_i  [N_STREAMS],
  output logic                  stream_ready_o [N_STREAMS],

  // Buffer Pool IF
  input  logic [M_MACROS-1:0]   bp_gnt_i,
  output logic [M_MACROS-1:0]   bp_done_o,
  output logic [M_MACROS-1:0]   bp_req_o,
  output logic [ADDR_WIDTH-1:0] bp_addr_o  [M_MACROS],
  output logic [DATA_WIDTH-1:0] bp_wdata_o [M_MACROS],
  output logic [3:0]            bp_be_o    [M_MACROS],

  // Control IF
  input logic [N_STREAMS-1:0]       cfg_stream_en_i,
  input logic [DATA_WIDTH-1:0]      cfg_window_size_i  [N_STREAMS],
  input logic [MACRO_PTR_WIDTH-1:0] cfg_start_macro_i  [N_STREAMS],
  input logic [MACRO_PTR_WIDTH-1:0] cfg_next_pointer_i [M_MACROS],

  // Egress IF
  output logic [N_STREAMS-1:0]       notify_valid_o,
  output logic [MACRO_PTR_WIDTH-1:0] notify_start_macro_o [N_STREAMS]
);

  // ############
  // N In-Streams

  logic [DATA_WIDTH-1:0] ch_data  [N_STREAMS];
  logic [N_STREAMS-1:0]  ch_valid;
  logic [N_STREAMS-1:0]  ch_ready;

  generate
    for (genvar i = 0; i < N_STREAMS; i++) begin : gen_in_stream_channels
      
      skid_buffer #(
        .DATA_WIDTH(DATA_WIDTH)
      ) u_in_stream_channel (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .us_valid_i(stream_valid_i[i]),
        .us_data_i(stream_data_i[i]),
        .us_ready_o(stream_ready_o[i]),

        .ds_ready_i(ch_ready[i]),
        .ds_valid_o(ch_valid[i]),
        .ds_data_o(ch_data[i])
      );

    end
  endgenerate


  // #############
  // Alloc Manager

  logic [MACRO_PTR_WIDTH-1:0]  am_macro_sel  [N_STREAMS];
  logic [ADDR_WIDTH-1:0]       am_addr       [N_STREAMS];
  logic [N_STREAMS-1:0]        am_req;
  
  alloc_manager #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .MACRO_DEPTH(MACRO_DEPTH)
  ) u_alloc_manager(
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .cfg_stream_en_i(cfg_stream_en_i),
    .cfg_window_size_i(cfg_window_size_i),
    .cfg_start_macro_i(cfg_start_macro_i),
    .cfg_next_pointer_i(cfg_next_pointer_i),

    .stream_valid_i(ch_valid),
    .stream_gnt_i(ch_ready),

    .am_macro_sel_o(am_macro_sel),
    .am_req_o(am_req),
    .am_addr_o(am_addr),

    .done_o(bp_done_o),  

    .window_valid_o(notify_valid_o),
    .window_start_o(notify_start_macro_o)
  );
  

  // ################
  // Ingress Crossbar

  ingress_crossbar #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_ingress_crossbar (
    .stream_data_i(ch_data),
    .stream_ready_o(ch_ready),

    .am_macro_sel_i(am_macro_sel),
    .am_req_i(am_req),
    .am_addr_i(am_addr),

    .bp_gnt_i(bp_gnt_i),
    .bp_req_o(bp_req_o),
    .bp_addr_o(bp_addr_o),
    .bp_wdata_o(bp_wdata_o),
    .bp_be_o(bp_be_o)
  );

endmodule