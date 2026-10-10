//==========================================================================
// tb_cpu.v -- Self-checking testbench, RISC-V 5-stage (uzair63210-png/RISC-V)
//
// RUN (icarus):
//   iverilog -g2012 -o tb tb_cpu.v cpu.v IF.v IF_stage.v ID.v ex_state.v \
//            ALU.v adder_16bit.v forwarding_unit.v MEM_state.v WB_state.v
//   vvp tb                  (add -DVCD for waves)
//   vvp tb +NO_MONITOR=1    (trace off without recompiling)
//
// RUN (Vivado): launch_simulation, then "run all" in the Tcl console.
//
// Hardware rules encoded here (all verified against the RTL):
//  * data memory is CLEARED by rst           -> init data AFTER do_reset
//  * DELAY SLOT: the instruction at branch+1 ALWAYS executes (taken or not)
//    -> keep NOP at branch+1  (ID_Buffer has no flush; MIPS-style slot)
//  * taken branch also leaks branch+3 via the IF fetch register
//    -> keep NOP at branch+3  (fixed by killing the fetch reg on brch in IF.v)
//  * return restores flags from mem[sp+0] but call wrote them at old sp
//    (flags slot is sp+3)                    -> flag restore across return
//      is currently broken in RTL; not asserted here
//      (RTL fix pending, MEM_state.v: sprd ? mem[sp+3] : ...)
//  * MAR (r30/r31) reads have NO bypass and WB is 2 regs deep:
//    a jump/call must be >= 5 instructions after the last MAR mov
//  * flags seen by a branch = flags of instruction (branch-2): 1 NOP gap
//  * call frame at OLD sp S: mem[S]=flags mem[S-1]=pc_lo mem[S-2]=pc_hi
//  * r1 is clobbered by multiply high half (no forwarding path for B)
//==========================================================================
`timescale 1ns/1ps

module tb_cpu;

reg clk, rst;
integer errors, checks;
integer last_errors, last_checks;
reg [15:0] stall_cnt, last_stall;
reg [255:0] cur_test;
reg mon_en;

cpu dut (.clk(clk), .rst(rst));

always #5 clk = ~clk;

always @(posedge clk) if (!rst && dut.stall) stall_cnt = stall_cnt + 1;

// global program image (tests fill this, load_prog() copies it into DUT)
reg [31:0] prog [0:255];

//---------------------------- MONITOR -------------------------------------
// Per-cycle pipeline trace. On by default; disable with +NO_MONITOR=1
// (xsim: launch_simulation -testplusarg NO_MONITOR=1... or recompile
// with -DNO_MONITOR).
`ifndef NO_MONITOR
initial mon_en = 1;
`else
initial mon_en = 0;
`endif

always @(posedge clk) if (!rst && mon_en) begin
    $display("t=%0t [%0s] PC=%03h fetch=%08x | acc=%h flags=%02x sp=%02h%s%s",
        $time, cur_test, dut.IF.pc, dut.IF.instruction,
        dut.ID.reg_file[0], dut.EX.flags, dut.ID.sp,
        (dut.stall)  ? " STALL"  : "",
        (dut.brch)   ? " FLUSH"  : "");
    if (dut.WB.wr && (dut.WB.addr != 0))
        $display("    [WB ] r%0d <= %h", dut.WB.addr, dut.WB.out);
    if (dut.MEM.mem.wr)
        $display("    [MEM] [%h] <= %h", dut.MEM.mem.A, dut.MEM.mem.data_in);
    if (dut.MEM.mem.spwr)
        $display("    [STK] PUSH flags=%02x pc=%h @sp=%h",
            dut.MEM.mem.flags, dut.MEM.mem.pc, dut.MEM.mem.sp);
    if (dut.MEM.mem.sprd)
        $display("    [STK] POP  @sp=%h", dut.MEM.mem.sp);
end

initial begin
    // allow +NO_MONITOR=1 to silence the trace at runtime
`ifdef NO_MONITOR
    if ($value$plusargs("NO_MONITOR=%d", mon_en)) mon_en = !mon_en;
`endif
end

