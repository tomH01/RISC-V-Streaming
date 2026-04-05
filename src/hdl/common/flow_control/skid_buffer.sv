module skid_buffer #(
  parameter DATA_WIDTH = 32
)(
  input logic clk_i,
  input logic rst_ni,

  // Upstream IF
  input  logic                  us_valid_i,
  input  logic [DATA_WIDTH-1:0] us_data_i,
  output logic                  us_ready_o,

  // Downstream IF
  input  logic                  ds_ready_i,
  output logic                  ds_valid_o,
  output logic [DATA_WIDTH-1:0] ds_data_o
);
  logic [DATA_WIDTH-1:0] data_q;
  logic                  data_valid_q;

  logic [DATA_WIDTH-1:0] skid_q;
  logic                  skid_valid_q;

  assign ds_data_o  = data_q;
  assign ds_valid_o = data_valid_q;

  assign us_ready_o = ~skid_valid_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      data_q       <= '0;
      data_valid_q <= 1'b0;
      skid_q       <= '0;
      skid_valid_q <= 1'b0;
    end else begin

      if (ds_ready_i) begin
        if (skid_valid_q) begin
          // Skid data to output
          data_q       <= skid_q;
          data_valid_q <= 1'b1;
          skid_valid_q <= 1'b0;
        end else begin
          // Directly pass through
          data_q       <= us_data_i;
          data_valid_q <= us_valid_i;
        end
      end

      else if (us_valid_i && us_ready_o) begin
        if (!data_valid_q) begin
          // Store to reg
          data_q       <= us_data_i;
          data_valid_q <= 1'b1;
        end else begin
          // Store to skid
          skid_q       <= us_data_i;
          skid_valid_q <= 1'b1;
        end
      end
    end
  end

endmodule