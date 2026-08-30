module ID_Buffer (input wire clk, rst,input wire [31:0] instruction_in,input wire [31:0] pc_in,
input wire brch_in,input wire [31:0] pc_branch_in,input wire [15:0] sp_add_in,
input wire [4:0] ard_in, ars1_in, ars2_in,input wire [15:0] rs1_in, rs2_in,
input wire [15:0] data_out_in,input wire [3:0] con_in,   
output reg [31:0] instruction_out,output reg [31:0] pc_out, output reg brch_out,
output reg [31:0] pc_branch_out,output reg [15:0] sp_add_out,
output reg [4:0] ard_out, ars1_out, ars2_out, output reg [15:0] rs1_out, rs2_out,
output reg [15:0] data_out_out,output reg [3:0] con_out
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            instruction_out <= 32'b0;
            pc_out <= 32'b0;
            brch_out <= 1'b0;
            pc_branch_out <= 32'b0;
            sp_add_out <= 16'h001A;
            ard_out <= 5'b0;
            ars1_out <= 5'b0;
            ars2_out <= 5'b0;
            rs1_out <= 16'b0;
            rs2_out <= 16'b0;
            data_out_out <= 16'b0;
            con_out <= 4'b0;
        end else begin
            instruction_out <= instruction_in;
            pc_out <= pc_in;
            brch_out <= brch_in;
            pc_branch_out <= pc_branch_in;
            sp_add_out <= sp_add_in;
            ard_out <= ard_in;
            ars1_out <= ars1_in;
            ars2_out <= ars2_in;
            rs1_out <= rs1_in;
            rs2_out <= rs2_in;
            data_out_out <= data_out_in;
            con_out <= con_in;
        end
    end
endmodule


module ID (
input wire [31:0] instruction,pc,input clk, rst,output wire brch,output wire [31:0] pc_branch,
output wire [31:0] instruction1,output wire [15:0] sp_add,output wire [31:0] pc1,
output wire [4:0] ard, ars1, ars2,output wire [15:0] rs1, rs2,input wire [5:0] flags,input wr,
input [4:0] addr,input [15:0] update_r,input wire [15:0] A, B,output wire [15:0] data_out,
output wire [3:0] con,input wr_ex, su
);

    // Internal signals from decode logic
    reg [31:0] instruction_decoded;
    reg [31:0] pc_decoded;
    reg brch_decoded;
    reg [31:0] pc_branch_decoded;
    reg [15:0] sp_add_decoded;
    reg [4:0] ard_decoded, ars1_decoded, ars2_decoded;
    reg [15:0] rs1_decoded, rs2_decoded;
    reg [15:0] data_out_decoded;
    reg [3:0] con_decoded;
    
    // Register file
    reg [15:0] reg_file [0:31];
    reg [15:0] sp;
    
    assign sp_add = sp_add_decoded;
   
    integer i;
    always @(posedge clk or posedge rst) begin
        reg_file[0] <= A;
    
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                reg_file[i] <= 16'b0;
            end
            sp <= 16'h001A;
        end else if (wr_ex || su || wr) begin
            if (wr_ex) begin
                reg_file[1] <= B;  // Write to register 1 (B)
            end
            if (su) begin
                sp <= A;  // Update stack pointer
            end
            if (wr) begin
                if (addr != 5'b0) begin  // Prevent writing to r0
                    reg_file[addr] <= update_r;
                end
            end
        end
    end
    
    // Decode logic (combinational)
    always @(*) begin
        // Default assignments
        instruction_decoded = instruction;
        pc_decoded = pc;
        brch_decoded = 1'b0;
        pc_branch_decoded = 32'b0;
        sp_add_decoded = sp;
        ard_decoded = 5'b0;
        ars1_decoded = 5'b0;
        ars2_decoded = 5'b0;
        rs1_decoded = 16'b0;
        rs2_decoded = 16'b0;
        con_decoded = 4'b0;
        data_out_decoded = 16'b0;
        
        case (instruction[31:30])
            2'b00: begin  // R-type instructions
                if (instruction[2:0] == 3'b000) begin  // Normal R-type
                    ard_decoded = instruction[25:21];    // Destination register
                    ars1_decoded = instruction[20:16];   // Source register 1
                    ars2_decoded = instruction[15:11];   // Source register 2
                    rs1_decoded = reg_file[instruction[20:16]];
                    rs2_decoded = reg_file[instruction[15:11]];
                    con_decoded = instruction[29:26];
                end else if (instruction[1:0] == 2'b11 && instruction[29:26] == 4'b0100) begin
                    // Return instruction
                    con_decoded = instruction[29:26];
                    ard_decoded = 5'b0;
                    ars1_decoded = 5'b0;
                    ars2_decoded = 5'b0;
                    rs1_decoded = sp;
                    rs2_decoded = 16'h0003;
                end
            end
            
            2'b01: begin  // Immediate instructions
                ard_decoded = instruction[25:21];    // Destination register
                ars1_decoded = instruction[20:16];   // Source register 1
                rs1_decoded = reg_file[instruction[20:16]];
                rs2_decoded = instruction[15:0];     // Immediate value
                con_decoded = instruction[29:26];
            end
            
            2'b10: begin  // Load/Store instructions
                case (instruction[27:26])
                    2'b00: begin  // Load (add)
                        ard_decoded = instruction[25:21];
                        ars1_decoded = instruction[20:16];
                        rs1_decoded = reg_file[instruction[20:16]];
                        rs2_decoded = instruction[15:0];
                        con_decoded = 4'b0100;
                    end
                    
                    2'b01: begin  // Load (subtract)
                        ard_decoded = instruction[25:21];
                        ars1_decoded = instruction[20:16];
                        rs1_decoded = reg_file[instruction[20:16]];
                        rs2_decoded = instruction[15:0];
                        con_decoded = 4'b0010;
                    end
                    
                    2'b10: begin  // Store (add)
                        ars1_decoded = instruction[25:21];
                        ars2_decoded = instruction[20:16];
                        rs1_decoded = reg_file[instruction[20:16]];
                        rs2_decoded = instruction[15:0];
                        con_decoded = 4'b0100;
                    end
                    
                    2'b11: begin  // Store (subtract)
                        ars1_decoded = instruction[25:21];
                        ars2_decoded = instruction[20:16];
                        rs1_decoded = reg_file[instruction[20:16]];
                        rs2_decoded = instruction[15:0];
                        con_decoded = 4'b0010;
                    end
                endcase
                
                // Data output for store operations
                if (instruction[27] == 1'b1) begin
                    data_out_decoded = reg_file[ars1_decoded];
                end
            end
            
            2'b11: begin  // Branch/Call instructions
                brch_decoded = 1'b1;
                pc_branch_decoded = {reg_file[31], reg_file[30]};  // PC = {MARh, MARl}
                
                case (instruction[28:26])
                    3'b000: begin  // Unconditional jump
                        brch_decoded = 1'b1;
                    end
                    
                    3'b001: begin  // Jump on carry
                        if (~flags[1]) brch_decoded = 1'b0;
                    end
                    
                    3'b010: begin  // Jump on negative
                        if (~flags[4]) brch_decoded = 1'b0;
                    end
                    
                    3'b011: begin  // Jump on positive
                        if (flags[4]) brch_decoded = 1'b0;
                    end
                    
                    3'b100: begin  // Jump on even
                        if (flags[0]) brch_decoded = 1'b0;
                    end
                    
                    3'b101: begin  // Jump on odd
                        if (~flags[0]) brch_decoded = 1'b0;
                    end
                    
                    3'b110: begin  // Jump if reg1 < reg2
                        if (reg_file[instruction[25:21]] < reg_file[instruction[20:16]]) begin
                            brch_decoded = 1'b0;
                        end
                    end
                    
                    3'b111: begin  // Jump if reg1 == reg2
                        if (!(reg_file[instruction[25:21]] == reg_file[instruction[20:16]])) begin
                            brch_decoded = 1'b0;
                        end
                    end
                endcase
                
                // Call instruction (branch with instruction[2:0] == 101)
                if (brch_decoded == 1'b1 && instruction[2:0] == 3'b101) begin
                    con_decoded = 4'b0010;  // Subtract operation for SP update
                    ard_decoded = 5'b0;
                    ars1_decoded = 5'b0;
                    ars2_decoded = 5'b0;
                    rs1_decoded = sp;
                    rs2_decoded = 16'h0003;  // Subtract 3 from SP
                end
            end
        endcase
    end
    
    // Buffer instance
    ID_Buffer buffer_inst (
        .clk(clk),
        .rst(rst),
        .instruction_in(instruction_decoded),
        .pc_in(pc_decoded),
        .brch_in(brch_decoded),
        .pc_branch_in(pc_branch_decoded),
        .sp_add_in(sp_add_decoded),
        .ard_in(ard_decoded),
        .ars1_in(ars1_decoded),
        .ars2_in(ars2_decoded),
        .rs1_in(rs1_decoded),
        .rs2_in(rs2_decoded),
        .data_out_in(data_out_decoded),
        .con_in(con_decoded),
        
        .instruction_out(instruction1),
        .pc_out(pc1),
        .brch_out(brch),
        .pc_branch_out(pc_branch),
        .sp_add_out(sp_add),
        .ard_out(ard),
        .ars1_out(ars1),
        .ars2_out(ars2),
        .rs1_out(rs1),
        .rs2_out(rs2),
        .data_out_out(data_out),
        .con_out(con)
    );

endmodule
