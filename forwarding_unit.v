module forwarding_unit (
    input  wire [5:0]  rd_ex,      // {we_ex, rd_ex[4:0]}
    input  wire [15:0] ex_val, 
    input  wire [5:0]  rd_mm,     
    input  wire [15:0] mm_val,
    input  wire [5:0]  rd_wb,      
    input  wire [15:0] wb_val,     
    input  wire [4:0]  rs1, rs2,
    input  wire [15:0] rs1_val,   
    input  wire [15:0] rs2_val,   
    
    input  wire  is_load_ex, 

    output reg  [15:0] out1, out2,
    output reg         stall
);
    reg [1:0] sel1, sel2;

    always @(*) begin
        sel1 = 2'b00;
        if      (rd_ex[5] && (rd_ex[4:0] != 5'b0) && (rd_ex[4:0] == rs1))
            sel1 = 2'b01;  
        else if (rd_mm[5] && (rd_mm[4:0] != 5'b0) && (rd_mm[4:0] == rs1))
            sel1 = 2'b10; 
        else if (rd_wb[5] && (rd_wb[4:0] != 5'b0) && (rd_wb[4:0] == rs1))
            sel1 = 2'b11;

        case (sel1)
            2'b00: out1 = rs1_val;
            2'b01: out1 = ex_val;
            2'b10: out1 = mm_val;
            2'b11: out1 = wb_val;
            default: out1 = rs1_val;
        endcase
    end

    always @(*) begin
        sel2 = 2'b00;
        if      (rd_ex[5] && (rd_ex[4:0] != 5'b0) && (rd_ex[4:0] == rs2))
            sel2 = 2'b01;
        else if (rd_mm[5] && (rd_mm[4:0] != 5'b0) && (rd_mm[4:0] == rs2))
            sel2 = 2'b10;
        else if (rd_wb[5] && (rd_wb[4:0] != 5'b0) && (rd_wb[4:0] == rs2))
            sel2 = 2'b11;

        case (sel2)
            2'b00: out2 = rs2_val;
            2'b01: out2 = ex_val;
            2'b10: out2 = mm_val;
            2'b11: out2 = wb_val;
            default: out2 = rs2_val;
        endcase
    end

 always @(*) begin
        stall = 1'b0;
        if (is_load_ex && (rd_ex[4:0] != 5'b0) &&
            ((rd_ex[4:0] == rs1) || (rd_ex[4:0] == rs2)))
            stall = 1'b1;
    end

endmodule