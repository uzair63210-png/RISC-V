module cpu (input clk,rst);

wire [3:0] con;
wire [31:0] instruction,instruction1,instructions,instructions2,pc,pc_brch,pc1,pc2;
wire [31:0] pc_out,pc_brch1;
wire brch,wr_ex,wr,su;
wire [15:0]sp_add,sp_add_,out;
wire return;
wire [15:0] A,B,data_out,update_r;
wire [4:0] addr;
wire [15:0] rs11,rs12,rs21;
wire [4:0] ars11,ars12,ars13,ars21,ars22,ars23,ard1,ard2,ard3;

assign pc_brch = (return) ? pc_out : pc_brch1;

IF_stage (pc_brch,brch|return,rst,clk,pc,instruction);

ID (instruction,pc,clk,rst,brch,pc_brch1,instruction1,sp_add,pc1,ard1,ars11,
ars21,rs11,rs21, flags,wr,addr, update_r,A,B,data_out,con,wr_ex,su);

ex_state (instruction1,instructions,clk,rst,sp_add,ard1,ars11,ars21,rs11,rs21,
out[5:0],flags,pc1,pc2,ard2,ars12,ars22,rs12,B,A,sp_add_,con,su,wr_ex,return);

MEM_state (instructions,pc_out,clk,rst,A,sp_add_,data_out,pc2,flags,instructions2,
ard2,ars12,ars22,ard3,ars13,ars23,out,return);

WB_state (instructions2,clk,rst,ard3,ars13,ars23,addr,out,wr,update_r);

endmodule