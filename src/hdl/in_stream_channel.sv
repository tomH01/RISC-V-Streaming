module in_stream_channel #(
  parameter DATA_WIDTH = 32
)(
  input logic clk_i,
  input logic rst_ni,

  // Input stream interface
  input logic [DATA_WIDTH-1:0] data_i,
  input logic valid_i,
  output logic ready_o,

  // Output stream interface
  output logic [DATA_WIDTH-1:0] data_o,
  output logic valid_o,
  input logic ready_i
);

  assign ready_o = ready_i || !valid_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      data_o <= 'b0;
      valid_o <= 1'b0;
    end else begin
      if (ready_o) begin
        valid_o <= valid_i;

        if (valid_i) begin
          data_o <= data_i;
        end
      end
    end
  end

endmodule