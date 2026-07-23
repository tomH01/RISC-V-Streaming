module meta #(
  parameter int N_STREAMS     = 4,
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,
  parameter int W_WORKERS     = 2,
  parameter int B_BANKS       = 2,
  parameter int BANK_DEPTH    = 16384,

  localparam int STREAM_PTR_WIDTH = (N_STREAMS > 1) ? $clog2(N_STREAMS) : 1,
  localparam int WORKER_PTR_WIDTH = (W_WORKERS > 1) ? $clog2(W_WORKERS) : 1,
  localparam int DATA_WIDTH_BYTES = DATA_WIDTH / 8,
  localparam int SRAM_SIZE_B      = B_BANKS * BANK_DEPTH * DATA_WIDTH_BYTES,
  localparam int SRAM_PTR_WIDTH   = $clog2(SRAM_SIZE_B)
)(
  input logic clk_i,
  input logic rst_ni,

  // Control IF
  input logic                  enable_i,
  input logic [DATA_WIDTH-1:0] l2_bank_base_i,

  // Subordinate IF
  input  logic                        meta_req_i,
  input  logic [ADDR_WIDTH-1:0]       meta_addr_i,
  output logic                        meta_gnt_o,
  input  logic                        meta_wen_i ,
  input  logic [DATA_WIDTH-1:0]       meta_wdata_i,
  input  logic [DATA_WIDTH_BYTES-1:0] meta_be_i,

  output logic [DATA_WIDTH-1:0] meta_r_rdata_o,
  output logic                  meta_r_valid_o,

  // L2 Allocator IF
  output logic                        dispatch_ready_o,
  input  logic                        dispatch_valid_i,
  input  logic [DATA_WIDTH-1:0]       dispatch_data_i,
  input  logic [WORKER_PTR_WIDTH-1:0] dispatch_worker_id_i,

  output logic [DATA_WIDTH-1:0] cpu_done_ptr_o,

  // Worker IF
  input logic [W_WORKERS-1:0]        ptr_valid_i,
  input logic [W_WORKERS-1:0]        ptr_done_i,
  input logic [STREAM_PTR_WIDTH-1:0] ptr_stream_id_i [W_WORKERS],
  input logic [ADDR_WIDTH-1:0]       ptr_i           [W_WORKERS]
);

  logic [DATA_WIDTH-1:0] cpu_done_ptr_q;
  logic [DATA_WIDTH-1:0] stream_ptrs_q [N_STREAMS];

  logic                  fifo_full;
  logic                  fifo_empty;
  logic                  fifo_push;  
  logic                  fifo_pop;
  logic [DATA_WIDTH-1:0] fifo_dout;

  logic [7:0] addr_offset;
  logic       is_stream_reg;
  logic       is_cpu_done_reg;
  logic       is_fifo_reg;
  logic [4:0] decoded_stream_id;

  assign addr_offset       = meta_addr_i[7:0];
  assign is_stream_reg     = (addr_offset < 8'h80);
  assign is_cpu_done_reg   = (addr_offset == 8'h80);
  assign is_fifo_reg       = (addr_offset == 8'h84);
  assign decoded_stream_id = addr_offset[6:2];

  assign meta_gnt_o = (meta_req_i && is_fifo_reg && meta_wen_i) ? ~fifo_empty : 1'b1;
  assign fifo_pop   = meta_req_i && meta_gnt_o && is_fifo_reg && meta_wen_i && !fifo_empty;

  logic [4:0] dispatch_stream_id;
  assign dispatch_stream_id = dispatch_data_i[31:27];

  assign fifo_push    = dispatch_valid_i && dispatch_ready_o;
  
  assign dispatch_ready_o = ~fifo_full;
  assign cpu_done_ptr_o   = cpu_done_ptr_q;

  // CPU IF
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cpu_done_ptr_q   <= '0;
      meta_r_valid_o <= 1'b0;
      meta_r_rdata_o <= '0;
    end else begin
      meta_r_valid_o <= 1'b0;

      // CPU Write
      if (meta_req_i && meta_gnt_o && !meta_wen_i) begin
        if (is_cpu_done_reg) begin
          cpu_done_ptr_q <= meta_wdata_i;
        end
      end

      // CPU Read
      if (meta_req_i && meta_gnt_o && meta_wen_i) begin
        meta_r_valid_o <= 1'b1;

        if (is_stream_reg && (decoded_stream_id < N_STREAMS)) begin
          meta_r_rdata_o <= stream_ptrs_q[decoded_stream_id];
        end else if (is_cpu_done_reg) begin
          meta_r_rdata_o <= cpu_done_ptr_q;
        end else if (is_fifo_reg) begin
          meta_r_rdata_o <= fifo_dout;          
        end else begin
          meta_r_rdata_o <= '0;
        end
      end
    end
  end

  // Worker IF
  logic [W_WORKERS-1:0]        retired_workers_q [N_STREAMS];
  logic [WORKER_PTR_WIDTH-1:0] top_worker_id     [N_STREAMS];
  logic [N_STREAMS-1:0]        order_fifo_empty;
  logic [N_STREAMS-1:0]        order_fifo_pop;


  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      retired_workers_q <= '{default: '0};
    end else begin
      for (int w = 0; w < W_WORKERS; w++) begin
        if (ptr_valid_i[w] && ptr_done_i[w]) begin
          retired_workers_q[ptr_stream_id_i[w]][w] <= 1'b1;
        end
      end

      for (int s = 0; s < N_STREAMS; s++) begin
        if (order_fifo_pop[s]) begin
          retired_workers_q[s][top_worker_id[s]] <= 1'b0;
        end
      end
    end
  end

  generate
    for (genvar i = 0; i < N_STREAMS; i++) begin : gen_streams
      logic                        order_fifo_push;
      logic [WORKER_PTR_WIDTH-1:0] order_fifo_din;

      assign order_fifo_push = fifo_push && (dispatch_stream_id == i);
      assign order_fifo_din  = dispatch_worker_id_i;

      assign order_fifo_pop[i] = !order_fifo_empty[i] &&
                                 (retired_workers_q[i][top_worker_id[i]] ||
                                 (ptr_valid_i[top_worker_id[i]] && ptr_done_i[top_worker_id[i]]));

      fwft_fifo #(
        .DATA_WIDTH(WORKER_PTR_WIDTH),
        .DEPTH(W_WORKERS)
      ) u_stream_order_fifo (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .push_i(order_fifo_push),
        .data_i(order_fifo_din),
        .full_o(),

        .pop_i(order_fifo_pop[i]),
        .data_o(top_worker_id[i]),
        .empty_o(order_fifo_empty[i])
      );

      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          stream_ptrs_q[i] <= '0;
        end else if (!enable_i) begin
          stream_ptrs_q[i] <= l2_bank_base_i;
        end else begin
          if (!order_fifo_empty[i] && ptr_valid_i[top_worker_id[i]]) begin
            stream_ptrs_q[i] <= ptr_i[top_worker_id[i]];
          end
        end
      end

    end
  endgenerate

  fwft_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(16)
  ) u_dispatch_fifo (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .push_i(fifo_push),
    .data_i(dispatch_data_i),
    .full_o(fifo_full),

    .pop_i(fifo_pop),
    .data_o(fifo_dout),
    .empty_o(fifo_empty)
  );

endmodule