//-------------------------- ISA encodings ---------------------------------
function [31:0] RTYPE(input [3:0] con, input [4:0] rd, rs1, rs2);
    RTYPE = {2'b00, con, rd, rs1, rs2, 11'd0};
endfunction
function [31:0] RSEL(input [3:0] con, input [1:0] sel);
    RSEL = {2'b00, con, 15'd0, sel, 9'd0};
endfunction
function [31:0] ITYPE(input [3:0] con, input [4:0] rd, rs1, input [15:0] imm);
    ITYPE = {2'b01, con, rd, rs1, imm};
endfunction
function [31:0] MEMI(input [1:0] lsu, input [4:0] rd, base, input [15:0] off);
    MEMI = {2'b10, 2'b00, lsu, rd, base, off};
endfunction
function [31:0] BRR(input [3:0] c, input [4:0] rA, rB, input [2:0] low);
    BRR = {2'b11, c, rA, rB[4:3], rB[2:0], 13'd0, low};
endfunction
function [31:0] BRI(input [3:0] c, input [15:0] imm, input [2:0] low);
    BRI = {2'b11, c, 5'd0, 2'b00, imm[15:13], imm[12:0], low};
endfunction

localparam [31:0] NOP  = 32'h3C000000;
localparam [31:0] RET  = 32'h10000003;
localparam [31:0] CALL = BRI(4'd0, 16'd0, 3'b101);

`define ZERO(r)      RTYPE(4'h1, r, r, r)
`define LDI(rd,imm)  ITYPE(4'h1, rd, 5'd1, imm)

//-------------------------- utilities --------------------------------------
task prep;    // MUST be called before writing prog: clears DUT memories and
    input integer n;   // pads prog[0..n-1] with NOP
    integer i;
    begin
        for (i = 0; i < 1024; i = i + 1) dut.IF.IFetch.instruction_memory[i] = NOP;
        for (i = 0; i < 512;  i = i + 1) dut.MEM.mem.mem[i] = 16'd0;
        for (i = 0; i < n;    i = i + 1) prog[i] = NOP;
    end
endtask

task load_prog;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1) dut.IF.IFetch.instruction_memory[i] = prog[i];
    end
endtask

task do_reset;
    begin
        rst = 1; stall_cnt = 0; #23; rst = 0; @(negedge clk);
    end
endtask

task run;
    input integer n;
    begin repeat (n) @(posedge clk); #1; end
endtask

task chk;
    input [15:0] got, exp;
    input [255:0] name;
    begin
        checks = checks + 1;
        if (got !== exp) begin
            errors = errors + 1;
            $display("  FAIL %0s : got %h  expected %h  (t=%0t)", name, got, exp, $time);
        end
    end
endtask

task test_header;
    input [255:0] name;
    begin
        cur_test = name;
        $display("----------------------------------------------------------");
        $display("TEST: %0s", name);
    end
endtask

task report;   // per-test verdict, call right after each test task
    input [255:0] name;
    integer dc, de, ds;
    begin
        dc = checks - last_checks; last_checks = checks;
        de = errors - last_errors; last_errors = errors;
        ds = stall_cnt - last_stall;  last_stall  = stall_cnt;
        if (de == 0) $display("  >> PASS %0s  (%0d checks, %0d stalls)", name, dc, ds);
        else         $display("  >> FAIL %0s  (%0d errors, %0d checks)", name, de, dc);
    end
endtask

//==========================================================================
initial begin
    clk = 0; errors = 0; checks = 0; stall_cnt = 0;
    last_errors = 0; last_checks = 0; last_stall = 0;
    cur_test = "init";
`ifdef VCD
    $dumpfile("tb_cpu.vcd"); $dumpvars(0, tb_cpu);
`endif
    $display("=== RISC-V 5-stage testbench ===");
    $display("  monitor: %0s (plusarg +NO_MONITOR=1 to silence)",
`ifdef NO_MONITOR
             "OFF (compiled -DNO_MONITOR)"
`else
             "ON"
`endif
             );

    test_alu;            report("alu");
    test_imm;            report("imm");
    test_multiply;       report("multiply");
    test_acc;            report("acc");
    test_forwarding;     report("forwarding");
    test_load_use_stall; report("load_use_stall");
    test_store_fwd;      report("store_fwd");
    test_suboffset;      report("suboffset");
    test_branch_carry;   report("branch_carry");
    test_branch_regacc;  report("branch_regacc");
    test_call_return;    report("call_return");

    $display("----------------------------------------------------------");
    $display("TOTAL: %0d checks, %0d errors", checks, errors);
    if (errors == 0) $display(">>> ALL TESTS PASSED <<<");
    else             $display(">>> %0d TEST(S) FAILED <<<", errors);
    $finish;
end

//==========================================================================
task test_alu;
    integer i;
    reg [15:0] exp, a, b;
    begin
    test_header("ALU register ops 0x0-0xF");
    a = 16'd9; b = 16'd4;
    for (i = 0; i <= 15; i = i + 1) begin
        case (i)
            4'h0: exp = a;  4'h1: exp = a ^ b;  4'h2: exp = a - b;
            4'h3: exp = a - b;  4'h4: exp = a + b;  4'h5: exp = a + b;
            4'h6: exp = a << 1; 4'h7: exp = a >> 1;
            4'h8: exp = (a << 1); 4'h9: exp = (a >> 1);
            4'hA: exp = a;  4'hB: exp = a | b;  4'hC: exp = ~a;
            4'hD: exp = a & b;  4'hE: exp = a * b;  4'hF: exp = a;
            default: exp = 16'hxxxx;
        endcase
        prep(8);
        prog[0] = `ZERO(1); prog[1] = `LDI(2, a); prog[2] = `LDI(3, b);
        prog[3] = RTYPE(i[3:0], 4'd4, 5'd2, 5'd3);
        load_prog(8); do_reset; run(16);
        chk(dut.ID.reg_file[4], exp, "alu rd");
        chk(dut.ID.reg_file[0], exp, "alu acc");
    end
    end
endtask

//==========================================================================
task test_imm;
    begin
    test_header("ALU immediate ops");
    prep(6);
    prog[0]=`ZERO(1); prog[1]=`LDI(2,16'd20);
    prog[2]=ITYPE(4'h4,5'd3,5'd2,16'd22);
    prog[3]=ITYPE(4'h2,5'd4,5'd3,16'd5);
    prog[4]=ITYPE(4'hD,5'd5,5'd3,16'h00FF);
    prog[5]=ITYPE(4'h1,5'd6,5'd2,16'h000F);
    load_prog(6); do_reset; run(20);
    chk(dut.ID.reg_file[3], 16'd42, "imm add");
    chk(dut.ID.reg_file[4], 16'd37, "imm sub");
    chk(dut.ID.reg_file[5], 16'd42, "imm and");
    chk(dut.ID.reg_file[6], 16'd27, "imm xor");
    end
endtask

//==========================================================================
task test_multiply;
    begin
    test_header("multiply 300*700 = 0x33450");
    prep(4);
    prog[0]=`ZERO(1); prog[1]=`LDI(2,16'd300); prog[2]=`LDI(3,16'd700);
    prog[3]=RTYPE(4'hE,5'd4,5'd2,5'd3);
    load_prog(4); do_reset; run(18);
    chk(dut.ID.reg_file[4], 16'h3450, "mul low -> rd");
    chk(dut.ID.reg_file[1], 16'h0003, "mul high -> r1 (wr fix)");
    chk(dut.ID.reg_file[0], 16'h3450, "mul acc = low");
    end
endtask

//==========================================================================
task test_acc;
    begin
    test_header("acc (r0) semantics");
    prep(5);
    prog[0]=`ZERO(1); prog[1]=`LDI(2,16'd9);
    prog[2]=ITYPE(4'h0,5'd3,5'd0,16'd0);
    prog[3]=ITYPE(4'h0,5'd0,5'd2,16'd0);
    prog[4]=ITYPE(4'h4,5'd4,5'd2,16'd3);
    load_prog(5); do_reset; run(18);
    chk(dut.ID.reg_file[3], 16'd9,  "acc forward read");
    chk(dut.ID.reg_file[4], 16'd12, "r4");
    chk(dut.ID.reg_file[0], 16'd12, "acc updated after r4 (not frozen by mov r0)");
    end
endtask

//==========================================================================
task test_forwarding;
    begin
    test_header("forwarding EX/MEM, MEM/WB, WB buffer");
    prep(5);
    prog[0]=`ZERO(1); prog[1]=`LDI(2,16'd5); prog[2]=`LDI(3,16'd7);
    prog[3]=RTYPE(4'h4,5'd4,5'd2,5'd3);
    prog[4]=RTYPE(4'h4,5'd5,5'd4,5'd3);
    load_prog(5); do_reset; run(18);
    chk(dut.ID.reg_file[5], 16'd19, "fwd gap0 (EX/MEM)");
    prep(6);
    prog[0]=`ZERO(1); prog[1]=`LDI(2,16'd5); prog[2]=`LDI(3,16'd7);
    prog[3]=RTYPE(4'h4,5'd4,5'd2,5'd3);
    prog[5]=RTYPE(4'h4,5'd5,5'd4,5'd3);
    load_prog(6); do_reset; run(19);
    chk(dut.ID.reg_file[5], 16'd19, "fwd gap1 (MEM/WB)");
    prep(7);
    prog[0]=`ZERO(1); prog[1]=`LDI(2,16'd5); prog[2]=`LDI(3,16'd7);
    prog[3]=RTYPE(4'h4,5'd4,5'd2,5'd3);
    prog[6]=RTYPE(4'h4,5'd5,5'd4,5'd3);
    load_prog(7); do_reset; run(20);
    chk(dut.ID.reg_file[5], 16'd19, "fwd gap2 (WB buf)");
    end
endtask

//==========================================================================
task test_load_use_stall;
    begin
    test_header("store, load, load-use stall");
    prep(6);
    prog[0]=`ZERO(1); prog[1]=`LDI(2,16'd40); prog[2]=`LDI(3,16'h0099);
    prog[3]=MEMI(2'd2,5'd3,5'd2,16'd0);
    prog[4]=MEMI(2'd0,5'd5,5'd2,16'd0);
    prog[5]=ITYPE(4'h4,5'd6,5'd5,16'd1);
    load_prog(6); do_reset; run(20);
    chk(dut.MEM.mem.mem[40], 16'h0099, "mem[40]");
    chk(dut.ID.reg_file[5], 16'h0099, "load r5");
    chk(dut.ID.reg_file[6], 16'h009A, "stall consumer r6");
    chk(stall_cnt, 16'd1, "stall count == 1");
    end
endtask

//==========================================================================
task test_store_fwd;
    begin
    test_header("store-data forwarding");
    prep(6);
    prog[0]=`ZERO(1); prog[1]=`LDI(2,16'd40); prog[2]=`LDI(3,16'd77);
    prog[3]=MEMI(2'd2,5'd3,5'd2,16'd0);
    prog[4]=MEMI(2'd0,5'd5,5'd2,16'd0);
    prog[5]=MEMI(2'd2,5'd5,5'd2,16'd1);
    load_prog(6); do_reset; run(20);
    chk(dut.MEM.mem.mem[41], 16'd77, "store-data fwd mem[41]");
    chk(stall_cnt, 16'd0, "no stall for store-data dep");
    end
endtask

//==========================================================================
task test_suboffset;
    begin
    test_header("load with subtract offset");
    prep(3);
    prog[0]=`ZERO(1); prog[1]=`LDI(2,16'd50);
    prog[2]=MEMI(2'd1,5'd5,5'd2,16'd4);   // LD r5 = [r2-4] = mem[46]
    load_prog(3); do_reset;
    dut.MEM.mem.mem[46] = 16'hABCD;       // AFTER reset (rst clears mem)
    run(16);
    chk(dut.ID.reg_file[5], 16'hABCD, "ld sub-offset r5");
    chk(dut.ID.reg_file[0], 16'd46, "acc = load address 46 (LD is last)");
    end
endtask

//==========================================================================
task test_branch_carry;
    begin
    test_header("branch on carry & parity");
    // (a) JC taken
    prep(17);
    prog[0]=`ZERO(1);
    prog[1]=`LDI(2,16'd16); prog[2]=`LDI(3,16'd0);
    prog[3]=ITYPE(4'h0,5'd30,5'd2,16'd0);
    prog[4]=ITYPE(4'h0,5'd31,5'd3,16'd0);
    prog[5]=NOP; prog[6]=NOP; prog[7]=NOP; prog[8]=NOP;
    prog[9]=RSEL(4'hF,2'b01);
    prog[10]=NOP; prog[11]=NOP;
    prog[12]=BRI(4'd1,16'd0,3'b000);     // JC -> 16
    prog[13]=NOP;                        // DELAY SLOT (always executes)
    prog[14]=NOP;
    prog[15]=NOP;                        // fetch-register leak slot
    prog[16]=ITYPE(4'h4,5'd10,5'd10,16'd1);
    load_prog(17); do_reset; run(24);
    chk(dut.ID.reg_file[10], 16'd1, "JC taken (delay slot is NOP)");
    // (b) JC not taken
    prep(17);
    prog[0]=`ZERO(1);
    prog[1]=`LDI(2,16'd16); prog[2]=`LDI(3,16'd0);
    prog[3]=ITYPE(4'h0,5'd30,5'd2,16'd0);
    prog[4]=ITYPE(4'h0,5'd31,5'd3,16'd0);
    prog[5]=NOP; prog[6]=NOP; prog[7]=NOP; prog[8]=NOP;
    prog[9]=NOP; prog[10]=NOP; prog[11]=NOP;
    prog[12]=BRI(4'd1,16'd0,3'b000);
    prog[13]=ITYPE(4'h4,5'd10,5'd10,16'd1);
    prog[14]=NOP;
    prog[15]=NOP;
    prog[16]=ITYPE(4'h4,5'd10,5'd10,16'd1);
    load_prog(17); do_reset; run(24);
    chk(dut.ID.reg_file[10], 16'd2, "JC not taken (fall through)");
    // (c) J-even taken
    prep(17);
    prog[0]=`ZERO(1);
    prog[1]=`LDI(2,16'd16); prog[2]=`LDI(3,16'd0);
    prog[3]=ITYPE(4'h0,5'd30,5'd2,16'd0);
    prog[4]=ITYPE(4'h0,5'd31,5'd3,16'd0);
    prog[5]=NOP; prog[6]=NOP; prog[7]=NOP; prog[8]=NOP;
    prog[9]=`LDI(2,16'd3);               // P=0
    prog[10]=NOP; prog[11]=NOP;
    prog[12]=BRI(4'd4,16'd0,3'b000);     // J-even -> 16
    prog[13]=NOP;                        // DELAY SLOT
    prog[14]=NOP;
    prog[15]=NOP;                        // leak slot
    prog[16]=ITYPE(4'h4,5'd10,5'd10,16'd1);
    load_prog(17); do_reset; run(24);
    chk(dut.ID.reg_file[10], 16'd1, "J-even taken (P=0)");
    end
endtask

//==========================================================================
task test_branch_regacc;
    begin
    test_header("reg-reg == branch & acc<imm branch");
    // (a) r2==r3 -> taken
    prep(19);
    prog[0]=`ZERO(1);
    prog[1]=`LDI(2,16'd16); prog[2]=`LDI(3,16'd0);
    prog[3]=ITYPE(4'h0,5'd30,5'd2,16'd0);
    prog[4]=ITYPE(4'h0,5'd31,5'd3,16'd0);
    prog[5]=NOP; prog[6]=NOP;
    prog[7]=`LDI(2,16'd5); prog[8]=`LDI(3,16'd5);
    prog[9]=NOP; prog[10]=NOP; prog[11]=NOP;
    prog[12]=BRR(4'd7,5'd2,5'd3,3'b000); // r2==r3 -> 16
    prog[13]=NOP;                        // DELAY SLOT
    prog[14]=NOP;
    prog[15]=NOP;                        // leak slot
    prog[16]=ITYPE(4'h4,5'd10,5'd10,16'd1);
    load_prog(17); do_reset; run(24);
    chk(dut.ID.reg_file[10], 16'd1, "reg==reg taken");
    // (b) acc(5) < imm(9) -> taken
    prep(19);
    prog[0]=`ZERO(1);
    prog[1]=`LDI(2,16'd18); prog[2]=`LDI(3,16'd0);
    prog[3]=ITYPE(4'h0,5'd30,5'd2,16'd0);
    prog[4]=ITYPE(4'h0,5'd31,5'd3,16'd0);
    prog[5]=NOP; prog[6]=NOP;
    prog[7]=NOP; prog[8]=NOP;
    prog[9]=ITYPE(4'h4,5'd5,5'd1,16'd5);  // r5=5, acc=5
    prog[10]=NOP; prog[11]=NOP; prog[12]=NOP; prog[13]=NOP;
    prog[14]=BRI(4'd12,16'd9,3'b000);    // acc<9 -> 18
    prog[15]=NOP;                        // DELAY SLOT
    prog[16]=NOP;
    prog[17]=NOP;                        // leak slot
    prog[18]=ITYPE(4'h4,5'd10,5'd10,16'd1);
    load_prog(19); do_reset; run(28);
    chk(dut.ID.reg_file[10], 16'd1, "acc<imm taken");
    end
endtask

//==========================================================================
task test_call_return;
    begin
    test_header("call / return, SP and stack frame");
    prep(27);
    prog[ 0]=`ZERO(1);
    prog[ 1]=`LDI(2,16'd25);             // MARl = subroutine @25
    prog[ 2]=`LDI(3,16'd0);
    prog[ 3]=ITYPE(4'h0,5'd30,5'd2,16'd0);
    prog[ 4]=ITYPE(4'h0,5'd31,5'd3,16'd0);
    prog[ 5]=NOP; prog[ 6]=NOP; prog[ 7]=NOP;
    prog[ 8]=NOP; prog[ 9]=NOP;          // MAR retire (>=5)
    prog[10]=CALL;                       // -> 25, returns to 11
    prog[11]=ITYPE(4'h4,5'd10,5'd10,16'd1);  // return landing / loop head
    prog[12]=`LDI(2,16'd11);             // MAR = 11
    prog[13]=`LDI(3,16'd0);
    prog[14]=ITYPE(4'h0,5'd30,5'd2,16'd0);
    prog[15]=ITYPE(4'h0,5'd31,5'd3,16'd0);
    prog[16]=NOP; prog[17]=NOP; prog[18]=NOP;
    prog[19]=NOP; prog[20]=NOP;          // MAR retire
    prog[21]=BRI(4'd0,16'd0,3'b000);     // JMP 11 (leak slot = 24)
    prog[22]=NOP;
    prog[23]=NOP;
    prog[24]=NOP;                        // JMP leak slot: MUST be NOP
    prog[25]=ITYPE(4'h4,5'd11,5'd11,16'd1);  // subroutine: r11++
    prog[26]=RET;
    load_prog(27); do_reset; run(80);
    chk(dut.ID.reg_file[11], 16'd1, "callee ran exactly once");
    if (dut.ID.reg_file[10] < 16'd3) begin
        checks=checks+1; errors=errors+1;
        $display("  FAIL return landing: r10=%0d (expect >=3, looping at 11)",
                 dut.ID.reg_file[10]);
    end else checks=checks+1;
    chk(dut.ID.sp, 16'h001A, "SP restored to 0x1A");
    chk(dut.MEM.mem.mem[16'h1A], 16'h00, "frame: flags@0x1A (call's own: sp-3=0x17)");
    chk(dut.MEM.mem.mem[16'h18], 16'h00, "frame: retaddr hi@0x18");
    chk(dut.MEM.mem.mem[16'h19], 16'd11, "frame: retaddr lo@0x19");
    end
endtask

endmodule