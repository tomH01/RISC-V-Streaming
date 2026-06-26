module l2_allocator #(
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,
  parameter int W_WORKERS     = 2,
  parameter int B_BANKS       = 2,

  localparam int WORKER_PTR_WIDTH = (W_WORKERS > 1) ? $clog2(W_WORKERS) : 1,
  localparam int BANK_PTR_WIDTH   = $clog2(B_BANKS),
  localparam int DATA_WIDTH_BYTES = DATA_WIDTH / 8,
  localparam int WIDTH_SHIFT      = $clog2(DATA_WIDTH_BYTES)
)(
  input logic clk_i,
  input logic rst_ni,

  // Job IF
  job_if.rx_ready job_req_i,

  // Control IF
  input  logic [BANK_PTR_WIDTH-1:0] start_bank_idx_i,
  input  logic [DATA_WIDTH-1:0]     l2_bank_base_i [B_BANKS],
  input  logic [DATA_WIDTH-1:0]     bank_limit_b_i,
  input  logic [DATA_WIDTH-1:0]     bank_header_size_b_i,
  input  logic [B_BANKS-1:0]        bank_owner_i,
  output logic [B_BANKS-1:0]        bank_full_o,

  // Worker IF
  input  logic [W_WORKERS-1:0]        worker_done_i,
  output logic [WORKER_PTR_WIDTH-1:0] job_wid_o,
  output logic [ADDR_WIDTH-1:0]       job_addr_o,
  output logic [BANK_PTR_WIDTH-1:0]   job_bank_o,
  job_if.tx_push                      job_assign_o,

  // Meta Writer IF:
  meta_if.tx_ready meta_req_o
  );

  typedef job_req_i.job_pkt_t job_pkt_t;

  logic [B_BANKS-1:0]        bank_busy_q,     bank_busy_d;
  logic [BANK_PTR_WIDTH-1:0] active_bank_q,   active_bank_d;
  logic [DATA_WIDTH-1:0]     bank_offset_q,   bank_offset_d;

  logic [W_WORKERS-1:0]      bank_worker_busy_q [B_BANKS];
  logic [W_WORKERS-1:0]      bank_worker_busy_d [B_BANKS];

  logic [B_BANKS-1:0]        bank_draining_q, bank_draining_d;
  logic [B_BANKS-1:0]        bank_meta_done_q, bank_meta_done_d;
  logic [B_BANKS-1:0]        bank_full_d;


  // Priority Encoder for Idle Workers
  logic [W_WORKERS-1:0]        worker_busy;
  logic [W_WORKERS-1:0]        worker_idle;
  logic                        has_idle_worker;
  logic [WORKER_PTR_WIDTH-1:0] idle_wid;

  always_comb begin
    worker_busy = '0;
    for (int b = 0; b < B_BANKS; b++) begin
      worker_busy |= bank_worker_busy_q[b];
    end

    worker_idle     = ~worker_busy;
    has_idle_worker = |worker_idle;

    idle_wid = '0;
    for (int i = 0; i < W_WORKERS; i++) begin
      if (worker_idle[i]) begin
        idle_wid = WORKER_PTR_WIDTH'(i);
        break;
      end
    end
  end

  // Job Dispatch Logic
  logic [DATA_WIDTH-1:0] current_job_size;
  assign current_job_size = DATA_WIDTH'(job_req_i.pkt.window_size << WIDTH_SHIFT);

  logic fits_in_current_bank;
  assign fits_in_current_bank = (bank_offset_q + bank_header_size_b_i + current_job_size) <= bank_limit_b_i;

  logic [BANK_PTR_WIDTH-1:0] next_bank;
  assign next_bank = (active_bank_q == BANK_PTR_WIDTH'(B_BANKS-1)) ? '0 : active_bank_q + 1'b1;

  logic [BANK_PTR_WIDTH-1:0] target_bank;
  assign target_bank = fits_in_current_bank ? active_bank_q : next_bank;

  logic target_bank_ready;
  assign target_bank_ready = fits_in_current_bank | 
                             (~bank_busy_q[next_bank] & ~bank_owner_i[next_bank]);


  logic ready_cond;
  logic do_dispatch;
  assign ready_cond      = target_bank_ready && has_idle_worker && meta_req_o.ready;
  assign do_dispatch     = job_req_i.valid && ready_cond;
  assign job_req_i.ready = ready_cond;

  assign meta_req_o.valid           = do_dispatch;
  assign meta_req_o.pkt.close_bank  = ~fits_in_current_bank;
  assign meta_req_o.pkt.bank_idx    = target_bank;
  assign meta_req_o.pkt.window_id   = job_req_i.pkt.window_id;
  assign meta_req_o.pkt.window_size = current_job_size;

  // Registered outputs
  job_pkt_t                    job_pkt_q;
  logic                        job_valid_q;
  logic [WORKER_PTR_WIDTH-1:0] job_wid_q;
  logic [ADDR_WIDTH-1:0]       job_addr_q;
  logic [BANK_PTR_WIDTH-1:0]   job_bank_q;

  // Next state logic
  always_comb begin
    active_bank_d    = active_bank_q;
    bank_offset_d    = bank_offset_q;
    bank_draining_d  = bank_draining_q;
    bank_meta_done_d = bank_meta_done_q;
    bank_full_d      = '0;

    for (int b = 0; b < B_BANKS; b++) begin
      bank_worker_busy_d[b] = bank_worker_busy_q[b];
    end

    // Worker done
    for (int b = 0; b < B_BANKS; b++) begin
      bank_worker_busy_d[b] &= ~worker_done_i;
    end

    // Dispatch Job
    if (do_dispatch) begin
      active_bank_d = target_bank;
      bank_worker_busy_d[target_bank][idle_wid] = 1'b1;

      if (fits_in_current_bank) begin
        bank_offset_d   = bank_offset_q + current_job_size;
      end else begin
        bank_offset_d   = current_job_size;
      end
    end

    // Bank Busy logic
    for (int b = 0; b < B_BANKS; b++) begin
      bank_busy_d[b] = (BANK_PTR_WIDTH'(b) == active_bank_d) || (|bank_worker_busy_d[b]);
    end

    // Bank Draining logic
    for (int b = 0; b < B_BANKS; b++) begin
      if (do_dispatch && !fits_in_current_bank && (active_bank_q == BANK_PTR_WIDTH'(b))) begin
        bank_draining_d[b]  = 1'b1;
        bank_meta_done_d[b] = 1'b0;
      end

      if (meta_req_o.done && bank_draining_q[b]) begin
        bank_meta_done_d[b] = 1'b1;
      end

      if (bank_draining_q[b] && !bank_busy_d[b] && bank_meta_done_d[b]) begin
        bank_draining_d[b]  = 1'b0;
        bank_meta_done_d[b] = 1'b0;
        bank_full_d[b]      = 1'b1;
      end
    end    
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      active_bank_q      <= start_bank_idx_i;
      bank_offset_q      <= '0;
      bank_busy_q        <= '0;
      bank_worker_busy_q <= '{default:'0};
      bank_draining_q    <= '0;
      bank_meta_done_q   <= '0;
      bank_full_o        <= '0;

      job_valid_q        <= 1'b0;
      job_wid_q          <= '0;
      job_pkt_q          <= '0;
      job_addr_q         <= '0;
      job_bank_q         <= '0;
    end else begin
      active_bank_q      <= active_bank_d;
      bank_offset_q      <= bank_offset_d;
      bank_busy_q        <= bank_busy_d;
      bank_worker_busy_q <= bank_worker_busy_d;
      bank_draining_q    <= bank_draining_d;
      bank_meta_done_q   <= bank_meta_done_d;
      bank_full_o        <= bank_full_d;

      job_valid_q        <= do_dispatch;
      if (do_dispatch) begin
        job_wid_q          <= idle_wid;
        job_pkt_q          <= job_req_i.pkt;
        job_addr_q         <= l2_bank_base_i[target_bank] + bank_header_size_b_i +
                              (fits_in_current_bank ? bank_offset_q : '0);
        job_bank_q         <= target_bank;
      end
    end
  end

  assign job_assign_o.valid = job_valid_q;
  assign job_assign_o.pkt   = job_pkt_q;
  assign job_wid_o          = job_wid_q;
  assign job_addr_o         = job_addr_q;
  assign job_bank_o         = job_bank_q;
  
endmodule
