interface meta_if #(
  parameter int DATA_WIDTH    = 32,
  parameter int B_BANKS       = 8,

  localparam int BANK_PTR_WIDTH  = $clog2(B_BANKS)
);

  typedef struct packed {
    logic                      close_bank;
    logic [BANK_PTR_WIDTH-1:0] close_idx;
    logic                      dispatch;
    logic [BANK_PTR_WIDTH-1:0] dispatch_idx;
    logic [DATA_WIDTH-1:0]     window_id;
    logic [DATA_WIDTH-1:0]     window_size;
  } meta_pkt_t;

  meta_pkt_t                 pkt;
  logic                      valid;
  logic                      ready;
  logic                      done;
  logic [BANK_PTR_WIDTH-1:0] done_idx;

  modport tx_ready (
    output pkt, valid,
    input  ready, done, done_idx
  );

  modport rx_ready (
    input  pkt, valid,
    output ready, done, done_idx
  );

endinterface
