module l2_allocator #(
  parameter int N_STREAMS     = 4,
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,
  parameter int W_WORKERS     = 2,
  parameter int B_BANKS       = 2,
  parameter int BANK_DEPTH    = 8192,

  localparam int STREAM_PTR_WIDTH = (N_STREAMS > 1) ? $clog2(N_STREAMS) : 1,
  localparam int WORKER_PTR_WIDTH = (W_WORKERS > 1) ? $clog2(W_WORKERS) : 1,
  localparam int BANK_PTR_WIDTH   = (B_BANKS > 1) ? $clog2(B_BANKS) : 1,
  localparam int DATA_WIDTH_BYTES = DATA_WIDTH / 8,
  localparam int BANK_SIZE_BYTES  = BANK_DEPTH * DATA_WIDTH_BYTES
)(
  input logic clk_i,
  input logic rst_ni,

  // Job IF
  job_if.rx_ready job_req_i,

  // Control IF
  input logic [DATA_WIDTH-1:0]  window_size_i [N_STREAMS],
  input  logic                  enable_i,
  input  logic [ADDR_WIDTH-1:0] l2_bank_base_i, 
  input  logic [DATA_WIDTH-1:0] bank_header_size_b_i,
  input  logic [B_BANKS-1:0]    bank_owner_i,   // 0 = DMA, 1 = CPU
  output logic [B_BANKS-1:0]    bank_full_o,


  // Worker IF
  input  logic [W_WORKERS-1:0]        worker_done_i,
  output logic [WORKER_PTR_WIDTH-1:0] job_wid_o,
  output logic [ADDR_WIDTH-1:0]       job_addr_o,
  job_if.tx_push                      job_assign_o,

  // Meta Writer IF:
  meta_if.tx_ready meta_req_o
  );

  typedef job_req_i.job_pkt_t job_pkt_t;

  typedef enum logic [2:0] {
    FREE,
    OPEN, 
    BUSY,
    CLOSING,
    FULL
  } bank_state_e;

  logic [DATA_WIDTH-1:0]       bank_offset_q [B_BANKS], bank_offset_d [B_BANKS];
  logic [STREAM_PTR_WIDTH-1:0] bank_stream_q [B_BANKS], bank_stream_d [B_BANKS];
  bank_state_e                 bank_state_q [B_BANKS],  bank_state_d [B_BANKS];

  logic [W_WORKERS-1:0]      worker_is_busy_q,            worker_is_busy_d;
  logic [BANK_PTR_WIDTH-1:0] worker_target_q [W_WORKERS], worker_target_d [W_WORKERS];

  // Priority Encoder for Idle Workers
  logic [W_WORKERS-1:0]        worker_idle;
  logic                        has_idle_worker;
  logic [WORKER_PTR_WIDTH-1:0] idle_wid;

  always_comb begin
    worker_idle     = ~worker_is_busy_q;
    has_idle_worker = |worker_idle;
    idle_wid = '0;

    for (int i = 0; i < W_WORKERS; i++) begin
      if (worker_idle[i]) begin
        idle_wid = WORKER_PTR_WIDTH'(i);
        break;
      end
    end
  end

  // Bank Closing Logic
  logic [B_BANKS-1:0]        bank_needs_close;
  logic                      has_bank_to_close;
  logic [BANK_PTR_WIDTH-1:0] bank_to_close_idx;

  always_comb begin
    bank_needs_close      = '0;
    has_bank_to_close     = 1'b0;
    bank_to_close_idx     = '0;

    for (int b = 0; b < B_BANKS; b++) begin
      bank_needs_close[b] = (bank_state_q[b] == OPEN) &&
                            ((bank_offset_q[b] + 
                            bank_header_size_b_i + 
                            (window_size_i[bank_stream_q[b]] * DATA_WIDTH_BYTES)) > BANK_SIZE_BYTES);
      if (bank_needs_close[b] && !has_bank_to_close) begin
        has_bank_to_close = 1'b1;
        bank_to_close_idx = BANK_PTR_WIDTH'(b);
      end
    end
  end

  // Bank Selection Logic 
  logic [DATA_WIDTH-1:0] current_job_size;
  assign current_job_size = DATA_WIDTH'(job_req_i.pkt.window_size * DATA_WIDTH_BYTES);

  logic [B_BANKS-1:0] bank_available, bank_fits, bank_matches, bank_empty;

  logic                      has_match_fit, has_empty, has_any_fit;
  logic [BANK_PTR_WIDTH-1:0] match_fit_idx, empty_idx, any_fit_idx;

  always_comb begin
    has_match_fit  = 1'b0;
    has_empty      = 1'b0;
    has_any_fit    = 1'b0;

    match_fit_idx  = '0;
    empty_idx      = '0;
    any_fit_idx    = '0;
    
    for (int b = 0; b < B_BANKS; b++) begin
      bank_available[b]        = ~bank_owner_i[b] 
                                 && ((bank_state_q[b] == FREE) || (bank_state_q[b] == OPEN))
                                 && !bank_needs_close[b];
      bank_matches[b]          = (bank_stream_q[b] == job_req_i.pkt.stream_id) && (bank_state_q[b] == OPEN);
      bank_fits[b]             = (bank_offset_q[b] + bank_header_size_b_i + current_job_size) <= BANK_SIZE_BYTES;
      bank_empty[b]            = (bank_state_q[b] == FREE);

      if (bank_available[b]) begin
        // Priority: Match & Fit > Empty > Any Fit

        // Match & Fit
        if (bank_matches[b] && bank_fits[b] && !has_match_fit) begin
          has_match_fit  = 1'b1;
          match_fit_idx  = BANK_PTR_WIDTH'(b);
        end  

        // Empty
        if (bank_empty[b] && bank_fits[b] && !has_empty) begin
          has_empty = 1'b1;
          empty_idx = BANK_PTR_WIDTH'(b);
        end

        // Any Fit
        if (bank_fits[b] && !has_any_fit) begin
          has_any_fit = 1'b1;
          any_fit_idx = BANK_PTR_WIDTH'(b);
        end
      end 
    end
  end

  // Dispatch Logic
  logic [BANK_PTR_WIDTH-1:0] target_bank;
  logic                      target_valid;

  always_comb begin
    target_bank  = '0;
    target_valid = 1'b0;

    if (has_match_fit) begin
      target_bank  = match_fit_idx;
      target_valid = 1'b1;
    end
    else if (has_empty) begin
      target_bank  = empty_idx;
      target_valid = 1'b1;
    end
    else if (has_any_fit) begin
      target_bank  = any_fit_idx;
      target_valid = 1'b1;
    end
  end

  logic job_not_empty;
  logic ready_cond;
  logic do_dispatch;
  logic do_close;

  assign job_not_empty   = job_req_i.pkt.window_size != '0;
  assign ready_cond      = enable_i && target_valid && has_idle_worker && meta_req_o.ready;
  assign do_dispatch     = job_req_i.valid && ready_cond && job_not_empty;
  assign do_close        = enable_i && has_bank_to_close && meta_req_o.ready;
  assign job_req_i.ready = ready_cond;

  assign meta_req_o.valid            = do_dispatch || do_close;
  assign meta_req_o.pkt.dispatch     = do_dispatch;
  assign meta_req_o.pkt.close_bank   = do_close;
  assign meta_req_o.pkt.dispatch_idx = do_dispatch ? target_bank             : '0;
  assign meta_req_o.pkt.close_idx    = do_close    ? bank_to_close_idx       : '0;
  assign meta_req_o.pkt.window_id    = do_dispatch ? job_req_i.pkt.window_id : '0;
  assign meta_req_o.pkt.window_size  = do_dispatch ? current_job_size        : '0;

  // Registered outputs
  logic                        job_valid_q, job_valid_d;
  job_pkt_t                    job_pkt_q,   job_pkt_d;
  logic [WORKER_PTR_WIDTH-1:0] job_wid_q,   job_wid_d;
  logic [ADDR_WIDTH-1:0]       job_addr_q,  job_addr_d;

  always_comb begin
    bank_offset_d    = bank_offset_q;
    bank_stream_d    = bank_stream_q;
    bank_state_d     = bank_state_q;

    worker_is_busy_d = worker_is_busy_q;
    worker_target_d  = worker_target_q;

    job_valid_d = 1'b0;
    job_pkt_d   = job_pkt_q;
    job_wid_d   = job_wid_q;
    job_addr_d  = job_addr_q;

    for (int w = 0; w < W_WORKERS; w++) begin
      if (worker_done_i[w] && worker_is_busy_q[w]) begin
        worker_is_busy_d[w]              = 1'b0;

        if (bank_state_q[worker_target_q[w]] == BUSY) begin
          bank_state_d[worker_target_q[w]] = OPEN;
        end
      end
    end

    // Dispatch Job
    if (do_dispatch) begin
      job_valid_d = 1'b1;
      job_pkt_d   = job_req_i.pkt;
      job_wid_d   = idle_wid;
      job_addr_d  = l2_bank_base_i + 
                    (ADDR_WIDTH'(target_bank) * ADDR_WIDTH'(BANK_SIZE_BYTES)) + 
                    bank_header_size_b_i + bank_offset_q[target_bank];

      worker_is_busy_d[idle_wid] = 1'b1;
      worker_target_d[idle_wid]  = target_bank;

      bank_stream_d[target_bank] = job_req_i.pkt.stream_id;
      bank_offset_d[target_bank] = bank_offset_q[target_bank] + current_job_size;
      bank_state_d[target_bank]  = BUSY;
    end

    // Close Bank
    if (do_close) begin
      bank_state_d[bank_to_close_idx] = CLOSING;
    end

    // Meta Done
    if (meta_req_o.done) begin
      bank_state_d[meta_req_o.done_idx] = FULL;
    end

    // Bank Reset
    for (int b = 0; b < B_BANKS; b++) begin
      if (!enable_i || bank_owner_i[b]) begin
        bank_offset_d[b] = '0;
        bank_stream_d[b] = '0;
        bank_state_d[b]  = FREE; 
      end
    end
  end
  


  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      bank_offset_q <= '{default:'0};
      bank_stream_q <= '{default:'0};
      bank_state_q  <= '{default:FREE};

      worker_is_busy_q <= '0;
      worker_target_q  <= '{default:'0};

      job_valid_q <= 1'b0;
      job_pkt_q   <= '0;
      job_wid_q   <= '0;
      job_addr_q  <= '0;
    end else begin
      bank_offset_q    <= bank_offset_d;
      bank_stream_q    <= bank_stream_d;
      bank_state_q     <= bank_state_d;

      worker_is_busy_q <= worker_is_busy_d;
      worker_target_q  <= worker_target_d;

      job_valid_q <= job_valid_d;
      job_pkt_q   <= job_pkt_d;
      job_wid_q   <= job_wid_d;
      job_addr_q  <= job_addr_d;
    end
  
  end

  always_comb begin
    bank_full_o = '0;
    if (meta_req_o.done) begin
      bank_full_o[meta_req_o.done_idx] = 1'b1;
    end
  end

  assign job_assign_o.valid = job_valid_q;
  assign job_assign_o.pkt   = job_pkt_q;
  assign job_wid_o          = job_wid_q;
  assign job_addr_o         = job_addr_q;
  
endmodule
