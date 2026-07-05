module stream_generator #(
  parameter int N_STREAMS  = 4,
  parameter int DATA_WIDTH = 32,
  parameter int STREAM_OFFSET_WIDTH = 10
)(
  input logic clk_i,
  input logic rst_ni,

  // Stream IF
  output logic [DATA_WIDTH-1:0] stream_data_o  [N_STREAMS],
  output logic [N_STREAMS-1:0]  stream_valid_o,
  input logic  [N_STREAMS-1:0]  stream_ready_i,

  // Control IF
  input logic [N_STREAMS-1:0]  stream_en_i,
  input logic [DATA_WIDTH-1:0] stream_interval_i [N_STREAMS]
);

  localparam [DATA_WIDTH-1:0] STREAM_OFFSET_STEP = (1 << STREAM_OFFSET_WIDTH);

  for (genvar i = 0; i < N_STREAMS; i++) begin : gen_stream
    logic [DATA_WIDTH-1:0] data_cnt_q,     data_cnt_d;
    logic [DATA_WIDTH-1:0] interval_cnt_q, interval_cnt_d;
    logic                  valid_q,        valid_d;

    localparam logic [DATA_WIDTH-1:0] START_VAL = (i * STREAM_OFFSET_STEP);
    localparam logic [DATA_WIDTH-1:0] END_VAL   = START_VAL + STREAM_OFFSET_STEP - 1;

    assign stream_data_o[i]     = data_cnt_q;
    assign stream_valid_o[i]    = valid_q && stream_en_i[i];

    always_comb begin
      data_cnt_d     = data_cnt_q;
      interval_cnt_d = interval_cnt_q;
      valid_d        = valid_q;

      if (stream_en_i[i]) begin
        if (valid_q && stream_ready_i[i]) begin
          valid_d = 1'b0;
        end

        if ((stream_interval_i[i] <= 1) || (interval_cnt_q >= stream_interval_i[i] - 1)) begin
          valid_d = 1'b1;
          
          data_cnt_d     = (data_cnt_q == END_VAL) ? START_VAL : data_cnt_q + 1;
          interval_cnt_d = '0;
        end else begin
          interval_cnt_d = interval_cnt_q + 1;
        end
      end else begin
        valid_d = 1'b0;
        interval_cnt_d = '0;
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        data_cnt_q     <= START_VAL;
        interval_cnt_q <= '0;
        valid_q        <= '0;
      end else begin
        data_cnt_q     <= data_cnt_d;
        interval_cnt_q <= interval_cnt_d;
        valid_q        <= valid_d;
      end
    end

  end

endmodule
