module WB_Buffer (input [31:0] instruction ,input clk,rst,iwr,
input [4:0] ard,output reg [5:0] addr,input [15:0] data,output reg wr, output reg [15:0] out
);

always @(posedge clk or posedge rst) begin
        if (rst) begin
            addr <= 6'b0;
            out <= 16'b0;
            wr <= 1'b0;
        end else begin
            addr[4:0] <= ard;
            addr [5] <= ~((instruction[31]&instruction[30])| ((instruction[31]&~instruction[30]&instruction[27])));
            out <= data;
            wr <= iwr;
        end
      end
endmodule





module WB_state (input [31:0] instruction,input clk,rst,
input [4:0] ard,ars1,ars2,output [5:0] addr,input [15:0] data,output wr, output [15:0] out);
wire wr1;
assign wr1 = (&{~instruction[31],~instruction[27]} | & {~instruction[31],~instruction[30]});

WB_Buffer buff (instruction,clk,rst,wr1,ard,addr,data,wr,out);

endmodule