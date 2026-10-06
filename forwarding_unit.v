module forwarding_unit #(parameter ACC_FWD = 1) (
    input  wire [5:0]  rd_ex, input wire [15:0] ex_val,   // EX/MEM
    input  wire [5:0]  rd_mm, input wire [15:0] mm_val,   // MEM/WB
    input  wire [5:0]  rd_wb, input wire [15:0] wb_val,   // WB buffer
    input  wire [4:0]  rs1, rs2,
    input  wire        use1, use2,
    input  wire [15:0] rs1_val, rs2_val,
    output reg  [15:0] out1, out2
);
    always @(*) begin
        if      (ACC_FWD != 0 && use1 && rs1 == 5'b0)                          out1 = ex_val;
        else if (rd_ex[5] && rd_ex[4:0] != 5'b0 && rd_ex[4:0] == rs1)          out1 = ex_val;
        else if (rd_mm[5] && rd_mm[4:0] != 5'b0 && rd_mm[4:0] == rs1)          out1 = mm_val;
        else if (rd_wb[5] && rd_wb[4:0] != 5'b0 && rd_wb[4:0] == rs1)          out1 = wb_val;
        else                                                                    out1 = rs1_val;
    end
    always @(*) begin
        if      (ACC_FWD != 0 && use2 && rs2 == 5'b0)                          out2 = ex_val;
        else if (rd_ex[5] && rd_ex[4:0] != 5'b0 && rd_ex[4:0] == rs2)          out2 = ex_val;
        else if (rd_mm[5] && rd_mm[4:0] != 5'b0 && rd_mm[4:0] == rs2)          out2 = mm_val;
        else if (rd_wb[5] && rd_wb[4:0] != 5'b0 && rd_wb[4:0] == rs2)          out2 = wb_val;
        else                                                                    out2 = rs2_val;
    end
endmodule

module load_use_hazard (
    input  wire       is_load_ex,
    input  wire [4:0] ld_rd,            // ID/EX dest (the load's rd)
    input  wire [4:0] id_rs1, id_rs2,   // sources of instruction in ID
    output wire       stall
);
    assign stall = is_load_ex && (ld_rd != 5'b0) &&
                   (ld_rd == id_rs1 || ld_rd == id_rs2);
endmodule

module store_data_fwd (
    input  wire [4:0]  st_reg,                          // store data reg (EX/MEM ard[4:0])
    input  wire [15:0] rf_val,                          // raw regfile read
    input  wire [5:0]  rd_mm, input wire [15:0] mm_val, // MEM/WB (incl. load data)
    input  wire [5:0]  rd_wb, input wire [15:0] wb_val, // WB buffer
    output wire [15:0] st_data
);
    assign st_data =
        (st_reg == 5'b0)                                   ? rf_val :
        (rd_mm[5] && rd_mm[4:0] == st_reg)                 ? mm_val :
        (rd_wb[5] && rd_wb[4:0] == st_reg)                 ? wb_val :
                                                             rf_val;
endmodule