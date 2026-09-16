module IF(input [31:0] PC_branch,input brch,rst,clk,output reg [31:0] instruction, 
output reg [31:0] pc, input stall,wrong);
reg [31:0] instruction_memory[2097151:0];
wire [31:0] next_pc;
reg [31:0] prev_pc;

assign next_pc = brch ? PC_branch : (stall) ? pc : (wrong) ? prev_pc : pc + 32'd1;

always @(posedge clk or posedge rst) begin
if(rst) begin
  pc <= 32'b0;
 instruction <= 32'b0;
 prev_pc <= 32'b0;
end
else  begin 
 prev_pc <= pc;
 pc <= next_pc;
instruction <= instruction_memory[pc];
end 
end
endmodule