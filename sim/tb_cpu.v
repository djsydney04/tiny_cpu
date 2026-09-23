`timescale 1ns/1ps
`default_nettype none
module tb_cpu;
    reg clk = 0, reset = 1;
    always #5 clk = !clk;
    wire valid, write, instr, ready, error, halted;
    wire [31:0] addr, wdata, rdata, pc, debug_value;
    wire [3:0] wstrb, fault, flags;
    wire trace_valid;
    wire [31:0] trace_pc, trace_instr;
    reg [31:0] ram [0:16383];
    integer cycles = 0, retired = 0, delay_count = 0, wait_cycles = 0;
    integer max_cycles = 100000, dump_start = 256, dump_words = 16;
    reg [31:0] error_addr = 32'hffffffff;
    integer i, lane, fd, scan, word_count;
    reg [31:0] word_value;
    reg [4095:0] image_path, wave_path;
    reg verbose;
    reg stalled = 0;
    reg [69:0] held_request;
    wire [69:0] request = {instr, write, addr, wdata, wstrb};

    tiny_arm dut(
        .clk(clk), .reset(reset), .mem_valid(valid), .mem_write(write),
        .mem_instr(instr), .mem_addr(addr), .mem_wdata(wdata), .mem_wstrb(wstrb),
        .mem_ready(ready), .mem_rdata(rdata), .mem_error(error),
        .halted(halted), .fault(fault), .debug_pc(pc), .debug_flags(flags),
        .debug_reg(4'd0), .debug_value(debug_value), .trace_valid(trace_valid),
        .trace_pc(trace_pc), .trace_instr(trace_instr)
    );
    assign ready = valid && delay_count >= wait_cycles;
    assign error = addr >= 65536 || addr == error_addr;
    assign rdata = addr < 65536 ? ram[addr[15:2]] : 32'b0;

    initial begin
        for (i = 0; i < 16384; i = i + 1) ram[i] = 0;
        if (!$value$plusargs("image=%s", image_path)) $fatal(1, "use +image=program.hex");
        scan = $value$plusargs("wait=%d", wait_cycles);
        scan = $value$plusargs("max_cycles=%d", max_cycles);
        scan = $value$plusargs("dump_start=%d", dump_start);
        scan = $value$plusargs("dump_words=%d", dump_words);
        scan = $value$plusargs("error_addr=%h", error_addr);
        if (wait_cycles < 0 || max_cycles <= 0 || dump_start < 0 || dump_start % 4 != 0 ||
            dump_words < 0 || dump_start / 4 + dump_words > 16384)
            $fatal(1, "invalid simulation option");
        verbose = $test$plusargs("trace");
        if ($value$plusargs("vcd=%s", wave_path)) begin
            $dumpfile(wave_path);
            $dumpvars(0, tb_cpu);
        end
        fd = $fopen(image_path, "r");
        if (!fd) $fatal(1, "cannot open image");
        word_count = 0;
        while (!$feof(fd)) begin
            scan = $fscanf(fd, "%h\n", word_value);
            if (scan == 1) begin
                if (word_count >= 16384) $fatal(1, "image exceeds 64 KiB");
                ram[word_count] = word_value;
                word_count = word_count + 1;
            end else if (scan == 0) $fatal(1, "malformed hex image");
        end
        $fclose(fd);
        if (word_count == 0) $fatal(1, "empty image");
        repeat (3) @(negedge clk);
        reset = 0;
    end

    always @(posedge clk) begin
        if (reset) begin delay_count <= 0; stalled <= 0; end
        else begin
            cycles <= cycles + 1;
            if (cycles >= max_cycles) $fatal(1, "execution timeout at pc=%08x", pc);
            if (stalled && (!valid || request !== held_request))
                $fatal(1, "memory request changed while stalled");
            stalled <= valid && !ready;
            held_request <= request;
            if (valid && !ready) delay_count <= delay_count + 1;
            else delay_count <= 0;
            if (valid && addr[1:0] != 0) $fatal(1, "unaligned bus request");
            if (valid && ready && write && !error)
                for (lane = 0; lane < 4; lane = lane + 1)
                    if (wstrb[lane]) ram[addr[15:2]][lane*8 +: 8] <= wdata[lane*8 +: 8];
        end
    end

    always @(negedge clk) begin
        if (!reset) begin
            if (trace_valid) begin
                retired = retired + 1;
                if (verbose) begin
                    $write("TRACE %08x %08x %01x", trace_pc, trace_instr, flags);
                    for (i = 0; i < 15; i = i + 1) $write(" %08x", dut.regs[i]);
                    $write("\n");
                end
            end
            if (halted) begin
                $display("RESULT fault=%0d pc=%08x cycles=%0d retired=%0d", fault, pc, cycles, retired);
                $write("STATE %08x %01x", pc, flags);
                for (i = 0; i < 15; i = i + 1) $write(" %08x", dut.regs[i]);
                $write("\n");
                for (i = 0; i < dump_words; i = i + 1)
                    $display("MEM %08x %08x", dump_start + i*4, ram[dump_start/4 + i]);
                repeat (3) begin
                    @(negedge clk);
                    if (valid || trace_valid || !halted) $fatal(1, "halt is not stable");
                end
                if (fault != 0) $fatal(1, "CPU fault %0d", fault);
                $finish;
            end
        end
    end
endmodule
`default_nettype wire
