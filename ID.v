module ID (input wire [31:0] instruction, input wire [31:0] pc,input clk,rst,output reg brch, 
output reg [31:0] pc_branch, output reg [31:0] instruction1,
output wire [15:0]sp_add,output reg [31:0] pc1,
output reg [4:0] ard,ars1,ars2,output reg [15:0] rs1,rs2, input wire [5:0]  flags,//alu
input wr, input [4:0] addr, input [15:0] update_r, // for write back stage
input wire [15:0] A,B, output wire [15:0] data_out,
output reg [3:0] con, input wr_ex,su);

reg [15:0] registor[31:0]; // all registors 
reg [15:0] sp; // default 1A hex
assign sp_add = sp;
assign data_out = registor[instruction[25:21]];

always @(posedge clk or posedge rst) begin
registor[0] <= A;
if (rst) begin
        registor[0]  <= 16'b0; //A
        registor[1]  <= 16'b0; //B
        registor[2]  <= 16'b0;
        registor[3]  <= 16'b0;
        registor[4]  <= 16'b0;
        registor[5]  <= 16'b0;
        registor[6]  <= 16'b0;
        registor[7]  <= 16'b0;
        registor[8]  <= 16'b0;
        registor[9]  <= 16'b0;
        registor[10] <= 16'b0;
        registor[11] <= 16'b0;
        registor[12] <= 16'b0;
        registor[13] <= 16'b0;
        registor[14] <= 16'b0;
        registor[15] <= 16'b0;
        registor[16] <= 16'b0;
        registor[17] <= 16'b0;
        registor[18] <= 16'b0;
        registor[19] <= 16'b0;
        registor[20] <= 16'b0;
        registor[21] <= 16'b0;
        registor[22] <= 16'b0;
        registor[23] <= 16'b0;
        registor[24] <= 16'b0;
        registor[25] <= 16'b0;
        registor[26] <= 16'b0;
        registor[27] <= 16'b0;
        registor[28] <= 16'b0;
        registor[29] <= 16'b0;
        registor[30] <= 16'b0; //MARl
        registor[31] <= 16'b0; // MARh
        sp <= 16'h1A;
        instruction1 <= 32'b0;
end else if ((wr_ex|su)|wr) begin
if (wr_ex) begin
registor[1] <= B;
end 
if (su) begin
 sp <= A;
end 
if (wr) begin
        if (addr != 5'b0) begin  // Prevent writing to r0 (A)
            registor[addr] <= update_r;
        end
    end
end
end

always @(posedge clk) begin
 pc1 <= pc;
 instruction1 <= instruction;
  brch <= 1'b0;
case (instruction[31:30])
    2'b00: begin
        if(instruction[2:0] == 3'b000) begin // normal r type
         ard <= instruction[25:21];   // Destination register (for R-type)
         ars1 <= instruction[20:16]; // Source register 1
         ars2 <= instruction[15:11]; // Source register 2
         rs1<= registor[instruction[20:16]];
         rs2 <= registor[instruction[15:11]];
         con <= instruction[29:26];
         end else if(instruction[1:0] == 2'b11 && instruction[29:26] == 4'b0100) begin //return
         con <= instruction[29:26];
         ard <= 5'b0;
         ars1 <= 5'b0; // Source register 1
         ars2 <= 5'b0; // Source register 2
         rs1<= sp;
         rs2 <= 16'h3;
         end 
    end
    
    2'b01: begin //imm
         ard <= instruction[25:21];   // Destination register (for R-type)
         ars1 <= instruction[20:16]; // Source register 1
         rs1<= registor[instruction[20:16]];
         rs2 <= instruction[15:0];
         con <= instruction[29:26];
    end
    
    2'b10: begin //store
        case (instruction[27:26])
        
         2'b00 : begin  // load
         ard <= instruction[25:21];   // Destination register
         ars1 <= instruction[20:16]; // Source register 1
         rs1<= registor[instruction[20:16]];
         rs2 <= instruction[15:0];
         con <= 4'b0100;
         end
         
         2'b01 : begin
         ard <= instruction[25:21];   // Destination register
         ars1 <= instruction[20:16]; // Source register 1
         rs1<= registor[instruction[20:16]];
         rs2 <= instruction[15:0];
         con <= 4'b0010;
         end
        
         2'b10 : begin
         ars1 <= instruction[25:21];   // Destination register
         ars2 <= instruction[20:16]; // Source register 1
         rs1<= registor[instruction[20:16]];
         rs2 <= instruction[15:0];
         con <= 4'b0100;
         end
         
         2'b11 : begin // store
         ars1 <= instruction[25:21];   // Destination register
         ars2 <= instruction[20:16]; // Source register 1
         rs1<= registor[instruction[20:16]];
         rs2 <= instruction[15:0];
         con <= 4'b0010;
         end
         endcase
    end
    
    2'b11 : begin //jump or call. for call the sp will update on mem stage andd call instruction[0]==1
         brch <= 1'b1;
         pc_branch = {registor[31], registor[30]};
         
         if(instruction[2:0] == 3'b101) begin //call
         con <= 4'b0010;
         ard <= 5'b0;
         ars1 <= 16'b0; // Source register 1
         ars2 <= 16'b0; // Source register 2
         rs1<= sp;
         rs2 <= 16'h3;
         end
         
         case (instruction[28:26])
         3'b000 : begin // unconditon jumm
          brch = 1'b1;
         end
         
         3'b001 : begin //jump on carry
         if (~flags[1]) begin brch <= 1'b0; end
         end
         
         3'b010 : begin //jump on negative
         if (~flags[4]) begin brch <= 1'b0; end
         end
         
         3'b011 : begin //jump on positive
         if (flags[4]) begin brch <= 1'b0; end
         end
         
         3'b100 : begin //jump on even
         if (flags[0]) begin brch <= 1'b0; end
         end
         
         3'b101 : begin //jump on odd
         if (~flags[0]) begin brch <= 1'b0; end
         end
         
         3'b110 : begin //jump on positive reg
         if (registor[instruction[25:21]]<registor[instruction[20:16]]) begin brch <= 1'b0; end
         end
         
         3'b111 : begin //jump on equal reg
         if (!(registor[instruction[25:21]]==registor[instruction[20:16]])) begin brch <= 1'b0; end
         end   
         endcase
    end
    //sel for flage is instution[15:16] in alu
//for return i m going to to used 29 bit of instruction from branch type in mem state
endcase
end
endmodule