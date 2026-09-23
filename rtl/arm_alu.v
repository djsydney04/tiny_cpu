`timescale 1ns/1ps
`default_nettype none
module arm_alu (
    input wire [3:0] opcode,
    input wire [31:0] a, b,
    input wire [3:0] old_flags,
    input wire shift_carry,
    output reg [31:0] result,
    output wire [3:0] flags
);
    reg [31:0] add_a, add_b;
    reg add_c, arithmetic, carry, overflow;
    reg [32:0] sum;
    assign flags = {result[31], result == 0, carry, overflow};
    always @* begin
        add_a = a;
        add_b = b;
        add_c = 0;
        arithmetic = 0;
        result = 0;
        carry = shift_carry;
        overflow = old_flags[0];
        case (opcode)
            4'h0, 4'h8: result = a & b; // AND / TST
            4'h1, 4'h9: result = a ^ b; // EOR / TEQ
            4'h2, 4'ha: begin arithmetic = 1; add_b = ~b; add_c = 1; end
            4'h3: begin arithmetic = 1; add_a = b; add_b = ~a; add_c = 1; end
            4'h4, 4'hb: arithmetic = 1; // ADD / CMN
            4'h5: begin arithmetic = 1; add_c = old_flags[1]; end
            4'h6: begin arithmetic = 1; add_b = ~b; add_c = old_flags[1]; end
            4'h7: begin arithmetic = 1; add_a = b; add_b = ~a; add_c = old_flags[1]; end
            4'hc: result = a | b;
            4'hd: result = b;
            4'he: result = a & ~b;
            4'hf: result = ~b;
        endcase
        sum = {1'b0, add_a} + {1'b0, add_b} + {32'b0, add_c};
        if (arithmetic) begin
            result = sum[31:0];
            carry = sum[32];
            overflow = (add_a[31] == add_b[31]) && (result[31] != add_a[31]);
        end
    end
endmodule
`default_nettype wire
