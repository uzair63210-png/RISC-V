module IF_Buffer (input wire [31:0] instruction_in,input wire [20:0] pc_in,input clk,rst,
output reg [31:0] instruction_out,output reg [20:0] pc_out);

always@(posedge clk) begin
if (rst) begin
pc_out <= 21'b0;
instruction_out <= 32'b0;
end else begin
pc_out <= pc_in;
instruction_out <= instruction_in;
end
end
endmodule



module IF_stage (input [20:0] PC_branch,input brch,rst,clk,output reg [20:0] pc,output reg [31:0] instruction);
wire [20:0] pc_i;
wire [31:0] instruction_i;

IF(PC_branch,brch,rst,clk,instruction_i,pc_i);
IF_Buffer (instruction_i,pc_i,clk,rst,
instruction_out,pc_out);


endmodule