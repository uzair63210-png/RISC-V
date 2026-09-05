module ALU (
    input  wire [15:0] A, B,
    input  wire [3:0]  con,
    input  wire        clk, rst,
    input  wire [1:0]      sel,
    output reg  [15:0] alu_out,
    output reg  [15:0] b_out,
    output reg [5:0]  flags,
    input  wire [5:0]  fg_i,
    output reg wr,
    input f0
);
    wire cin;
    wire [15:0] add_in,result;
    wire        adder_cout, sub_cout;
    assign cin = (con[0])? flags[1] : 1'b0;
    assign add_in = (con[2])? A : ~A;
    Adder_16bit adder_add (.a(add_in), .b(B), .cin(cin), .sum(result), .cout(adder_cout));

    always @(*) begin
    
    wr <= 1'b0;
        if (rst) begin
            alu_out <= 16'b0;
            b_out   <= 16'b0;
            flags   <= 6'b0;
        end else begin
            case (con)
                4'b0000: begin //move
                    alu_out <= A;
                    flags = {1'b0, 1'b0, ~|A, 1'b0, 1'b0, ^alu_out};
                end
                //overflow sign zero AC carry parity
                4'b0001: begin //xor
                    alu_out <= A ^ B;
                    flags = {1'b0, 1'b0, ~|alu_out, 1'b0, 1'b0, ^alu_out};
                end
                
                4'b0010: begin // sub
                    alu_out <= ~result;
                    flags = {sub_cout, sub_cout, ~|alu_out,A[7]&B[7] , sub_cout, ^alu_out};
                end
                
                4'b0011: begin // sub with borrow
                    alu_out <= ~result;
                    flags = {sub_cout, sub_cout, ~|alu_out,A[7]&B[7] , sub_cout, ^alu_out};
                end
                
                4'b0100: begin //add
                    alu_out <= result;
                    flags = {adder_cout, 1'b0,~|alu_out,A[7]&B[7], adder_cout,^alu_out};
                end
                
                4'b0101: begin // add with carry
                    alu_out <= result;
                    flags = {adder_cout, 1'b0,~|alu_out,A[7]&B[7], adder_cout,^alu_out};
                end
                
                4'b0110: begin //shift  left
                    alu_out <= A << 1;
                    flags = {1'b0, 1'b0, ~|alu_out, 1'b0, 1'b0, ^alu_out};
                end
                
                4'b0111: begin //shift right
                    alu_out <= A >> 1;
                    flags = {1'b0, 1'b0, ~|alu_out, 1'b0, 1'b0, ^alu_out};
                end
                
                4'b1000: begin //rotate left
                    {alu_out, flags[1]} <= {A, fg_i[1]} << 1;
                    flags = {1'b0, 1'b0, ~|alu_out, 1'b0, flags[1], ^alu_out};
                end
                
                4'b1001: begin //rotate right
                    {flags[1], alu_out} <= {fg_i[1], A} >> 1;
                    flags = {1'b0, 1'b0, ~|alu_out, 1'b0, flags[1], ^alu_out};
                end
                
                4'b1010: begin // campare
                    alu_out <= A;
                    if (A == B)      flags <= {3'b0, 1'b1, 2'b0};
                    else if (A > B)  flags <= 6'b0;
                    else             flags <= {4'b0, 1'b1, 1'b0};
                end
                
                4'b1011: begin // or
                    alu_out <= A | B;
                    flags = {1'b0, 1'b0, ~|alu_out, 1'b0, 1'b0, ^alu_out};
                end
                
                4'b1100: begin //not
                    alu_out <= ~A;
                    flags = {1'b0, 1'b0, ~|alu_out, 1'b0, 1'b0, ^alu_out};
                end
                
                4'b1101: begin //and
                    alu_out <= A & B;
                    flags = {1'b0, 1'b0, ~|alu_out, 1'b0, 1'b0, ^alu_out};
                end
                
                4'b1110: begin //multiple
                    {b_out, alu_out} <= A * B;
                    flags = {1'b0, 1'b0, ~|{b_out, alu_out}, 1'b0, 1'b0, ^{b_out, alu_out}};
                    wr <= 1'b1;
                end
                
                4'b1111: begin //flage operation
                    alu_out <= A;
                    if (sel == 2'b00) flags <= flags;
                    else if (sel == 2'b01)        flags[1] <= 1'b1;
                    else if(sel == 2'b10)     flags[1] <= ~flags[1];
                    else if (f0) flags <= fg_i;
                end
                
                default: begin
                    alu_out <= alu_out;
                    flags <= 6'b0;
                end
            endcase
        end
    end


endmodule
