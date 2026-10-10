module MEM_Buffer (input [31:0] instruction, output reg [31:0] instructions,input clk,rst,rd,sprd,
input [5:0] ard,input [15:0] data_out,A,
output reg [5:0] ard_,output reg [15:0] out,output reg return);

always @(posedge clk or posedge rst) begin
        if (rst) begin
            instructions <= 32'b0;
            ard_ <= 6'b0;
            out <= 16'b0;
            return <= 1'b0;
        end  else begin
        instructions <= instruction;
            ard_[4:0] <= ard[4:0];
            ard_[5] <= (instruction[31] & ~instruction[30]) ? ~instruction[27] : ard[5];
            out <= (rd | sprd) ? data_out : A;
            return <= sprd; 
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
    output wire  [15:0] data_out, // Data read
    input  wire [15:0] sp,
    input wire [31:0] pc,
    input wire [5:0] flags,
    output wire [31:0] pc_out
);
    reg [15:0] mem [0:SIZE-1];
    assign data_out = sprd ? ((sp < SIZE) ? mem[sp] : 16'b0) :
                      (rd && (A < SIZE))  ? mem[A]  : 16'b0;   
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < SIZE; i = i + 1) begin
                mem[i] <= 16'b0;
            end
        end else begin
            if (wr && (A < SIZE)) begin
                mem[A] <= data_in;
            end
            if (spwr) begin
                mem[sp] <= flags;
                mem[sp - 1'b1] <= pc[15:0];
                mem[sp - 2'b10] <=  pc[31:16];
            end
        end
    end
    assign pc_out = {mem[sp + 1'b1],mem[sp + 2'b10]};
endmodule


module MEM_state (input [31:0] instruction, output [31:0] pc_out,
input wire clk,rst, input [15:0] A,sp,data_in,
input wire [31:0] pc,input wire [5:0] flags,
output [31:0] instructions,input [5:0] ard,input [4:0] ars1,ars2,output [5:0] 
ard_,output [15:0] out,output return);

wire wr,rd,sprd,spwr;
wire [15:0] d1;
assign wr = &{instruction[31],~instruction[30],instruction[27]};
assign rd = &{instruction[31],~instruction[30],~instruction[27]};
assign spwr = &{instruction[31],instruction[30],instruction[0],~instruction[1],instruction[2]};
assign sprd = &{~instruction[31],~instruction[30],~instruction[29],instruction[28],~instruction[27],~instruction[26],instruction[1],instruction[0]};

memory mem (clk,rst,wr,rd,spwr,sprd,A,data_in,d1,sp,pc,flags,pc_out);

MEM_Buffer buff (instruction,instructions,clk,rst,rd,sprd,
ard,d1,A,ard_,out,return);

endmodule