module ex_Buffer(input [31:0] instruction, output reg [31:0] instructions,input clk,rst,
input [15:0]sp_add,input [4:0] ard,ars1,ars2,input [15:0] rs1,rs2,B,A,
input [5:0]  flag,output reg [5:0] flags,input wire [31:0] pc,output reg [31:0] pc1,
output reg [4:0] ard_,ars1_,ars2_,output reg [15:0] rs1_,B_,A_,output reg [15:0]sp_add_,output reg su);

always @(posedge clk or posedge rst) begin
        if (rst) begin
            instructions <= 32'b0;
            flags <= 6'b0;
            ard_ <= 5'b0;
            ars1_ <= 5'b0;
            ars2_ <= 5'b0;
            A_ <= 16'b0;
            B_ <= 16'b0;
            rs1_ <= 16'b0;
            sp_add_ <= 16'b0;
            pc1 <= 16'b0;
            su <= 1'b0;
        end  else begin
            if (&{~instruction[31],~instruction[30],~instruction[29],instruction[28],~instruction[27],~instruction[26],instruction[1],instruction[0]}) begin
            su <= 1'b1;
            end
        instructions <= instruction;
            flags <= flag;
            ard_ <= ard;
            ars1_ <= ars1;
            ars2_ <= ars2;
            A_ <= A;
            B_ <= B;
            rs1_ <= rs1;
            sp_add_ <= sp_add;
            pc1 <= pc;
        end
end
endmodule



module ex_state ( input [31:0] instruction, output [31:0] instructions,input clk,rst,
input [15:0]sp_add,input [4:0] ard,ars1,ars2,input [15:0] rs1,rs2,
input [5:0]  flag,output [5:0] flags,input wire [31:0] pc,output [31:0] pc1,
output [4:0] ard_,ars1_,ars2_,output [15:0] rs1_,B_,A_,output [15:0]sp_add_,
input [3:0] con,output su,wr,input f0
);
wire [15:0] A1,B1;
wire [5:0]f; 
ALU alu (rs1,rs2,con,clk,rst,instruction[10:9],A1,B1,f,flag,wr,f0);

ex_Buffer buff(instruction,instructions,clk,rst,sp_add,ard,ars1,ars2,rs1,rs2,B1,A1,
f,flags,pc,pc1,ard_,ars1_,ars2_,rs1_,B_,A_,sp_add_,su);
endmodule