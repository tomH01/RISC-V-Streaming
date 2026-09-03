module meta_writer #(
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,
  parameter int B_BANKS       = 2,
  parameter int BANK_DEPTH    = 8192,

  localparam int BANK_PTR_WIDTH   = $clog2(B_BANKS),
  localparam int DATA_WIDTH_BYTES = DATA_WIDTH / 8,
  localparam int BANK_SIZE_BYTES  = BANK_DEPTH * DATA_WIDTH_BYTES
)(
  input logic clk_i,
  input logic rst_ni,

  // L2 Allocator IF
  meta_if.rx_ready meta_req_i,

  // Control IF
  input logic [DATA_WIDTH-1:0] l2_bank_base_i,

  // Bus IF
  input logic                       bus_ready_i,
  output logic                      bus_valid_o,
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

  meta_pkt_t                 pkt_q,           pkt_d;
  logic                      meta_done_q,     meta_done_d;
  logic [BANK_PTR_WIDTH-1:0] meta_done_idx_q, meta_done_idx_d;

  assign meta_req_i.ready = !fifo_full;
  assign meta_req_i.done = meta_done_q;
  assign meta_req_i.done_idx = meta_done_idx_q;

  always_comb begin
    state_d       = state_q;
    bank_cnt_d    = bank_cnt_q;
    bank_ptr_d    = bank_ptr_q;
    pkt_d         = pkt_q;

    meta_done_d     = 1'b0;
    meta_done_idx_d = '0;

    fifo_pop      = 1'b0;

    bus_valid_o   = 1'b0;
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
          state_d = WRITE_CLOSE_COUNT;
        end 
        else if (fifo_dout.dispatch) begin
          state_d = WRITE_WINDOW_ID;
        end else begin
          if (!fifo_empty) begin
            fifo_pop = 1'b1;
            state_d  = READ_FIFO;
          end else begin
            state_d = IDLE;
          end
        end
      end

      WRITE_CLOSE_COUNT: begin
        bus_valid_o = 1'b1;
        bus_addr_o  = l2_bank_base_i + (ADDR_WIDTH'(pkt_q.close_idx) * ADDR_WIDTH'(BANK_SIZE_BYTES));
        bus_wdata_o = bank_cnt_q[pkt_q.close_idx];

        if (bus_ready_i) begin
          meta_done_d                 = 1'b1;
          meta_done_idx_d             = pkt_q.close_idx;
          bank_cnt_d[pkt_q.close_idx] = '0;
          bank_ptr_d[pkt_q.close_idx] = DATA_WIDTH'(1);

          if (pkt_q.dispatch) begin
            state_d = WRITE_WINDOW_ID;
          end else begin
            if (!fifo_empty) begin
              fifo_pop = 1'b1;
              state_d  = READ_FIFO;
            end else begin
              state_d = IDLE;
            end
          end
        end
      end

      WRITE_WINDOW_ID: begin
        bus_valid_o = 1'b1;
        bus_addr_o  = l2_bank_base_i + 
                      (ADDR_WIDTH'(pkt_q.dispatch_idx) * ADDR_WIDTH'(BANK_SIZE_BYTES)) + 
                      ADDR_WIDTH'(bank_ptr_q[pkt_q.dispatch_idx] * DATA_WIDTH_BYTES);
        bus_wdata_o = pkt_q.window_id;

        if (bus_ready_i) begin
          bank_ptr_d[pkt_q.dispatch_idx] = bank_ptr_q[pkt_q.dispatch_idx] + 1;
          state_d = WRITE_WINDOW_SIZE;
        end
      end

      WRITE_WINDOW_SIZE: begin
        bus_valid_o = 1'b1;
        bus_addr_o  = l2_bank_base_i + 
                      (ADDR_WIDTH'(pkt_q.dispatch_idx) * ADDR_WIDTH'(BANK_SIZE_BYTES)) + 
                      ADDR_WIDTH'(bank_ptr_q[pkt_q.dispatch_idx] * DATA_WIDTH_BYTES);
        bus_wdata_o = pkt_q.window_size;

        if (bus_ready_i) begin
          bank_ptr_d[pkt_q.dispatch_idx] = bank_ptr_q[pkt_q.dispatch_idx] + 1;
          bank_cnt_d[pkt_q.dispatch_idx] = bank_cnt_q[pkt_q.dispatch_idx] + 1;

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
      meta_done_q     <= '0;
      meta_done_idx_q <= '0;
    end else begin
      state_q         <= state_d;
      bank_cnt_q      <= bank_cnt_d;
      bank_ptr_q      <= bank_ptr_d;
      pkt_q           <= pkt_d;
      meta_done_q     <= meta_done_d;
      meta_done_idx_q <= meta_done_idx_d;
    end
  end

endmodule
