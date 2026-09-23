`timescale 1ns/1ps
`default_nettype none
// A32 Operand2: rotated immediate or register shifted by an immediate.
module arm_shifter (
    input wire immediate,
    input wire [11:0] operand,
    input wire [31:0] rm,
    input wire carry_in,
    output reg [31:0] value,
    output reg carry_out
);
    reg [31:0] source;
    reg [4:0] amount;
    always @* begin
        source = {24'b0, operand[7:0]};
        amount = immediate ? {operand[11:8], 1'b0} : operand[11:7];
        value = rm;
        carry_out = carry_in;
        if (immediate) begin
            value = source;
            if (amount != 0) begin
                value = (source >> amount) | (source << (32 - amount));
                carry_out = value[31];
            end
        end else begin
            case (operand[6:5])
                2'b00: if (amount != 0) begin // LSL #0 preserves carry
                    value = rm << amount;
                    carry_out = rm[32 - amount];
                end
                2'b01: begin // Encoded LSR #0 means LSR #32
                    value = amount == 0 ? 32'b0 : rm >> amount;
                    carry_out = amount == 0 ? rm[31] : rm[amount - 1];
                end
                2'b10: begin // Encoded ASR #0 means ASR #32
                    if (amount == 0) value = {32{rm[31]}};
                    else value = $signed(rm) >>> amount;
                    carry_out = amount == 0 ? rm[31] : rm[amount - 1];
                end
                2'b11: begin // Encoded ROR #0 is RRX
                    if (amount == 0) begin
                        value = {carry_in, rm[31:1]};
                        carry_out = rm[0];
                    end else begin
                        value = (rm >> amount) | (rm << (32 - amount));
                        carry_out = value[31];
                    end
                end
            endcase
        end
    end
endmodule
`default_nettype wire
