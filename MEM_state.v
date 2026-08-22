module MEM_Buffer (input [31:0] instruction, output reg [31:0] instructions,input clk,rst,rd,sprd,
input [4:0] ard,ars1,ars2,input [15:0] data_out,A,
output reg [4:0] ard_,ars1_,ars2_, output reg [15:0] out,output reg return);

always @(posedge clk or posedge rst) begin
        if (rst) begin
            instructions <= 32'b0;
            ard_ <= 5'b0;
            ars1_ <= 5'b0;
            ars2_ <= 5'b0;
            out <= 16'b0;
            return <= 1'b0;
        end  else begin
        instructions <= instruction;
            ard_ <= ard;
            ars1_ <= ars1;
            if (rd | sprd) begin
            out <= data_out;
                if(sprd) begin
                return <= 1'b1;
                end
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
    input wire [31:0] pc,
    input wire [5:0] flags,
    output wire [31:0] pc_out
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
            mem[sp] <= flags;
            mem[sp - 1'b1] <= pc[31:16];
            mem[sp - 2'b10] <=  pc[16:0];
            end else if (!rd & (~sprd)) begin
                data_out <= 16'b0;
            end
        end
    end
assign pc_out = {mem[sp + 1'b1],mem[sp + 2'b10]};
endmodule


module MEM_state (input [31:0] instruction, output [31:0] pc_out,
input wire clk,rst, input [15:0] A,sp,data_in,
input wire [31:0] pc,input wire [5:0] flags,
output [31:0] instructions,input [4:0] ard,ars1,ars2,output [4:0] ard_,ars1_,ars2_,output [15:0] out,output return);

wire wr,rd,sprd,spwr;
wire [15:0] d1;
assign wr = &{instruction[31],~instruction[30],instruction[27]};
assign rd = &{instruction[31],~instruction[30],~instruction[27]};
assign spwr = &{instruction[31],instruction[30],instruction[0]};
assign sprd = &{~instruction[31],~instruction[30],~instruction[29],instruction[28],~instruction[27],~instruction[26],instruction[1],instruction[0]};

memory(clk,rst,wr,rd,spwr,sprd,A,data_in,d1,sp,pc,flags,pc_out);

MEM_Buffer (instruction,instructions,clk,rst,rd,sprd,
ard,ars1,ars2,d1,A,ard_,ars1_,ars2_,out,return);

endmodule
