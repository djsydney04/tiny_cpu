`timescale 1ns/1ps
`default_nettype none
module tb_datapath;
    reg [31:0] a, b, control, old_flags, expected, expected_flags;
    wire [31:0] alu_result, shifted;
    wire [3:0] flags;
    wire carry, passed;
    reg [4095:0] path;
    reg [63:0] kind;
    integer fd, scan, count = 0;
    arm_alu alu(control[3:0], a, b, old_flags[3:0], control[4], alu_result, flags);
    arm_shifter shift(control[12], control[11:0], a, old_flags[1], shifted, carry);
    arm_condition cond(control[3:0], old_flags[3:0], passed);
    initial begin
        if (!$value$plusargs("vectors=%s", path) || !$value$plusargs("kind=%s", kind))
            $fatal(1, "missing vector arguments");
        fd = $fopen(path, "r");
        if (!fd) $fatal(1, "cannot open vectors");
        while (!$feof(fd)) begin
            scan = $fscanf(fd, "%h %h %h %h %h %h\n", a, b, control, old_flags, expected, expected_flags);
            if (scan != 6) $fatal(1, "bad vector %0d", count);
            #1;
            if (kind == "alu" && (alu_result !== expected || flags !== expected_flags[3:0]))
                $fatal(1, "ALU vector %0d: got %08x/%x expected %08x/%x", count, alu_result, flags, expected, expected_flags);
            if (kind == "shift" && (shifted !== expected || carry !== expected_flags[0]))
                $fatal(1, "shift vector %0d: got %08x/%b expected %08x/%b", count, shifted, carry, expected, expected_flags[0]);
            if (kind == "cond" && passed !== expected[0]) $fatal(1, "condition vector %0d", count);
            count = count + 1;
        end
        if (count == 0) $fatal(1, "no vectors");
        $display("PASS %0d %0s vectors", count, kind);
        $finish;
    end
endmodule
`default_nettype wire
