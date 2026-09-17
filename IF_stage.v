module IF_Buffer (input wire [31:0] instruction_in,input wire [31:0] pc_in,input clk,rst,
output reg [31:0] instruction_out,output reg [31:0] pc_out,input stall);

always@(posedge clk) begin
if (rst) begin
pc_out <= 32'b0;
instruction_out <= 32'b0;
end else if (!stall) begin
pc_out <= pc_in;
instruction_out <= instruction_in;
end
end
endmodule



module IF_stage (
    input [31:0] PC_branch,
    input brch, rst, clk,
    output reg [31:0] pc,
    output reg [31:0] instruction,
    input stall, wrong
);

    wire [31:0] pc_i;
    wire [31:0] instruction_i;
    wire [31:0] pc_buf;
    wire [31:0] instruction_buf;

    IF IFetch(PC_branch, brch, rst, clk, instruction_i, pc_i, stall, wrong);
    IF_Buffer BUFF(instruction_i, pc_i, clk, rst, instruction_buf, pc_buf, stall);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc <= 32'b0;
            instruction <= 32'b0;
        end else if (!stall) begin
            pc <= pc_buf;
            instruction <= instruction_buf;
        end
    end
endmodule