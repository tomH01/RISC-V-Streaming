module ingress_crossbar #(
  parameter int N_STREAMS  = 2,
  parameter int M_MACROS   = 8,
  parameter int DATA_WIDTH = 32,
  parameter int ADDR_WIDTH = 32
)(
  // Stream IF
  input logic  [DATA_WIDTH-1:0] stream_data_i [N_STREAMS],
  output logic [N_STREAMS-1:0]  stream_ready_o,

  // Alloc Manager IF
  input logic [$clog2(M_MACROS)-1:0] am_macro_sel_i [N_STREAMS],
  input logic [N_STREAMS-1:0]        am_req_i,
  input logic [ADDR_WIDTH-1:0]       am_addr_i      [N_STREAMS],


  // Buffer Pool IF
  input logic  [M_MACROS-1:0]   bp_gnt_i,
  output logic [M_MACROS-1:0]   bp_req_o,
  output logic [ADDR_WIDTH-1:0] bp_addr_o    [M_MACROS],
  output logic [DATA_WIDTH-1:0] bp_wdata_o  [M_MACROS],
  output logic [3:0]            bp_be_o     [M_MACROS]
);

  always_comb begin
    int m;

    stream_ready_o = '0;

    bp_req_o   = '0;
    bp_addr_o  = '{default: '0};
    bp_wdata_o = '{default: '0};
    bp_be_o    = '{default: 4'hF};

    for (int n = 0; n < N_STREAMS; n++) begin
      if (am_req_i[n]) begin
        m = am_macro_sel_i[n];

        bp_req_o[m]   = 1'b1;
        bp_addr_o[m]  = am_addr_i[n];
        bp_wdata_o[m] = stream_data_i[n];

        stream_ready_o[n] = bp_gnt_i[m];
      end
    end
  end
endmodule