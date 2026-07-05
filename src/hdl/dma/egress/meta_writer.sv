module meta_writer #(
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,
  parameter int B_BANKS       = 2,

  localparam int BANK_PTR_WIDTH   = $clog2(B_BANKS),
  localparam int DATA_WIDTH_BYTES = DATA_WIDTH / 8
)(
  input logic clk_i,
  input logic rst_ni,

  // L2 Allocator IF
  meta_if.rx_ready meta_req_i,

  // Control IF
  input logic [DATA_WIDTH-1:0] l2_bank_base_i [B_BANKS],

  // Bus IF
  input logic                       bus_ready_i,
  output logic                      bus_valid_o,
  output logic [BANK_PTR_WIDTH-1:0] bus_bank_o,
  output logic [ADDR_WIDTH-1:0]     bus_addr_o,
  output logic [DATA_WIDTH-1:0]     bus_wdata_o

  
);
  typedef meta_req_i.meta_pkt_t meta_pkt_t;
  localparam int PKT_WIDTH = $bits(meta_pkt_t);

  logic      fifo_push;
  logic      fifo_pop;
  logic      fifo_full;
  logic      fifo_empty;
  meta_pkt_t fifo_din;
  meta_pkt_t fifo_dout;

  assign fifo_push        = meta_req_i.valid && !fifo_full;
  assign fifo_din         = meta_req_i.pkt;
  assign meta_req_i.ready = !fifo_full;

  fifo #(
    .DATA_WIDTH(PKT_WIDTH),
    .DEPTH(4)
  ) u_fifo (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .push_i(fifo_push),
    .data_i(fifo_din),
    .full_o(fifo_full),
    .pop_i(fifo_pop),
    .data_o(fifo_dout),
    .empty_o(fifo_empty)
  );

  typedef enum logic [2:0] {
    IDLE,
    READ_FIFO,
    WRITE_CLOSE_COUNT,
    WRITE_WINDOW_ID,
    WRITE_WINDOW_SIZE
  } state_e;

  state_e state_q, state_d;

  logic [DATA_WIDTH-1:0] bank_cnt_q [B_BANKS], bank_cnt_d [B_BANKS];
  logic [DATA_WIDTH-1:0] bank_ptr_q [B_BANKS], bank_ptr_d [B_BANKS];

  meta_pkt_t                 pkt_q,         pkt_d;
  logic [BANK_PTR_WIDTH-1:0] closed_bank_q, closed_bank_d;
  logic                      meta_done_q,   meta_done_d;

  assign meta_req_i.done = meta_done_q;

  always_comb begin
    state_d       = state_q;

    bank_cnt_d = bank_cnt_q;
    bank_ptr_d = bank_ptr_q;

    pkt_d         = pkt_q;
    closed_bank_d = closed_bank_q;
    meta_done_d   = 1'b0;
    fifo_pop      = 1'b0;

    bus_valid_o   = 1'b0;
    bus_bank_o    = '0;
    bus_addr_o    = '0; 
    bus_wdata_o   = '0;

    case (state_q) 
      IDLE: begin
        if (!fifo_empty) begin
          fifo_pop = 1'b1;
          state_d  = READ_FIFO;
        end
      end

      READ_FIFO: begin
        pkt_d = fifo_dout;

        if (fifo_dout.close_bank) begin
          closed_bank_d = pkt_q.bank_idx;
          state_d       = WRITE_CLOSE_COUNT;
        end else begin
          state_d = WRITE_WINDOW_ID;
        end
      end

      WRITE_CLOSE_COUNT: begin
        bus_valid_o = 1'b1;
        bus_bank_o  = closed_bank_q;
        bus_addr_o  = l2_bank_base_i[closed_bank_q];
        bus_wdata_o = bank_cnt_q[closed_bank_q];

        if (bus_ready_i) begin
          meta_done_d = 1'b1;
          bank_cnt_d[closed_bank_q] = '0;
          bank_ptr_d[closed_bank_q] = DATA_WIDTH'(1);
          state_d                   = WRITE_WINDOW_ID;
        end
      end

      WRITE_WINDOW_ID: begin
        bus_valid_o = 1'b1;
        bus_bank_o  = pkt_q.bank_idx;
        bus_addr_o  = ADDR_WIDTH'(l2_bank_base_i[pkt_q.bank_idx] + 
                                  bank_ptr_q[pkt_q.bank_idx] * DATA_WIDTH_BYTES);
        bus_wdata_o = pkt_q.window_id;

        if (bus_ready_i) begin
          bank_ptr_d[pkt_q.bank_idx] = bank_ptr_q[pkt_q.bank_idx] + 1;
          state_d = WRITE_WINDOW_SIZE;
        end
      
      end

      WRITE_WINDOW_SIZE: begin
        bus_valid_o = 1'b1;
        bus_bank_o  = pkt_q.bank_idx;
        bus_addr_o  = ADDR_WIDTH'(l2_bank_base_i[pkt_q.bank_idx] + 
                                  bank_ptr_q[pkt_q.bank_idx] * DATA_WIDTH_BYTES);
        bus_wdata_o = pkt_q.window_size;

        if (bus_ready_i) begin
          bank_ptr_d[pkt_q.bank_idx] = bank_ptr_q[pkt_q.bank_idx] + 1;
          bank_cnt_d[pkt_q.bank_idx] = bank_cnt_q[pkt_q.bank_idx] + 1;

          if (!fifo_empty) begin
            fifo_pop = 1'b1;
            state_d  = READ_FIFO;
          end else begin
            state_d = IDLE;
          end
        end
      end

      default: state_d = IDLE;
    endcase


  end

  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin
      state_q         <= IDLE;

      bank_cnt_q      <= '{default:'0};
      bank_ptr_q      <= '{default:DATA_WIDTH'(1)};

      pkt_q           <= '0;
      closed_bank_q   <= '0;
      meta_done_q     <= '0;
    end else begin
      state_q         <= state_d;

      bank_cnt_q      <= bank_cnt_d;
      bank_ptr_q      <= bank_ptr_d;

      pkt_q           <= pkt_d;
      closed_bank_q   <= closed_bank_d;
      meta_done_q     <= meta_done_d;
    end
  end

endmodule
