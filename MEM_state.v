module MEM_Buffer (input [31:0] instruction, output reg [31:0] instructions,input clk,rst,rd,sprd,
input [4:0] ard,ars1,ars2,input [15:0] data_out,A,
output reg [4:0] ard_,ars1_,ars2_, output reg [15:0] out);

always @(posedge clk or posedge rst) begin
        if (rst) begin
            instructions <= 32'b0;
            ard_ <= 5'b0;
            ars1_ <= 5'b0;
            ars2_ <= 5'b0;
            out <= 16'b0;
        end  else begin
        instructions <= instruction;
            ard_ <= ard;
            ars1_ <= ars1;
            if (rd | sprd) begin
            out <= data_out;
            end else begin
            out <= A;
            end
            ars2_ <= ars2;
        end
end
endmodule

module memory #(
    parameter SIZE = 512,
    parameter ADDR_WIDTH = 16
)(
    input  wire  clk,rst,wr,rd,spwr,sprd,    
    input  wire [ADDR_WIDTH-1:0] A,      // Address
    input  wire [15:0] data_in, // Data to write
    output reg  [15:0] data_out, // Data read
    input  wire [15:0] sp,
    input wire [31:0] pc,input wire [5:0] flags,
    output wire [15:0] data_out1,data_out2
);
    reg [15:0] mem [0:SIZE-1];

    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < SIZE; i = i + 1) begin
                mem[i] <= 16'b0;
            end
            data_out <= 16'b0;
        end else begin
            if (wr && (A < SIZE)) begin
                mem[A] <= data_in;
            end
            if (rd && (A < SIZE)) begin
                data_out <= mem[A];
            end
            if (sprd) begin
                data_out <= mem[sp];
            end
            if (spwr) begin
            mem[sp] <= pc[31:16];
            mem[sp - 1'b1] <= pc[16:0];
            mem[sp - 2'b10] <= flags;
            end else if (!rd) begin
                data_out <= 16'b0;
            end
        end
    end
assign data_out1 = mem[sp + 1'b1];
assign data_out2 = mem[sp + 2'b10];
endmodule


module MEM_state (input [31:0] instruction, input wire clk,rst, input [15:0] A,sp,data_in,
input wire [31:0] pc,input wire [5:0] flags, output wire [15:0] data_out,data_out1,data_out2,
output [31:0] instructions,output [4:0] ard_,ars1_,ars2_,output [15:0] out);
wire wr,rd,sprd,spwr;
wire d1;
assign wr = &{instruction[31],~instruction[30],instruction[27]};
assign rd = &{instruction[31],~instruction[30],~instruction[27]};
assign spwr = &{instruction[31],instruction[30],instruction[0]};
assign sprd = &{~instruction[31],~instruction[30],~instruction[29],instruction[28],~instruction[27],~instruction[26],instruction[1],instruction[0]};

memory(clk,rst,wr,rd,spwr,sprd,A,d1,data_out,sp,pc,flage,data_out1,data_out2);

MEM_Buffer (instruction,instructions,clk,rst,rd,sprd,
ard,ars1,ars2,d1,A,ard_,ars1_,ars2_,);

endmodule
