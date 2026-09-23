`timescale 1ns/1ps
`default_nettype none
// Educational A32 subset. See docs/architecture.md for the exact contract.
// All state changes and bus transfers occur on a rising clock edge.
module tiny_arm #(
    parameter [31:0] RESET_VECTOR = 32'h00000000
) (
    input wire clk,
    input wire reset,
    output wire mem_valid,
    output wire mem_write,
    output wire mem_instr,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [3:0] mem_wstrb,
    input wire mem_ready,
    input wire [31:0] mem_rdata,
    input wire mem_error,
    output wire halted,
    output reg [3:0] fault,
    output wire [31:0] debug_pc,
    output wire [3:0] debug_flags,
    input wire [3:0] debug_reg,
    output wire [31:0] debug_value,
    output reg trace_valid,
    output reg [31:0] trace_pc,
    output reg [31:0] trace_instr
);
    localparam FETCH = 2'd0, EXECUTE = 2'd1, MEMORY = 2'd2, STOP = 2'd3;
    localparam FAULT_DECODE = 4'd1, FAULT_ALIGN = 4'd2,
               FAULT_BUS = 4'd3, FAULT_THUMB = 4'd4;
    reg [1:0] state;
    reg [31:0] regs [0:14];
    reg [31:0] pc, instruction;
    reg [3:0] nzcv;
    reg [31:0] data_addr, store_data, updated_base;
    reg [3:0] strobes, load_rd, base_rn;
    reg load, byte_access, writeback;
    integer i;

    wire [3:0] rn = instruction[19:16], rd = instruction[15:12];
    wire [3:0] rm = instruction[3:0], opcode = instruction[24:21];
    wire [31:0] rn_value = rn == 15 ? pc + 8 : regs[rn];
    wire [31:0] rm_value = rm == 15 ? pc + 8 : regs[rm];
    wire [31:0] rd_value = rd == 15 ? pc + 12 : regs[rd];
    wire [31:0] operand2, alu_result;
    wire shift_carry, condition_passed;
    wire [3:0] alu_flags;
    wire is_test = opcode[3:2] == 2'b10;
    wire [31:0] offset = {20'b0, instruction[11:0]};
    wire [31:0] indexed_addr = instruction[23] ? rn_value + offset : rn_value - offset;
    wire [31:0] effective_addr = instruction[24] ? indexed_addr : rn_value;
    wire needs_writeback = !instruction[24] || instruction[21];
    wire [31:0] read_shifted = mem_rdata >> {data_addr[1:0], 3'b000};
    wire [31:0] load_value = byte_access ? {24'b0, read_shifted[7:0]} : mem_rdata;

    arm_condition cond(instruction[31:28], nzcv, condition_passed);
    arm_shifter shifter(instruction[25], instruction[11:0], rm_value,
                        nzcv[1], operand2, shift_carry);
    arm_alu alu(opcode, rn_value, operand2, nzcv, shift_carry, alu_result, alu_flags);

    assign halted = state == STOP;
    assign debug_pc = pc;
    assign debug_flags = nzcv;
    assign debug_value = debug_reg == 15 ? pc + 8 : regs[debug_reg];
    assign mem_valid = !reset && (state == FETCH || state == MEMORY);
    assign mem_instr = state == FETCH;
    assign mem_write = state == MEMORY && !load;
    assign mem_addr = state == FETCH ? pc : {data_addr[31:2], 2'b00};
    assign mem_wdata = state == MEMORY ? store_data : 32'b0;
    assign mem_wstrb = mem_write ? strobes : 4'b0;

    task stop_with_fault;
        input [3:0] code;
        begin state <= STOP; fault <= code; end
    endtask

    task retire;
        begin
            trace_valid <= 1;
            trace_pc <= pc;
            trace_instr <= instruction;
        end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            state <= RESET_VECTOR[1:0] == 0 ? FETCH : STOP;
            fault <= RESET_VECTOR[1:0] == 0 ? 4'b0 : FAULT_ALIGN;
            pc <= RESET_VECTOR;
            instruction <= 0;
            nzcv <= 0;
            data_addr <= 0;
            store_data <= 0;
            updated_base <= 0;
            strobes <= 0;
            load_rd <= 0;
            base_rn <= 0;
            load <= 0;
            byte_access <= 0;
            writeback <= 0;
            trace_valid <= 0;
            trace_pc <= 0;
            trace_instr <= 0;
            for (i = 0; i < 15; i = i + 1) regs[i] <= 0;
        end else begin
            trace_valid <= 0;
            case (state)
                FETCH: if (mem_ready) begin
                    if (mem_error) stop_with_fault(FAULT_BUS);
                    else begin instruction <= mem_rdata; state <= EXECUTE; end
                end
                EXECUTE: begin
                    if (instruction[31:28] == 4'hf) stop_with_fault(FAULT_DECODE);
                    else if (!condition_passed) begin
                        pc <= pc + 4;
                        state <= FETCH;
                        retire();
                    end else if (instruction[27:4] == 24'h12fff1) begin // BX Rm
                        if (rm_value[0]) stop_with_fault(FAULT_THUMB);
                        else if (rm_value[1]) stop_with_fault(FAULT_ALIGN);
                        else begin pc <= rm_value; state <= FETCH; retire(); end
                    end else if (instruction[27:25] == 3'b101) begin // B / BL
                        if (instruction[24]) regs[14] <= pc + 4;
                        pc <= pc + 8 + {{6{instruction[23]}}, instruction[23:0], 2'b00};
                        state <= FETCH;
                        retire();
                    end else if (instruction[27:24] == 4'hf) begin
                        // Local monitor convention, not an ARM exception implementation.
                        if (instruction[23:0] == 0) begin state <= STOP; retire(); end
                        else stop_with_fault(FAULT_DECODE);
                    end else if (instruction[27:26] == 2'b01) begin
                        // Immediate offsets only; reject translated accesses and unsafe aliases.
                        if (instruction[25] || (!instruction[24] && instruction[21]) ||
                            (needs_writeback && (rn == 15 || rn == rd)) ||
                            (instruction[22] && rd == 15) ||
                            (!instruction[20] && rd == 15)) stop_with_fault(FAULT_DECODE);
                        else if (!instruction[22] && effective_addr[1:0] != 0)
                            stop_with_fault(FAULT_ALIGN);
                        else begin
                            data_addr <= effective_addr;
                            updated_base <= indexed_addr;
                            base_rn <= rn;
                            load_rd <= rd;
                            load <= instruction[20];
                            byte_access <= instruction[22];
                            writeback <= needs_writeback;
                            store_data <= instruction[22] ?
                                {24'b0, rd_value[7:0]} << {effective_addr[1:0], 3'b000} : rd_value;
                            strobes <= instruction[22] ? 4'b0001 << effective_addr[1:0] : 4'b1111;
                            state <= MEMORY;
                        end
                    end else if (instruction[27:26] == 2'b00) begin
                        if ((!instruction[25] && instruction[4]) ||
                            (is_test && (!instruction[20] || rd != 0)) ||
                            ((opcode == 13 || opcode == 15) && rn != 0) ||
                            (!is_test && rd == 15 && instruction[20])) stop_with_fault(FAULT_DECODE);
                        else if (!is_test && rd == 15 && alu_result[1:0] != 0)
                            stop_with_fault(FAULT_ALIGN);
                        else begin
                            if (!is_test && rd != 15) regs[rd] <= alu_result;
                            if (instruction[20]) nzcv <= alu_flags;
                            pc <= !is_test && rd == 15 ? alu_result : pc + 4;
                            state <= FETCH;
                            retire();
                        end
                    end else stop_with_fault(FAULT_DECODE);
                end
                MEMORY: if (mem_ready) begin
                    if (mem_error) stop_with_fault(FAULT_BUS);
                    else if (load && load_rd == 15 && load_value[1:0] != 0)
                        stop_with_fault(FAULT_ALIGN);
                    else begin
                        if (writeback) regs[base_rn] <= updated_base;
                        if (load && load_rd != 15) regs[load_rd] <= load_value;
                        pc <= load && load_rd == 15 ? load_value : pc + 4;
                        state <= FETCH;
                        retire();
                    end
                end
                STOP: state <= STOP;
                default: stop_with_fault(FAULT_DECODE);
            endcase
        end
    end
endmodule
`default_nettype wire
