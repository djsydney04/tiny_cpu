"""Independent mathematical expectations for the supported datapath, not an emulator."""
MASK = 2**32 - 1


def signed(x):
    return x if x < 2**31 else x - 2**32


def condition(code, flags):
    n, z, c, v = (bool(flags & bit) for bit in (8, 4, 2, 1))
    return (z, not z, c, not c, n, not n, v, not v, c and not z,
            not c or z, n == v, n != v, not z and n == v,
            z or n != v, True, False)[code]


def rotate(x, amount):
    amount %= 32
    return ((x >> amount) | (x << (32 - amount))) & MASK


def shift(immediate, operand, value, carry):
    if immediate:
        amount = ((operand >> 8) & 15) * 2
        result = rotate(operand & 255, amount)
        return result, result >> 31 if amount else carry
    amount, kind = operand >> 7, (operand >> 5) & 3
    if kind == 0:
        return (value << amount) & MASK, (value >> (32 - amount)) & 1 if amount else carry
    if kind == 1:
        amount = amount or 32
        return value >> amount, (value >> (amount - 1)) & 1
    if kind == 2:
        amount = amount or 32
        return (signed(value) // 2**amount) & MASK, (value >> (amount - 1)) & 1
    if amount == 0:
        return (carry << 31) | (value >> 1), value & 1
    result = rotate(value, amount)
    return result, result >> 31


def alu(op, a, b, old, shift_carry):
    carry, overflow = shift_carry, old & 1
    carry_in = (old >> 1) & 1
    if op in (2, 3, 4, 5, 6, 7, 10, 11):
        if op in (2, 10):
            full, exact = a - b, signed(a) - signed(b)
        elif op == 3:
            full, exact = b - a, signed(b) - signed(a)
        elif op in (4, 11):
            full, exact = a + b, signed(a) + signed(b)
        elif op == 5:
            full, exact = a + b + carry_in, signed(a) + signed(b) + carry_in
        elif op == 6:
            full, exact = a - b - (1 - carry_in), signed(a) - signed(b) - (1 - carry_in)
        else:
            full, exact = b - a - (1 - carry_in), signed(b) - signed(a) - (1 - carry_in)
        carry = int(full > MASK) if op in (4, 5, 11) else int(full >= 0)
        overflow = int(not -2**31 <= exact < 2**31)
        result = full & MASK
    else:
        result = {0: a & b, 1: a ^ b, 8: a & b, 9: a ^ b,
                  12: a | b, 13: b, 14: a & ~b, 15: ~b}[op] & MASK
    return result, (result >> 31) * 8 + (result == 0) * 4 + carry * 2 + overflow
