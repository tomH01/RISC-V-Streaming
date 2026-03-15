module ingress_top #(
  parameter int N_STREAMS  = 4,
  parameter int M_MACROS   = 8,
  parameter int DATA_WIDTH = 32,
  parameter int ADD_WIDTH  = 32,
  parameter int NB_READ_PORTS = 1 
)(
  input logic clk_i,
  input logic rst_ni,

  input logic [DATA_WIDTH-1:0] stream_data_i  [N_STREAMS],
  input logic                  stream_valid_i [N_STREAMS],
  output logic                 stream_ready_o [N_STREAMS]
);

  // ############
  // N In-Streams

  logic [DATA_WIDTH-1:0] ch_data  [N_STREAMS];
  logic                  ch_valid [N_STREAMS];
  logic                  ch_ready [N_STREAMS];

  generate
    for (genvar i = 0; i < N_STREAMS; i++) begin : gen_in_stream_channels
      
      in_stream_channel #(
        .DATA_WIDTH(DATA_WIDTH)
      )(
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .data_i(stream_data_i[i]),
        .valid_i(stream_valid_i[i]),
        .ready_o(stream_ready_o[i]),

        .data_o(ch_data[i]),
        .valid_o(ch_valid[i]),
        .ready_i(ch_ready[i])
      );

    end
  endgenerate


  // #############
  // Alloc Manager

  logic [$clog2(M_MACROS)-1:0] am_macro_sel [N_STREAMS];
  logic [ADD_WIDTH-1:0]        am_add       [N_STREAMS];
  logic [N_STREAMS-1:0]        am_req;
  
  // TODO: implement alloc manager module
  logic [M_MACROS-1:0] macro_owner;
  // macro_owner must be connect to the associated output
  

  // ################
  // Ingress Crossbar

  logic [M_MACROS-1:0]   bp_gnt;
  logic [M_MACROS-1:0]   bp_req;
  logic [ADD_WIDTH-1:0]  bp_add   [M_MACROS];
  logic [DATA_WIDTH-1:0] bp_wdata [M_MACROS];
  logic [3:0]            bp_be    [M_MACROS];

  ingress_crossbar #(
    .M_MACROS(M_MACROS),
    .NB_READ_PORTS(NB_READ_PORTS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADD_WIDTH(ADD_WIDTH)
  )(
    .stream_data_i(ch_data),
    .stream_ready_o(ch_ready),

    .am_macro_sel_i(am_macro_sel),
    .am_add_i(am_add),
    .am_req_i(am_req),

    .bp_gnt_i(bp_gnt),
    .bp_req_o(bp_req),
    .bp_add_o(bp_add),
    .bp_wdata_o(bp_wdata),
    .bp_be_o(bp_be)
  );


  // ###########
  // Buffer Pool

  // Maybe Buffer Poool in dma_top as interface module to only expose ingress ports here
  buffer_pool #(
    .M_MACROS(M_MACROS),
    .NB_READ_PORTS(NB_READ_PORTS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADD_WIDTH(ADD_WIDTH)
  )(
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .macro_owner(macro_owner),

    .ingress_req_i(bp_req),
    .ingress_add_i(bp_add),
    .ingress_wdata_i(bp_wdata),
    .ingress_be_i(bp_be),
    .ingress_gnt_o(bp_gnt),

    .egress_req_i(),
    .egress_add_i(),
    .egress_macro_select_i(),
    .egress_gnt_o(),
    .egress_r_opc_o(),
    .egress_r_rdata_o(),
    .egress_r_valid_o()
  );
endmodule