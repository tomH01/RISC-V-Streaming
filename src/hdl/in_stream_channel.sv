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
  logic [DATA_WIDTH-1:0] data_reg;
  logic reg_valid;

  logic [DATA_WIDTH-1:0] skid_reg;
  logic skid_valid;

  assign ready_o = ~skid_valid;

  assign data_o = data_reg;
  assign valid_o = reg_valid;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      data_reg <= 'b0;
      reg_valid <= 1'b0;
      skid_reg <= 'b0;
      skid_valid <= 1'b0;
    end else begin
      if (ready_i) begin
        if (skid_valid) begin
          data_reg <= skid_reg;
          reg_valid <= 1'b1;
          skid_valid <= 1'b0;
        end else if (valid_i && ready_o) begin
          data_reg <= data_i;
          reg_valid <= 1'b1;
        end else begin
          reg_valid <= 1'b0;
        end
      end else begin
        if (valid_i && ready_o) begin
          if (!reg_valid) begin
            data_reg <= data_i;
            reg_valid <= 1'b1;
          end else begin
            skid_reg <= data_i;
            skid_valid <= 1'b1;
          end
        end
      end
    end
  end

endmodule