interface job_if #(
  parameter int N_STREAMS     = 4,
  parameter int M_MACROS      = 8,
  parameter int ADDR_WIDTH    = 32,

  localparam int MACRO_PTR_WIDTH  = $clog2(M_MACROS),
  localparam int STREAM_PTR_WIDTH = $clog2(N_STREAMS)
);

  typedef struct packed {
    logic [STREAM_PTR_WIDTH-1:0] stream_id;
    logic [MACRO_PTR_WIDTH-1:0]  start_macro;
    logic [ADDR_WIDTH-1:0]       window_size;
    logic [3:0]                  mode;
    logic [15:0]                 window_id;
    logic [95:0]                 payload;
  } job_pkt_t;

  job_pkt_t pkt;
  logic     valid;
  logic     ready;

  modport manager (
    output pkt,
    output valid,
    input  ready
  );

  modport allocator (
    input  pkt,
    input  valid,
    output ready
  );

endinterface
