`timescale 1ns/1ps
`default_nettype none
// NZCV is packed in that order. Condition 1111 is rejected by the core.
module arm_condition (
    input wire [3:0] condition,
    input wire [3:0] nzcv,
    output reg passed
);
    wire n = nzcv[3], z = nzcv[2], c = nzcv[1], v = nzcv[0];
    always @* begin
        case (condition)
            4'h0: passed = z;
            4'h1: passed = !z;
            4'h2: passed = c;
            4'h3: passed = !c;
            4'h4: passed = n;
            4'h5: passed = !n;
            4'h6: passed = v;
            4'h7: passed = !v;
            4'h8: passed = c && !z;
            4'h9: passed = !c || z;
            4'ha: passed = n == v;
            4'hb: passed = n != v;
            4'hc: passed = !z && (n == v);
            4'hd: passed = z || (n != v);
            4'he: passed = 1'b1;
            default: passed = 1'b0;
        endcase
    end
endmodule
`default_nettype wire
