module IF_Buffer #(parameter [31:0] NOP = 32'h3C000000) (
    input  wire        clk, rst, stall, flush,
    input  wire [31:0] instruction_in, pc_in,
    output reg  [31:0] instruction_out, pc_out
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc_out          <= 32'b0;
            instruction_out <= 32'b0;
        end else if (flush) begin         
            pc_out          <= pc_in;
            instruction_out <= NOP;
        end else if (!stall) begin
            pc_out          <= pc_in;
            instruction_out <= instruction_in;
        end
    end
endmodule



module IF_stage (
    input [31:0] PC_branch,
    input brch, rst, clk,
    output [31:0] pc,
    output [31:0] instruction,
    input stall
);

    wire [31:0] pc_i;
    wire [31:0] instruction_i;


    IF IFetch(PC_branch, brch, rst, clk, instruction_i, pc_i, stall);
    IF_Buffer BUFF( clk, rst, stall, brch, instruction_i, pc_i, instruction, pc);

endmodule