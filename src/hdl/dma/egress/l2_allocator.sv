module l2_allocator #(
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,
  parameter int W_WORKERS     = 2,
  parameter int B_BANKS       = 2,
  parameter int BANK_DEPTH    = 8192,

  localparam int WORKER_PTR_WIDTH = (W_WORKERS > 1) ? $clog2(W_WORKERS) : 1,
  localparam int BANK_PTR_WIDTH   = $clog2(B_BANKS),
  localparam int DATA_WIDTH_BYTES = DATA_WIDTH / 8,
  localparam int SRAM_SIZE_B      = B_BANKS * BANK_DEPTH * DATA_WIDTH_BYTES,
  localparam int RING_PTR_WIDTH   = $clog2(SRAM_SIZE_B),
  localparam int WIDTH_SHIFT      = $clog2(DATA_WIDTH_BYTES)
)(
  input logic clk_i,
  input logic rst_ni,

  // Job IF
  job_if.rx_ready job_req_i,

  // Control IF
  input  logic                  enable_i, 
  input  logic [ADDR_WIDTH-1:0] l2_bank_base_i,
  output logic                  job_dispatched_o,

  // Worker IF
  input  logic [W_WORKERS-1:0]        worker_done_i,
  output logic [WORKER_PTR_WIDTH-1:0] job_wid_o,
  output logic [ADDR_WIDTH-1:0]       job_addr_o,
  job_if.tx_push                      job_assign_o,

  // Meta IF
  input  logic                        dispatch_ready_i,
  output logic                        dispatch_valid_o,
  output logic [DATA_WIDTH-1:0]       dispatch_data_o,
  output logic [WORKER_PTR_WIDTH-1:0] dispatch_worker_id_o,
  input  logic [ADDR_WIDTH-1:0]       cpu_done_ptr_i
  );

  typedef job_req_i.job_pkt_t job_pkt_t;

  logic                  full_q,         full_d;
  logic [ADDR_WIDTH-1:0] cpu_done_ptr_q;
  logic [ADDR_WIDTH-1:0] dispatch_ptr_q, dispatch_ptr_d;
  logic [W_WORKERS-1:0]  worker_busy_q,  worker_busy_d;

  // Priority Encoder for Workers
  logic [W_WORKERS-1:0]        worker_idle;
  logic                        has_idle_worker;
  logic [WORKER_PTR_WIDTH-1:0] idle_wid;

  always_comb begin
    worker_idle     = ~worker_busy_q;
    has_idle_worker = |worker_idle;

    idle_wid = '0;
    for (int i = 0; i < W_WORKERS; i++) begin
      if (worker_idle[i]) begin
        idle_wid = WORKER_PTR_WIDTH'(i);
        break;
      end
    end
  end

  // Space Management
  logic [ADDR_WIDTH-1:0] current_job_size;
  logic                  space_available;

  logic [ADDR_WIDTH-1:0] rel_dispatch;
  logic [ADDR_WIDTH-1:0] rel_cpu_done;
  logic [ADDR_WIDTH-1:0] occupied_space;


  assign rel_dispatch = dispatch_ptr_q - l2_bank_base_i;
  assign rel_cpu_done = cpu_done_ptr_i - l2_bank_base_i;

  always_comb begin
    if (rel_dispatch == rel_cpu_done) begin
      occupied_space = full_q ? SRAM_SIZE_B : '0;
    end else begin
      occupied_space = (rel_dispatch - rel_cpu_done + SRAM_SIZE_B) % SRAM_SIZE_B;
    end
  end

  assign current_job_size = ADDR_WIDTH'(job_req_i.pkt.window_size * DATA_WIDTH_BYTES);
  assign space_available  = (occupied_space + current_job_size) <= SRAM_SIZE_B;


  logic [ADDR_WIDTH-1:0] rel_ptr;
  assign rel_ptr = (dispatch_ptr_q - l2_bank_base_i);

  logic [ADDR_WIDTH-1:0] dispatch_ptr_n;
  assign dispatch_ptr_n = l2_bank_base_i + (rel_ptr + current_job_size) % SRAM_SIZE_B;

  logic job_not_empty;
  logic ready_cond;
  logic do_dispatch;

  assign job_not_empty = job_req_i.pkt.window_size != '0;
  assign ready_cond    = enable_i && has_idle_worker && space_available && dispatch_ready_i;
  assign do_dispatch   = job_req_i.valid && ready_cond && job_not_empty;
  assign job_req_i.ready = ready_cond;

  assign dispatch_valid_o     = do_dispatch;
  assign dispatch_data_o      = {
     5'(job_req_i.pkt.stream_id),
    27'(job_req_i.pkt.window_size)
  };
  assign dispatch_worker_id_o = idle_wid;

  // Next state logic
  always_comb begin
    dispatch_ptr_d = dispatch_ptr_q;
    worker_busy_d  = worker_busy_q & ~worker_done_i;
    full_d         = full_q;

    if (cpu_done_ptr_i != cpu_done_ptr_q) begin
      full_d = 1'b0;
    end

    if (!enable_i) begin
      dispatch_ptr_d = l2_bank_base_i;
      full_d         = 1'b0;
    end else if (do_dispatch) begin
      dispatch_ptr_d = dispatch_ptr_n;
      worker_busy_d[idle_wid] = 1'b1;

      if ((occupied_space + current_job_size) == SRAM_SIZE_B) begin
        full_d = (cpu_done_ptr_i == cpu_done_ptr_q);
      end
    end
  end

  // Registered outputs
  job_pkt_t                    job_pkt_q;
  logic                        job_valid_q;
  logic [WORKER_PTR_WIDTH-1:0] job_wid_q;
  logic [ADDR_WIDTH-1:0]       job_addr_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dispatch_ptr_q   <= '0;
      worker_busy_q    <= '0;
      job_pkt_q        <= '0;
      job_valid_q      <= 1'b0;
      job_wid_q        <= '0;
      job_addr_q       <= '0;
      full_q           <= 1'b0;
      cpu_done_ptr_q   <= '0;
    end else begin
      dispatch_ptr_q <= dispatch_ptr_d;
      worker_busy_q  <= worker_busy_d;
      job_valid_q    <= do_dispatch;
      full_q         <= full_d;
      cpu_done_ptr_q <= cpu_done_ptr_i;

      if (do_dispatch) begin
        job_pkt_q   <= job_req_i.pkt;
        job_wid_q   <= idle_wid;
        job_addr_q  <= dispatch_ptr_q;
      end
    end
  end

  assign job_dispatched_o   = job_valid_q;
  assign job_assign_o.valid = job_valid_q;
  assign job_assign_o.pkt   = job_pkt_q;
  assign job_wid_o          = job_wid_q;
  assign job_addr_o         = job_addr_q;
  
endmodule
