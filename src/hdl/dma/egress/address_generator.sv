module address_generator #(
  parameter int N_STREAMS  = 4,
  parameter int M_MACROS   = 8,
  parameter int DATA_WIDTH = 32,
  parameter int ADDR_WIDTH = 32,
  parameter int B_BANKS    = 2,
  parameter int MACRO_DEPTH = 256,

  localparam int MACRO_PTR_WIDTH  = $clog2(M_MACROS),
  localparam int STREAM_PTR_WIDTH = (N_STREAMS > 1) ? $clog2(N_STREAMS) : 1,
  localparam int BANK_PTR_WIDTH   = $clog2(B_BANKS),
  localparam int OFFSET_WIDTH     = $clog2(MACRO_DEPTH),
  localparam int MACRO_CNT_WIDTH  = $clog2(M_MACROS + 1),
  localparam int DATA_WIDTH_BYTES = DATA_WIDTH / 8,
  localparam int NUM_MODES        = 16
)(
  input logic clk_i,
  input logic rst_ni,

  // Control IF
  input logic [MACRO_PTR_WIDTH-1:0] next_pointer_i [M_MACROS],

  // Allocator IF
  input logic                      sel_i,
  job_if.rx_push                   job_assign_i,
  input logic [ADDR_WIDTH-1:0]     job_addr_i,
  output logic                     job_done_o,

  // Meta IF
  output logic                        ptr_valid_o,
  output logic                        ptr_done_o,
  output logic [STREAM_PTR_WIDTH-1:0] ptr_stream_id_o,
  output logic [ADDR_WIDTH-1:0]       ptr_o,

  // Buffer Pool IF
  output logic [M_MACROS-1:0]        bp_release_o,
  output logic                       bp_req_o,
  output logic [ADDR_WIDTH-1:0]      bp_addr_o,
  output logic [MACRO_PTR_WIDTH-1:0] bp_macro_sel_o,
  input  logic                       bp_gnt_i,
  input  logic [DATA_WIDTH-1:0]      bp_r_rdata_i,
  input  logic                       bp_r_valid_i,

  // Bus IF
  input logic                       bus_ready_i,
  output logic                      bus_valid_o,
  output logic [ADDR_WIDTH-1:0]     bus_addr_o,
  output logic [DATA_WIDTH-1:0]     bus_wdata_o
);

  typedef enum logic [1:0] {
    IDLE,
    PREPARE,
    RUN,
    FINISH
  } state_e;

  typedef enum logic [3:0] {
    MODE_LINEAR  = 4'h0,
    MODE_STRIDED = 4'h1
  } agu_mode_e;

  state_e state_q, state_d;

  logic [STREAM_PTR_WIDTH-1:0] stream_id_q,      stream_id_d;
  logic [MACRO_PTR_WIDTH-1:0]  start_macro_id_q, start_macro_id_d;
  logic [ADDR_WIDTH-1:0]       window_size_q,    window_size_d;
  agu_mode_e                   agu_mode_q,       agu_mode_d;
  logic [95:0]                 payload_q,        payload_d;
  logic [ADDR_WIDTH-1:0]       base_addr_q,      base_addr_d;

  logic [ADDR_WIDTH-1:0]      req_cnt_q,      req_cnt_d;
  logic [ADDR_WIDTH-1:0]      bus_cnt_q,      bus_cnt_d;

  logic [MACRO_CNT_WIDTH-1:0] num_macros_needed_q, num_macros_needed_d;
  logic [MACRO_PTR_WIDTH-1:0] macro_table_q [M_MACROS/2]; 
  logic [MACRO_PTR_WIDTH-1:0] macro_table_d [M_MACROS/2];
  logic [MACRO_CNT_WIDTH-1:0] prep_cnt_q,   prep_cnt_d;
  logic [M_MACROS-1:0]        macro_mask_q, macro_mask_d;

  logic [ADDR_WIDTH-1:0] current_addr;
  logic                  job_start; 
  logic                  can_issue_req;
  logic                  fifo_empty;
  logic                  pipeline_full;

  assign pipeline_full     = ((req_cnt_q - bus_cnt_q) >= 4);
  assign can_issue_req     = (state_q == RUN) && 
                             !pipeline_full &&
                             (req_cnt_q < window_size_q);

  assign bp_addr_o         = current_addr[OFFSET_WIDTH-1:0] * DATA_WIDTH_BYTES;
  assign bp_macro_sel_o    = macro_table_q[current_addr >> OFFSET_WIDTH];
  assign bp_req_o          = can_issue_req;

  assign bus_valid_o       = !fifo_empty;
  assign bus_addr_o        = base_addr_q + (bus_cnt_q * DATA_WIDTH_BYTES);

  // Meta IF
  always_comb begin
    ptr_valid_o       = 1'b0;
    ptr_stream_id_o   = '0;
    ptr_o             = '0;

    if (state_q != IDLE) begin
      ptr_valid_o     = 1'b1;
      ptr_stream_id_o = stream_id_q;
      ptr_o           = base_addr_q + (bus_cnt_q * DATA_WIDTH_BYTES);
    end else if (sel_i && job_assign_i.valid) begin
      ptr_valid_o     = 1'b1;
      ptr_stream_id_o = job_assign_i.pkt.stream_id;
      ptr_o           = job_addr_i;
    end
  end

  // AGU State Machine
  always_comb begin
    state_d             = state_q;
    req_cnt_d           = req_cnt_q;
    bus_cnt_d           = bus_cnt_q;
    num_macros_needed_d = num_macros_needed_q;
    macro_table_d       = macro_table_q;
    prep_cnt_d          = prep_cnt_q;
    macro_mask_d        = macro_mask_q;

    stream_id_d      = stream_id_q;
    start_macro_id_d = start_macro_id_q;
    window_size_d    = window_size_q;
    agu_mode_d       = agu_mode_q;
    payload_d        = payload_q;
    base_addr_d      = base_addr_q;

    job_start  = 1'b0;
    job_done_o = 1'b0;

    case (state_q)
      IDLE: begin
        if (sel_i && job_assign_i.valid) begin
          req_cnt_d = '0;
          bus_cnt_d = '0;
          job_start  = 1'b1;

          num_macros_needed_d = MACRO_PTR_WIDTH'((job_assign_i.pkt.window_size + (MACRO_DEPTH - 1)) >> OFFSET_WIDTH);

          macro_table_d[0]                           = job_assign_i.pkt.start_macro;
          prep_cnt_d                                 = 1;
          macro_mask_d                               = '0;
          macro_mask_d[job_assign_i.pkt.start_macro] = 1'b1;

          stream_id_d      = job_assign_i.pkt.stream_id;
          start_macro_id_d = job_assign_i.pkt.start_macro;
          window_size_d    = job_assign_i.pkt.window_size;
          agu_mode_d       = agu_mode_e'(job_assign_i.pkt.mode);
          payload_d        = job_assign_i.pkt.payload;
          base_addr_d      = job_addr_i;

          state_d = PREPARE;
        end
      end

      PREPARE: begin
        if (prep_cnt_q >= num_macros_needed_q) begin
          state_d = RUN;
        end else begin
          logic [MACRO_PTR_WIDTH-1:0] next_ptr;
          next_ptr                  = next_pointer_i[macro_table_q[prep_cnt_q-1]];
          macro_table_d[prep_cnt_q] = next_ptr;
          macro_mask_d[next_ptr]    = 1'b1;
          prep_cnt_d                = prep_cnt_q + 1;
        end
      end

      RUN: begin
        job_start = 1'b0;
        // Prefetch BP 
        if (can_issue_req && bp_gnt_i) begin
          req_cnt_d = req_cnt_q + 1;
        end

        // Bus transaction
        if (bus_valid_o && bus_ready_i) begin
          bus_cnt_d = bus_cnt_q + 1;
          if (bus_cnt_q == window_size_q - 1) begin
            state_d = FINISH;
          end
        end
      end

      FINISH: begin
        if (req_cnt_q == bus_cnt_q) begin
          macro_mask_d = '0; 
          job_done_o   = 1'b1;
          state_d      = IDLE;
        end 
      end

      default: state_d = IDLE;
    endcase
  end

  assign bp_release_o = (state_q == FINISH) ? macro_mask_q : '0;
  assign ptr_done_o   = job_done_o; 

  // Address Generation Logic
  logic [ADDR_WIDTH-1:0] addr_all [NUM_MODES];
  logic [NUM_MODES-1:0]  req_all;

  assign addr_all[MODE_LINEAR] = req_cnt_q;
  assign req_all               = NUM_MODES'(can_issue_req && bp_gnt_i) << agu_mode_q;

  strided_addr_gen #(
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_strided_addr_gen (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .job_start_i(job_start),
    .req_i(req_all[MODE_STRIDED]),
    .base_addr_i('0),
    .payload_i(payload_q),
    .addr_o(addr_all[MODE_STRIDED])
  );  

  always_comb begin
    case (agu_mode_q)
      MODE_LINEAR:  current_addr = addr_all[MODE_LINEAR];
      MODE_STRIDED: current_addr = addr_all[MODE_STRIDED];
      default:      current_addr = addr_all[MODE_LINEAR];
    endcase
  end

  fwft_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(4)
  ) u_fwft_fifo (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .push_i(bp_r_valid_i),
    .data_i(bp_r_rdata_i),
    .full_o(),
    .pop_i(bus_valid_o && bus_ready_i),
    .data_o(bus_wdata_o),
    .empty_o(fifo_empty)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;

      stream_id_q      <= '0;
      start_macro_id_q <= '0;
      window_size_q    <= '0;
      agu_mode_q       <= MODE_LINEAR;
      payload_q        <= '0;
      base_addr_q      <= '0;

      req_cnt_q           <= '0;
      bus_cnt_q           <= '0;
      num_macros_needed_q <= '0;
      macro_table_q       <= '{default:'0};
      prep_cnt_q          <= '0;
      macro_mask_q        <= '0;

    end else begin
      state_q <= state_d;

      stream_id_q      <= stream_id_d;
      start_macro_id_q <= start_macro_id_d;
      window_size_q    <= window_size_d;
      agu_mode_q       <= agu_mode_d;
      payload_q        <= payload_d;
      base_addr_q      <= base_addr_d;

      req_cnt_q           <= req_cnt_d;
      bus_cnt_q           <= bus_cnt_d;
      num_macros_needed_q <= num_macros_needed_d;
      macro_table_q       <= macro_table_d;
      prep_cnt_q          <= prep_cnt_d;
      macro_mask_q        <= macro_mask_d;
    end
  end

endmodule
