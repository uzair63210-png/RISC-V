`timescale 1ns/1ps
//============================================================================
//  tb_cpu.v  -  self-checking testbench for the 16-bit 5-stage CPU (README)
//
//  Every test does the same four steps:
//     1. hold reset, clear instruction memory to NOP
//     2. WRITE THE PROGRAM into instruction memory  (+ data into data memory)
//     3. release reset and let the CPU run
//     4. check registers / data memory / SP / stall count
//
//  Conventions used by the test programs (all from the README):
//     r0  accumulator          r1  multiply high half
//     r2  ZERO (never written) r30/r31  MAR (jump target = {r31,r30})
//     LDI rd,imm  =  xor rd, r2, #imm
//     delay slot at branch+1 always executes -> program puts markers there
//     MAR must retire (>= 5 instr) before the jump   -> 6 NOPs
//     flags: one gap instruction between flag producer and branch
//
//  Run (Icarus):
//     iverilog -o tb tb_cpu.v cpu.v IF.v IF_stage.v ID.v ex_state.v \
//              ALU.v adder_16bit.v forwarding_unit.v MEM_state.v WB_state.v
//     vvp tb                      (add +NO_MONITOR=1 to silence the trace)
//                                 (add +VCD to dump tb_cpu.vcd)
//============================================================================
module tb_cpu;
 
  reg clk = 1'b0;
  reg rst = 1'b1;
  cpu dut (.clk(clk), .rst(rst));
  always #5 clk = ~clk;
 
  //--------------------------------------------------------------------------
  // constants and instruction encoders
  //--------------------------------------------------------------------------
  localparam [31:0] NOP  = 32'h3C000000;                       // flagop, holds flags + acc
  localparam [31:0] RET  = 32'h10000003;
  localparam [31:0] SETC = {2'b00, 4'hF, 5'd0, 5'd0, 5'd0, 11'h200};   // flagop sel=01: C=1
 
  localparam [3:0] C_MOV = 4'h0, C_XOR = 4'h1, C_SUB = 4'h2, C_SBB = 4'h3,
                   C_ADD = 4'h4, C_ADC = 4'h5, C_SHL = 4'h6, C_SHR = 4'h7,
                   C_RL  = 4'h8, C_RR  = 4'h9, C_CMP = 4'hA, C_OR  = 4'hB,
                   C_NOT = 4'hC, C_AND = 4'hD, C_MUL = 4'hE, C_FLG = 4'hF;
 
  localparam [1:0] LD_ADD = 2'b00, LD_SUB = 2'b01, ST_ADD = 2'b10, ST_SUB = 2'b11;
 
  // R-type : [31:30]=00 con rd rs1 rs2 000
  function [31:0] RT;
    input [3:0] con; input [4:0] rd, rs1, rs2;
    RT = {2'b00, con, rd, rs1, rs2, 11'b0};
  endfunction
 
  // I-type : [31:30]=01 con rd rs1 imm16
  function [31:0] IT;
    input [3:0] con; input [4:0] rd, rs1; input [15:0] imm;
    IT = {2'b01, con, rd, rs1, imm};
  endfunction
 
  // load constant: rd = r2 ^ imm = imm
  function [31:0] LDI;
    input [4:0] rd; input [15:0] imm;
    LDI = IT(C_XOR, rd, 5'd2, imm);
  endfunction
 
  // load / store : [31:30]=10 [29:28]=00 lsu rd base off16
  function [31:0] LS;
    input [1:0] lsu; input [4:0] rd, base; input [15:0] off;
    LS = {2'b10, 2'b00, lsu, rd, base, off};
  endfunction
 
  // branch, register compare : [31:30]=11 cond rA rB ... low3
  function [31:0] BR;
    input [3:0] cond; input [4:0] ra, rb; input [2:0] low;
    BR = {2'b11, cond, ra, rb, 13'b0, low};
  endfunction
 
  // branch, immediate compare : imm lives in [18:3]
  function [31:0] BRI;
    input [3:0] cond; input [4:0] ra; input [15:0] imm; input [2:0] low;
    BRI = {2'b11, cond, ra, 2'b00, imm, low};
  endfunction
 
  //--------------------------------------------------------------------------
  // back-door access into the DUT
  //--------------------------------------------------------------------------
  function [15:0] RG;  input [4:0] n; RG = dut.ID.reg_file[n];       endfunction
  function [15:0] MM;  input [8:0] a; MM = dut.MEM.mem.mem[a];       endfunction
  function [15:0] SPV; input dummy;   SPV = dut.ID.sp;               endfunction
 
  //--------------------------------------------------------------------------
  // program / data loading
  //--------------------------------------------------------------------------
  integer pa;                                   // next instruction address to write
 
  task emit;
    input [31:0] w;
    begin
      dut.IF.IFetch.instruction_memory[pa] = w;
      pa = pa + 1;
    end
  endtask
 
  task nops;
    input [31:0] n;
    integer k;
    begin
      for (k = 0; k < n; k = k + 1) emit(NOP);
    end
  endtask
 
  task patch;                                   // overwrite an already-written word
    input [31:0] a; input [31:0] w;
    begin
      dut.IF.IFetch.instruction_memory[a] = w;
    end
  endtask
 
  task dset;                                    // write one word of DATA memory
    input [8:0] a; input [15:0] v;
    begin
      dut.MEM.mem.mem[a] = v;
    end
  endtask
 
  //--------------------------------------------------------------------------
  // test infrastructure
  //--------------------------------------------------------------------------
  integer checks = 0, errors = 0, tnum = 0, tfail = 0, err0 = 0;
  integer stall_cnt = 0;
 
  // reset (clears regs + data memory), then fill instruction memory with NOPs
  task prog_start;
    integer i;
    begin
      rst = 1'b1;
      repeat (3) @(negedge clk);
      for (i = 0; i < 1024; i = i + 1) dut.IF.IFetch.instruction_memory[i] = NOP;
      pa = 0;
    end
  endtask
 
  // data memory is cleared by reset, so data is written right before reset is
  // released (same time step, no clock edge in between)
  task launch;
    begin
      stall_cnt = 0;
      rst = 1'b0;
    end
  endtask
 
  task run;
    input [31:0] n;
    begin
      repeat (n) @(posedge clk);
      @(negedge clk);
    end
  endtask
 
  task test_begin;
    input [8*64-1:0] nm;
    begin
      tnum = tnum + 1;
      err0 = errors;
      $display("\n=== TEST %0d: %0s ===", tnum, nm);
    end
  endtask
 
  task test_end;
    begin
      if (errors == err0) $display("  -> TEST %0d PASS", tnum);
      else begin
        tfail = tfail + 1;
        $display("  -> TEST %0d FAIL", tnum);
      end
    end
  endtask
 
  task check16;
    input [8*40-1:0] nm; input [15:0] got, exp;
    begin
      checks = checks + 1;
      if (got === exp) $display("  ok   %0s = %04h", nm, got);
      else begin
        errors = errors + 1;
        $display("  FAIL %0s : got %04h, expected %04h", nm, got, exp);
      end
    end
  endtask
 
  // per-cycle trace
  reg trace_on;
  integer cyc = 0;
  initial trace_on = !$test$plusargs("NO_MONITOR");
  always @(posedge clk) begin
    if (rst) cyc <= 0;
    else begin
      cyc <= cyc + 1;
      if (trace_on)
        $display("  [T%0d c%0d] ID=%h acc=%04h flags=%b stall=%b brch=%b sp=%04h",
                 tnum, cyc, dut.instruction, dut.ID.reg_file[0], dut.flags,
                 dut.stall, dut.brch, dut.ID.sp);
    end
  end
 
  always @(posedge clk) if (!rst && dut.stall === 1'b1) stall_cnt = stall_cnt + 1;
 
  //--------------------------------------------------------------------------
  // ALU test program (shared by the register and the immediate test)
  //   r3 = VA, r4 = VB ; results in r10..r25, mul high half in r1
  //--------------------------------------------------------------------------
  localparam [15:0] VA = 16'h00F0, VB = 16'h0035;
  localparam [31:0] P0 = VA * VB;                      // 240*53 = 12720
 
  function [31:0] OP;
    input use_imm; input [3:0] con; input [4:0] rd;
    OP = use_imm ? IT(con, rd, 5'd3, VB) : RT(con, rd, 5'd3, 5'd4);
  endfunction
 
  task alu_program;
    input u;
    begin
      emit(LDI(5'd3, VA));
      emit(LDI(5'd4, VB));
      nops(6);
      emit(OP(u, C_MOV, 5'd10));
      emit(OP(u, C_XOR, 5'd11));
      emit(OP(u, C_SUB, 5'd12));
      emit(SETC); emit(OP(u, C_SBB, 5'd13));           // C = 1
      emit(OP(u, C_ADD, 5'd14));
      emit(SETC); emit(OP(u, C_ADC, 5'd15));           // C = 1
      emit(OP(u, C_SHL, 5'd16));
      emit(OP(u, C_SHR, 5'd17));
      emit(SETC); emit(OP(u, C_RL,  5'd18));           // C = 1
      emit(SETC); emit(OP(u, C_RR,  5'd19));           // C = 1
      emit(OP(u, C_CMP, 5'd20));
      emit(OP(u, C_OR,  5'd21));
      emit(OP(u, C_NOT, 5'd22));
      emit(OP(u, C_AND, 5'd23));
      emit(OP(u, C_MUL, 5'd24));
      emit(OP(u, C_FLG, 5'd25));
      nops(8);
    end
  endtask
 
  task check_alu;
    begin
      check16("mov  rd = rs1",            RG(10), VA);
      check16("xor",                      RG(11), VA ^ VB);
      check16("sub  rs1 - rs2",           RG(12), VA - VB);
      check16("sbb  rs1 - rs2 - C (C=1)", RG(13), VA - VB - 16'd1);
      check16("add",                      RG(14), VA + VB);
      check16("adc  rs1 + rs2 + C (C=1)", RG(15), VA + VB + 16'd1);
      check16("shl",                      RG(16), VA << 1);
      check16("shr",                      RG(17), VA >> 1);
      check16("rl   through C (C=1)",     RG(18), {VA[14:0], 1'b1});
      check16("rr   through C (C=1)",     RG(19), {1'b1, VA[15:1]});
      check16("cmp  rd = rs1",            RG(20), VA);
      check16("or",                       RG(21), VA | VB);
      check16("not",                      RG(22), ~VA);
      check16("and",                      RG(23), VA & VB);
      check16("mul  low half -> rd",      RG(24), P0[15:0]);
      check16("mul  high half -> r1",     RG(1),  P0[31:16]);
      check16("flagop rd = rs1",          RG(25), VA);
    end
  endtask
 
  //--------------------------------------------------------------------------
  // branch test program
  //
  //   r3=5  r4=9  r5=9           (compare operands)
  //   LDI r30,<target>           (MAR, patched once the target address is known)
  //   6 NOPs                     (MAR retires)
  //   <setup> <gap NOPs>         (flag / accumulator set-up)
  //   BRANCH
  //   B+1  LDI r11,1             delay slot            -> always executes
  //   B+2  LDI r12,1             flushed when taken
  //   B+3  LDI r13,1             "branch+3" leak check -> must be flushed when taken
  //   B+4  LDI r15,1             never fetched when taken
  //   TGT  LDI r14,1             target (also the fall-through)
  //
  //   taken     : r11 r12 r13 r14 r15 = 1 0 0 1 0
  //   not taken : r11 r12 r13 r14 r15 = 1 1 1 1 1
  //--------------------------------------------------------------------------
  integer mar_at, tgt;
 
  task br_core;
    input [8*40-1:0] nm;
    input [31:0] setup;
    input [31:0] gap;
    input [31:0] bword;
    input        taken;
    reg [15:0] got, exp;
    begin
      prog_start;
      emit(LDI(5'd3, 16'd5));
      emit(LDI(5'd4, 16'd9));
      emit(LDI(5'd5, 16'd9));
      mar_at = pa; emit(NOP);                        // placeholder for LDI r30,target
      nops(6);
      emit(setup);
      nops(gap);
      emit(bword);
      emit(LDI(5'd11, 16'd1));
      emit(LDI(5'd12, 16'd1));
      emit(LDI(5'd13, 16'd1));
      emit(LDI(5'd15, 16'd1));
      tgt = pa;
      emit(LDI(5'd14, 16'd1));
      nops(10);
      patch(mar_at, LDI(5'd30, tgt[15:0]));
      launch;
      run(pa + 40);
      got = {11'b0, (RG(11) == 16'd1), (RG(12) == 16'd1), (RG(13) == 16'd1),
                    (RG(14) == 16'd1), (RG(15) == 16'd1)};
      exp = taken ? 16'h0012 : 16'h001F;
      if (got !== exp)
        $display("       markers r11..r15 = %0d %0d %0d %0d %0d (delay slot, B+2, B+3, target, B+4)",
                 RG(11), RG(12), RG(13), RG(14), RG(15));
      check16(nm, got, exp);
    end
  endtask
 
  //--------------------------------------------------------------------------
  // call / return programs
  //--------------------------------------------------------------------------
  integer call_pc, func_at;
  localparam FUNC_ADDR = 300;                       // far away from the main code
 
  //--------------------------------------------------------------------------
  // main sequence
  //--------------------------------------------------------------------------
  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_cpu.vcd");
      $dumpvars(0, tb_cpu);
    end
 
    //------------------------------------------------------------------ 1
    test_begin("ALU register ops (all 16)");
    prog_start; alu_program(1'b0); launch; run(pa + 30);
    check_alu;
    test_end;
 
    //------------------------------------------------------------------ 2
    test_begin("ALU immediate ops (all 16)");
    prog_start; alu_program(1'b1); launch; run(pa + 30);
    check_alu;
    test_end;
 
    //------------------------------------------------------------------ 3
    test_begin("Accumulator (r0) semantics");
    prog_start;
    emit(LDI(5'd3, 16'd100));
    nops(5);
    emit(IT(C_ADD, 5'd4, 5'd3, 16'd5));             // r4 = 105, acc = 105
    emit(IT(C_ADD, 5'd5, 5'd0, 16'd7));             // r0 = live acc (105) -> r5 = 112
    emit(RT(C_ADD, 5'd6, 5'd0, 5'd0));              // acc + acc  (112+112) -> r6 = 224
    nops(8);
    launch; run(pa + 30);
    check16("r4 = r3 + 5",                RG(4), 16'd105);
    check16("r5 = acc + 7 (prev result)", RG(5), 16'd112);
    check16("r6 = acc + acc",             RG(6), 16'd224);
    check16("acc holds last ALU result",  RG(0), 16'd224);
    test_end;
 
    //------------------------------------------------------------------ 4
    test_begin("Forwarding: distance 1, 2, 3 and reg-file (4)");
    prog_start;
    emit(LDI(5'd3, 16'd10));
    nops(6);
    // distance 1 : EX/MEM -> EX
    emit(IT(C_ADD, 5'd10, 5'd3, 16'd1));
    emit(IT(C_ADD, 5'd11, 5'd10, 16'd100));
    nops(6);
    // distance 2 : MEM/WB -> EX
    emit(IT(C_ADD, 5'd12, 5'd3, 16'd2));
    emit(NOP);
    emit(IT(C_ADD, 5'd14, 5'd12, 16'd100));
    nops(6);
    // distance 3 : WB buffer -> EX
    emit(IT(C_ADD, 5'd15, 5'd3, 16'd3));
    emit(NOP); emit(NOP);
    emit(IT(C_ADD, 5'd18, 5'd15, 16'd100));
    nops(6);
    // distance 4 : register file (write-through bypass in ID)
    emit(IT(C_ADD, 5'd19, 5'd3, 16'd4));
    emit(NOP); emit(NOP); emit(NOP);
    emit(IT(C_ADD, 5'd20, 5'd19, 16'd100));
    nops(6);
    // back-to-back chain
    emit(IT(C_ADD, 5'd21, 5'd3,  16'd1));
    emit(IT(C_ADD, 5'd22, 5'd21, 16'd1));
    emit(IT(C_ADD, 5'd23, 5'd22, 16'd1));
    emit(IT(C_ADD, 5'd24, 5'd23, 16'd1));
    nops(6);
    // both operands forwarded (rs1 at distance 2, rs2 at distance 1)
    emit(IT(C_ADD, 5'd25, 5'd3, 16'd100));
    emit(IT(C_ADD, 5'd26, 5'd3, 16'd200));
    emit(RT(C_ADD, 5'd27, 5'd25, 5'd26));
    nops(8);
    launch; run(pa + 30);
    check16("dist1  r11 = r10 + 100",  RG(11), 16'd111);
    check16("dist2  r14 = r12 + 100",  RG(14), 16'd112);
    check16("dist3  r18 = r15 + 100",  RG(18), 16'd113);
    check16("dist4  r20 = r19 + 100",  RG(20), 16'd114);
    check16("chain  r21",              RG(21), 16'd11);
    check16("chain  r22",              RG(22), 16'd12);
    check16("chain  r23",              RG(23), 16'd13);
    check16("chain  r24",              RG(24), 16'd14);
    check16("rs1 dist2 + rs2 dist1",   RG(27), 16'd320);
    test_end;
 
    //------------------------------------------------------------------ 5
    test_begin("Load/store, sub-offset, store-data forwarding");
    prog_start;
    dset(9'd100, 16'h1111);
    dset(9'd101, 16'h2222);
    dset(9'd110, 16'h3333);
    emit(LDI(5'd3, 16'd100));
    emit(LDI(5'd6, 16'd110));
    nops(6);
    emit(LS(LD_ADD, 5'd4, 5'd3, 16'd0));            // r4 = mem[100]
    emit(LS(LD_ADD, 5'd5, 5'd3, 16'd1));            // r5 = mem[101]
    emit(LS(LD_SUB, 5'd7, 5'd6, 16'd10));           // r7 = mem[110-10] = mem[100]
    emit(LS(LD_SUB, 5'd8, 5'd6, 16'd0));            // r8 = mem[110]
    nops(6);
    emit(LS(ST_ADD, 5'd4, 5'd3, 16'd20));           // mem[120] = r4
    emit(LS(ST_SUB, 5'd5, 5'd6, 16'd5));            // mem[105] = r5
    nops(6);
    // store data produced 1, 2, 3 instructions before the store
    emit(LDI(5'd9, 16'hBEEF));
    emit(LS(ST_ADD, 5'd9, 5'd3, 16'd30));           // mem[130]
    nops(6);
    emit(LDI(5'd12, 16'hCAFE));
    emit(NOP);
    emit(LS(ST_ADD, 5'd12, 5'd3, 16'd31));          // mem[131]
    nops(6);
    emit(LDI(5'd13, 16'hF00D));
    emit(NOP); emit(NOP);
    emit(LS(ST_ADD, 5'd13, 5'd3, 16'd32));          // mem[132]
    nops(6);
    // load followed immediately by the store of the loaded register
    emit(LS(LD_ADD, 5'd14, 5'd3, 16'd0));
    emit(LS(ST_ADD, 5'd14, 5'd3, 16'd40));          // mem[140] = mem[100]
    nops(8);
    launch; run(pa + 30);
    check16("ld  r4 = mem[100+0]",       RG(4), 16'h1111);
    check16("ld  r5 = mem[100+1]",       RG(5), 16'h2222);
    check16("ld  r7 = mem[110-10]",      RG(7), 16'h1111);
    check16("ld  r8 = mem[110-0]",       RG(8), 16'h3333);
    check16("st  mem[100+20] = r4",      MM(120), 16'h1111);
    check16("st  mem[110-5]  = r5",      MM(105), 16'h2222);
    check16("st fwd dist1  mem[130]",    MM(130), 16'hBEEF);
    check16("st fwd dist2  mem[131]",    MM(131), 16'hCAFE);
    check16("st fwd dist3  mem[132]",    MM(132), 16'hF00D);
    check16("ld -> st back to back",     MM(140), 16'h1111);
    test_end;
 
    //------------------------------------------------------------------ 6
    test_begin("Load-use stall (exactly 1 cycle)");
    prog_start;
    dset(9'd101, 16'h2222);
    emit(LDI(5'd3, 16'd100));
    nops(6);
    emit(LS(LD_ADD, 5'd15, 5'd3, 16'd1));           // r15 = mem[101]
    emit(IT(C_ADD, 5'd16, 5'd15, 16'd1));           // uses r15 right away -> stall
    nops(8);
    launch; run(pa + 30);
    check16("r16 = loaded value + 1",    RG(16), 16'h2223);
    check16("stall cycles",              stall_cnt[15:0], 16'd1);
    test_end;
 
    //------------------------------------------------------------------ 7
    test_begin("Multiply high/low + r1");
    prog_start;
    emit(LDI(5'd3, 16'h1234));
    emit(LDI(5'd4, 16'h0567));
    nops(6);
    emit(RT(C_MUL, 5'd10, 5'd3, 5'd4));             // 0x1234 * 0x0567
    nops(4);
    emit(RT(C_ADD, 5'd26, 5'd1, 5'd2));             // r26 = r1 (+ 0) after 4 NOPs
    nops(6);
    emit(IT(C_MUL, 5'd12, 5'd3, 16'h0100));         // immediate multiply
    nops(8);
    launch; run(pa + 30);
    check16("mul  low  -> r10",          RG(10), (16'h1234 * 16'h0567) & 16'hFFFF);
    check16("mul  high read back via r26", RG(26), ((32'h1234 * 32'h0567) >> 16) & 16'hFFFF);
    check16("muli low  -> r12",          RG(12), 16'h3400);
    check16("muli high -> r1",           RG(1),  16'h0012);
    test_end;
 
    //------------------------------------------------------------------ 8
    test_begin("Flag branches (carry/sign/parity) + delay slot + flush");
    br_core("JMP always",                 NOP,                      0, BR(4'd0, 5'd0, 5'd0, 3'b000), 1'b1);
    br_core("JC  taken   (set carry)",    SETC,                     1, BR(4'd1, 5'd0, 5'd0, 3'b000), 1'b1);
    br_core("JC  not     (C=0)",          RT(C_XOR, 5'd10, 5'd2, 5'd2), 1, BR(4'd1, 5'd0, 5'd0, 3'b000), 1'b0);
    br_core("JN  taken   (sub 5-9, S=1)", RT(C_SUB, 5'd10, 5'd3, 5'd4), 1, BR(4'd2, 5'd0, 5'd0, 3'b000), 1'b1);
    br_core("JN  not     (sub 9-5, S=0)", RT(C_SUB, 5'd10, 5'd4, 5'd3), 1, BR(4'd2, 5'd0, 5'd0, 3'b000), 1'b0);
    br_core("JP  taken   (sub 9-5, S=0)", RT(C_SUB, 5'd10, 5'd4, 5'd3), 1, BR(4'd3, 5'd0, 5'd0, 3'b000), 1'b1);
    br_core("JP  not     (sub 5-9, S=1)", RT(C_SUB, 5'd10, 5'd3, 5'd4), 1, BR(4'd3, 5'd0, 5'd0, 3'b000), 1'b0);
    br_core("JEVEN taken (0x0003, P=0)",  LDI(5'd10, 16'h0003),     1, BR(4'd4, 5'd0, 5'd0, 3'b000), 1'b1);
    br_core("JEVEN not   (0x0001, P=1)",  LDI(5'd10, 16'h0001),     1, BR(4'd4, 5'd0, 5'd0, 3'b000), 1'b0);
    br_core("JODD  taken (0x0001, P=1)",  LDI(5'd10, 16'h0001),     1, BR(4'd5, 5'd0, 5'd0, 3'b000), 1'b1);
    br_core("JODD  not   (0x0003, P=0)",  LDI(5'd10, 16'h0003),     1, BR(4'd5, 5'd0, 5'd0, 3'b000), 1'b0);
    test_end;
 
    //------------------------------------------------------------------ 9
    test_begin("Register / immediate compare branches");
    br_core("cond6  r4 > r3   taken",     NOP, 0, BR (4'd6,  5'd4, 5'd3, 3'b000), 1'b1);
    br_core("cond6  r3 > r4   not",       NOP, 0, BR (4'd6,  5'd3, 5'd4, 3'b000), 1'b0);
    br_core("cond7  r4 == r5  taken",     NOP, 0, BR (4'd7,  5'd4, 5'd5, 3'b000), 1'b1);
    br_core("cond7  r3 == r4  not",       NOP, 0, BR (4'd7,  5'd3, 5'd4, 3'b000), 1'b0);
    br_core("cond8  r3 < r4   taken",     NOP, 0, BR (4'd8,  5'd3, 5'd4, 3'b000), 1'b1);
    br_core("cond8  r4 < r3   not",       NOP, 0, BR (4'd8,  5'd4, 5'd3, 3'b000), 1'b0);
    br_core("cond11 r3 == 5   taken",     NOP, 0, BRI(4'd11, 5'd3, 16'd5, 3'b000), 1'b1);
    br_core("cond11 r3 == 6   not",       NOP, 0, BRI(4'd11, 5'd3, 16'd6, 3'b000), 1'b0);
    test_end;
 
    //------------------------------------------------------------------ 10
    test_begin("Accumulator branches (cond 12-15)");
    br_core("cond12 acc 50 < 100  taken", LDI(5'd10, 16'd50), 4, BRI(4'd12, 5'd0, 16'd100, 3'b000), 1'b1);
    br_core("cond12 acc 50 < 10   not",   LDI(5'd10, 16'd50), 4, BRI(4'd12, 5'd0, 16'd10,  3'b000), 1'b0);
    br_core("cond13 acc 50 > 10   taken", LDI(5'd10, 16'd50), 4, BRI(4'd13, 5'd0, 16'd10,  3'b000), 1'b1);
    br_core("cond13 acc 50 > 100  not",   LDI(5'd10, 16'd50), 4, BRI(4'd13, 5'd0, 16'd100, 3'b000), 1'b0);
    br_core("cond14 acc 50 == 50  taken", LDI(5'd10, 16'd50), 4, BRI(4'd14, 5'd0, 16'd50,  3'b000), 1'b1);
    br_core("cond14 acc 50 == 51  not",   LDI(5'd10, 16'd50), 4, BRI(4'd14, 5'd0, 16'd51,  3'b000), 1'b0);
    br_core("cond15 acc 50 > 10, +ve taken", LDI(5'd10, 16'd50), 4, BRI(4'd15, 5'd0, 16'd10, 3'b000), 1'b1);
    br_core("cond15 acc 5 > 10    not",   LDI(5'd10, 16'd5),  4, BRI(4'd15, 5'd0, 16'd10,  3'b000), 1'b0);
    br_core("cond15 acc 0x8005 (bit15) not", LDI(5'd10, 16'h8005), 4, BRI(4'd15, 5'd0, 16'd10, 3'b000), 1'b0);
    test_end;
 
    //------------------------------------------------------------------ 11
    // CALL pushes the frame, callee runs, RET pops it.  The call's delay slot
    // is also the return address, so it executes twice.
    test_begin("Call / return + stack frame");
    prog_start;
    mar_at = pa; emit(NOP);                          // LDI r30,FUNC (patched below)
    nops(6);
    emit(LDI(5'd9, 16'h0007));                       // flags: P=1
    emit(SETC);                                      // flags: C=1  -> 0b000011
    emit(NOP);
    call_pc = pa;
    emit(BR(4'd0, 5'd0, 5'd0, 3'b101));             // CALL
    emit(IT(C_ADD, 5'd19, 5'd19, 16'd1));           // call+1 : delay slot / return point (x2)
    emit(IT(C_ADD, 5'd20, 5'd20, 16'd1));           // call+2 : flushed on the way out (x1)
    emit(IT(C_ADD, 5'd21, 5'd21, 16'd1));           // call+3 : "branch+3" leak check (x1)
    emit(LDI(5'd22, 16'hABCD));                      // call+4 : after return only
    nops(8);
    pa = FUNC_ADDR; func_at = pa;
    emit(IT(C_ADD, 5'd23, 5'd23, 16'd1));           // callee body (x1)
    emit(LDI(5'd24, 16'h2222));                      // clobbers the flags
    nops(6);
    emit(RET);
    nops(4);                                         // return redirect lands 3 slots later
    patch(mar_at, LDI(5'd30, func_at[15:0]));
    launch; run(130);
    check16("r19  delay slot ran twice",     RG(19), 16'd2);
    check16("r20  call+2 ran once",          RG(20), 16'd1);
    check16("r21  call+3 ran once (no leak)", RG(21), 16'd1);
    check16("r22  code after return ran",    RG(22), 16'hABCD);
    check16("r23  callee ran once",          RG(23), 16'd1);
    check16("r24  callee body completed",    RG(24), 16'h2222);
    check16("sp   back to 0x001A",           SPV(1'b0), 16'h001A);
    check16("frame mem[S-3] = caller flags", MM(9'd23), 16'h0003);
    check16("frame mem[S-2] = ret addr hi",  MM(9'd24), 16'h0000);
    check16("frame mem[S-1] = ret addr lo",  MM(9'd25), call_pc + 1);
    test_end;
 
    //------------------------------------------------------------------ 12
    // flags are restored from the stack: the callee clobbers C, and the
    // adc after the return reads C (= 0 + 0 + C)
    test_begin("Return restores the caller's flags");
    prog_start;
    mar_at = pa; emit(NOP);
    nops(6);
    emit(LDI(5'd9, 16'h0007));
    emit(SETC);                                      // C = 1
    emit(NOP);
    emit(BR(4'd0, 5'd0, 5'd0, 3'b101));             // CALL
    emit(NOP);                                       // call+1 (runs twice, flag-neutral)
    emit(RT(C_ADC, 5'd25, 5'd2, 5'd2));             // call+2 : r25 = C after return
    nops(8);
    pa = FUNC_ADDR; func_at = pa;
    emit(LDI(5'd24, 16'h2222));                      // xor -> C = 0
    nops(6);
    emit(RET);
    nops(4);
    patch(mar_at, LDI(5'd30, func_at[15:0]));
    launch; run(130);
    check16("r24  callee body completed",    RG(24), 16'h2222);
    check16("r25  C restored (adc 0+0+C)",   RG(25), 16'd1);
    check16("sp   back to 0x001A",           SPV(1'b0), 16'h001A);
    test_end;
 
    //------------------------------------------------------------------ summary
    $display("\n------------------------------------------------------------");
    $display("TOTAL: %0d checks, %0d errors", checks, errors);
    if (errors == 0) $display(">>> ALL TESTS PASSED <<<");
    else             $display(">>> %0d TEST(S) FAILED <<<", tfail);
    $finish;
  end
 
  // safety net
  initial begin
    #20000000;
    $display("TIMEOUT");
    $finish;
  end
 
endmodule