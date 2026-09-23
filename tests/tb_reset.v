`timescale 1ns/1ps
`default_nettype none
module tb_reset;
    reg clk = 0, reset = 1, allow_data = 0;
    always #5 clk = !clk;
    wire valid, write, instr, halted, trace_valid;
    wire [31:0] addr, wdata, pc, value, trace_pc, trace_instr;
    wire [3:0] strobe, fault, flags;
    reg [31:0] rdata;
    integer stores = 0;
    tiny_arm dut(
        .clk(clk), .reset(reset), .mem_valid(valid), .mem_write(write), .mem_instr(instr),
        .mem_addr(addr), .mem_wdata(wdata), .mem_wstrb(strobe),
        .mem_ready(valid && (instr || allow_data)), .mem_rdata(rdata), .mem_error(1'b0),
        .halted(halted), .fault(fault), .debug_pc(pc), .debug_flags(flags),
        .debug_reg(4'd0), .debug_value(value), .trace_valid(trace_valid),
        .trace_pc(trace_pc), .trace_instr(trace_instr)
    );
    always @* begin
        case (addr)
            0: rdata = 32'he3a00c01; // MOV r0, #256
            4: rdata = 32'he3a01007; // MOV r1, #7
            8: rdata = 32'he5a01004; // STR r1, [r0, #4]!
            default: rdata = 32'hef000000;
        endcase
    end
    always @(posedge clk) begin
        if (!reset && valid && write && allow_data) begin
            if (addr != 260 || wdata != 7 || strobe != 15) $fatal(1, "bad store");
            stores <= stores + 1;
        end
    end
    task check_reset;
        begin
            repeat (2) @(negedge clk);
            if (valid || halted || fault != 0 || pc != 0 || value != 0 || flags != 0)
                $fatal(1, "reset did not clear state");
            if (dut.regs[1] != 0) $fatal(1, "reset did not clear registers");
        end
    endtask
    initial begin
        check_reset();
        reset = 0;
        wait (valid && write);
        repeat (4) @(negedge clk);
        if (value != 256 || stores != 0) $fatal(1, "store committed before ready");
        reset = 1;
        check_reset();
        allow_data = 1;
        reset = 0;
        wait (halted);
        @(negedge clk);
        if (stores != 1 || value != 260 || fault != 0) $fatal(1, "restart failed");
        reset = 1;
        check_reset();
        reset = 0;
        wait (halted);
        @(negedge clk);
        if (stores != 2 || value != 260) $fatal(1, "reset from halt failed");
        $display("PASS reset cancels pending store and restarts halted core");
        $finish;
    end
    initial begin #10000; $fatal(1, "reset test timeout"); end
endmodule
`default_nettype wire
