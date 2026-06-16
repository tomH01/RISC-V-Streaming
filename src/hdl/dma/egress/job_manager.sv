module job_manager #(
  parameter int N_STREAMS     = 4,
  parameter int M_MACROS      = 8,
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,
  parameter int FIFO_DEPTH    = 8,

  localparam int MACRO_PTR_WIDTH  = $clog2(M_MACROS),
  localparam int STREAM_PTR_WIDTH = $clog2(N_STREAMS)
)(
  input logic clk_i,
  input logic rst_ni,

  // Debug IF TODO: Remove after Testing
  output logic [N_STREAMS-1:0] dbg_arb_gnt_o,
  output logic                 dbg_arb_valid_o,
  output logic                 dbg_us_job_ready_o,
  output logic                 dbg_us_job_valid_o,

  // Notification IF
  input logic [N_STREAMS-1:0]       notif_valid_i,
  input logic [MACRO_PTR_WIDTH-1:0] notif_start_macro_i [N_STREAMS],

  // Control IF
  input logic [N_STREAMS-1:0]    cfg_push_i,
  input logic [4*DATA_WIDTH-1:0] cfg_wdata_i   [N_STREAMS],
  
  input logic [ADDR_WIDTH-1:0]   window_size_i [N_STREAMS],

  // Job IF
  job_if.tx_ready job_req_o
);

  typedef struct packed {
    logic [3:0]  mode;
    logic [11:0] apply_count;
    logic [15:0] window_id;
    logic [95:0] payload;
  } cfg_t;

  typedef job_req_o.job_pkt_t job_pkt_t;

  // Notification FIFOs
  logic [N_STREAMS-1:0]       notif_empty;
  logic [N_STREAMS-1:0]       notif_pop;
  logic [MACRO_PTR_WIDTH-1:0] notif_data  [N_STREAMS];

  // Config FIFOs
  logic [N_STREAMS-1:0] cfg_pop;
  cfg_t                 cfg_data [N_STREAMS];
  logic [N_STREAMS-1:0] cfg_empty;

  // Current Config
  cfg_t                 current_cfg_q   [N_STREAMS];
  logic [15:0]          apply_counter_q [N_STREAMS];

  cfg_t                 effective_cfg [N_STREAMS];
  logic [N_STREAMS-1:0] effective_active;
  logic [N_STREAMS-1:0] load_new_cfg;

  // Skid 
  job_pkt_t us_job_data;
  logic     us_job_valid;
  logic     us_job_ready;

  // Arbiter
  logic [N_STREAMS-1:0] stream_ready_vec;
  logic [N_STREAMS-1:0] stream_gnt_vec;
  logic                 arb_valid;

  rr_arbiter #(
    .NUM_REQS(N_STREAMS)
  ) u_stream_arbiter (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .req_i(us_job_ready),
    .ready_i(stream_ready_vec),
    .gnt_o(stream_gnt_vec),
    .valid_o(arb_valid)
  );

  generate
    for (genvar i = 0; i < N_STREAMS; i++) begin : gen_fifos

      assign stream_ready_vec[i] = ~notif_empty[i];
      assign notif_pop[i]        = stream_gnt_vec[i] & arb_valid;

      fwft_fifo #(
        .DATA_WIDTH(MACRO_PTR_WIDTH),
        .DEPTH(FIFO_DEPTH)
      ) u_notif_fifo (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .push_i(notif_valid_i[i]),
        .data_i(notif_start_macro_i[i]),
        .full_o(),

        .pop_i(notif_pop[i]),
        .data_o(notif_data[i]),
        .empty_o(notif_empty[i])
      );

      fwft_fifo #(
        .DATA_WIDTH(4*DATA_WIDTH),
        .DEPTH(FIFO_DEPTH)
      ) u_cfg_fifo (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .push_i(cfg_push_i[i]),
        .data_i(cfg_wdata_i[i]),
        .full_o(),

        .pop_i(cfg_pop[i]),
        .data_o(cfg_data[i]),
        .empty_o(cfg_empty[i])
      );

      // Pop logic
      always_comb begin
        cfg_pop[i] = 1'b0;

        if (!cfg_empty[i]) begin
          if (cfg_data[i].window_id <= current_cfg_q[i].window_id) begin
            cfg_pop[i] = 1'b1;
          end
        end
      end

      assign load_new_cfg[i] = cfg_pop[i] && (cfg_data[i].window_id == current_cfg_q[i].window_id);

      always_comb begin
        if (load_new_cfg[i]) begin
          effective_cfg[i]    = cfg_data[i];
          effective_active[i] = 1'b1; 
        end else begin
          effective_cfg[i] = current_cfg_q[i];
          effective_active[i] = (current_cfg_q[i].apply_count == '0) || 
                                (apply_counter_q[i] < current_cfg_q[i].apply_count);
        end
      end

      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          current_cfg_q[i]   <= '0;
          apply_counter_q[i] <= '0;
        end else begin

          if (load_new_cfg[i]) begin
            current_cfg_q[i]   <= cfg_data[i];

            if (stream_gnt_vec[i] && arb_valid) begin
              apply_counter_q[i]         <= 16'h1; 
              current_cfg_q[i].window_id <= cfg_data[i].window_id + 1;
            end else begin
              apply_counter_q[i] <= 16'h0;
            end

          end else if (stream_gnt_vec[i] && arb_valid) begin
            apply_counter_q[i] <= apply_counter_q[i] + 1;
            current_cfg_q[i].window_id <= current_cfg_q[i].window_id + 1;
          end

        end
      end
    end
  endgenerate

  always_comb begin
    us_job_valid = arb_valid;
    us_job_data  = '0;

    for (int i = 0; i < N_STREAMS; i++) begin
      if (stream_gnt_vec[i] && arb_valid) begin
        us_job_data.stream_id   = STREAM_PTR_WIDTH'(i);
        us_job_data.start_macro = notif_data[i];
        us_job_data.window_size = window_size_i[i];
        us_job_data.window_id   = current_cfg_q[i].window_id;

        if (effective_active[i]) begin
          us_job_data.mode    = effective_cfg[i].mode;
          us_job_data.payload = effective_cfg[i].payload;
        end else begin
          us_job_data.mode    = '0; // Linear Mode
          us_job_data.payload = '0;
        end
      end
    end
  end

  skid_buffer #(
    .DATA_WIDTH($bits(job_pkt_t))
  ) u_job_skid (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .us_valid_i(us_job_valid),
    .us_data_i(us_job_data),
    .us_ready_o(us_job_ready),

    .ds_ready_i(job_req_o.ready),
    .ds_valid_o(job_req_o.valid),
    .ds_data_o(job_req_o.pkt)
  );

  // Debug TODO: Remove after Testing
  assign dbg_arb_gnt_o       = stream_gnt_vec;
  assign dbg_arb_valid_o     = arb_valid;
  assign dbg_us_job_ready_o  = us_job_ready;
  assign dbg_us_job_valid_o  = us_job_valid;

endmodule
