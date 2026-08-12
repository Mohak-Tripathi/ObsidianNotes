# Bit Manipulation — Pattern Notes

> Striver A2Z · Chapter 1 (Fundamentals) · Last updated: Aug 2026

> Chapter 1 is pure foundations — no LeetCode problems yet. This file is the concept reference the later problem chapters lean on. `⊕` marks additions from me, not in Striver's video.

---

## Why This Chapter Exists

The computer never stores decimal. It only understands `0` and `1`. When you write `int x = 13`, the machine converts `13` to binary, stores those bits, and converts back to decimal only when you _read_ it (e.g. `print(x)`). Everything in bit manipulation is about operating directly on those stored bits instead of the decimal illusion on top.

Chapter 1 gives you the four things you must own before any problem:

1. Convert decimal ↔ binary
2. One's / two's complement
3. The operators (AND, OR, XOR, shifts, NOT)
4. How signed integers are actually stored (sign bit + two's complement)

---

## 1. Decimal → Binary (repeated division)

Divide by 2 repeatedly, collect remainders, read them **bottom to top**.

```
13 ÷ 2 = 6 rem 1   ↑
 6 ÷ 2 = 3 rem 0   | read
 3 ÷ 2 = 1 rem 1   | upward
 1 → stop, write 1 ↑

13 = 1101₂
```

Verify: `7 = 111₂`, `13 = 1101₂`.

```python
def to_binary(n: int) -> str:
    if n == 0:
        return "0"
    res = ""
    while n > 0:            # Striver uses n != 1; n > 0 is cleaner and handles n=0-ish edges
        res += "1" if n % 2 == 1 else "0"
        n //= 2
    return res[::-1]        # remainders came out low→high bit, reverse to read MSB first
```

- **Time:** O(log n) — you halve `n` each step.
- **Space:** O(log n) — one char per bit.
- **Gotcha:** you _must_ reverse. Without it you get the bits least-significant-first, which is backwards.

⊕ In Python just use `bin(13)` → `'0b1101'`, or `bin(13)[2:]` → `'1101'`. Write the manual version once to understand it, use the builtin in a real solve.

---

## 2. Binary → Decimal (positional powers)

Index from the **right**, starting at 0. Each `1` contributes `2^index`. Sum them.

```
1 1 0 1
│ │ │ └ 1 × 2⁰ = 1
│ │ └── 0 × 2¹ = 0
│ └──── 1 × 2² = 4
└────── 1 × 2³ = 8
                 ── 
                 13
```

```python
def to_decimal(s: str) -> int:
    num = 0
    power = 1              # 2⁰
    for ch in reversed(s):
        if ch == "1":
            num += power   # a '0' bit contributes nothing, so only add on '1'
        power *= 2         # ⭐ increment the power by *2 each step — don't recompute 2**i
    return num
```

- **Time:** O(len(s)).
- **Space:** O(1).
- **Trick worth keeping:** carry a running `power` and multiply by 2 each iteration instead of calling `pow(2, i)` every loop. Same idea shows up in shift proofs below.

⊕ Python builtin: `int('1101', 2)` → `13`.

> ⚠ **Transcript slip:** the video says "13 is converted into its _decimal_ equivalent which is 1101." That's a verbal slip — `1101` is the **binary** equivalent. The computer stores binary, never decimal.

---

## 3. One's Complement & Two's Complement

**One's complement** = flip every bit.

```
13 = 1101
~   → 0010   (one's complement)
```

**Two's complement** = one's complement **+ 1**.

```
13     = 1101
1's    = 0010
+1     = 0011   (two's complement of 13)
```

Two's complement is the whole ballgame for negative numbers (section 5). Memorize the two steps: **flip, then add 1.**

⊕ Fast identity: **two's complement of x = `-x`** in how the machine represents it. And a shortcut you'll reuse constantly: `~x == -(x + 1)`.

---

## 4. The Operators

### AND `&` — "all true → true"

Bit is `1` only if **every** operand has `1` in that position.

|a|b|a & b|
|---|---|---|
|0|0|0|
|0|1|0|
|1|0|0|
|1|1|1|

```
13 = 1101
 7 = 0111
     ────  &
 5 = 0101
```

### OR `|` — "at least one true → true"

Bit is `1` if **any** operand has `1`.

|a|b|a \| b|
|---|---|---|
|0|0|0|
|0|1|1|
|1|0|1|
|1|1|1|

```
13 = 1101
 7 = 0111
     ────  |
15 = 1111
```

### XOR `^` — "odd number of 1s → 1"

Bit is `1` if the count of `1`s in that position is **odd**.

|a|b|a ^ b|
|---|---|---|
|0|0|0|
|0|1|1|
|1|0|1|
|1|1|0|

```
13 = 1101
 7 = 0111
     ────  ^
10 = 1010
```

⊕ **XOR properties — these carry the most weight in later problems, memorize them:**

- `x ^ 0 = x`
- `x ^ x = 0`
- XOR is commutative & associative → order doesn't matter
- Consequence: XOR the whole array and pairs cancel, leaving the lone unpaired element (LC 136 Single Number). This one identity powers a huge chunk of the bit-manip problem set.

### Left Shift `<<` — multiply by 2^k

`x << k` shifts bits left by `k`, filling right with zeros. Equivalent to `x * 2^k`.

```
13 << 1:  1101 → 11010 = 26   (13 × 2¹)
```

### Right Shift `>>` — floor-divide by 2^k

`x >> k` shifts bits right by `k`, bits fall off the right edge. Equivalent to `x // 2^k` (integer division).

```
13 >> 1:  1101 → 110  = 6    (13 // 2¹ = 6)
13 >> 2:  1101 → 11   = 3    (13 // 4  = 3)
13 >> 4:  1101 → 0    = 0    (13 // 16 = 0)
```

**Why `>> k` = `x // 2^k` (the proof):** each bit's positional power drops by `k`. `1101 = 1·2³ + 1·2² + 0·2¹ + 1·2⁰`. Shift right by 1 → every exponent drops by 1 → `1·2² + 1·2¹ + 0·2⁰` = factor out one `2` from the original = `13 / 2`. Same logic scales: shift by k divides by 2ᵏ.

### NOT `~` — flip, then read as signed

Two-step behavior:

1. Flip all bits.
2. If the result's sign bit is `1` (negative), read its value via two's complement; if positive, read directly.

```
~5:
5      = 0…0101
flip   = 1…1010   → sign bit is 1 → negative → take 2's complement to read value
2's    = 0…0110 = 6
result = -6
```

⊕ Shortcut that always holds: **`~x == -(x + 1)`.** So `~5 = -6`, `~(-6) = 5`. You rarely need the full flip-and-complement dance if you remember this.

---

## 5. How Signed Integers Are Stored (32-bit)

`int` = 32 bits. The **leftmost bit (bit 31)** is the **sign bit**:

- `0` → positive
- `1` → negative

Positive numbers are stored as plain binary:

```
+13 = 0 0000000 00000000 00000000 0001101
      ↑ sign
```

Negative numbers are stored as the **two's complement** of their magnitude:

```
-3:
 3     = 0…0011
 flip  = 1…1100
 +1    = 1…1101   ← this is what -3 actually stores
         ↑ sign bit 1 = negative
```

That's why the machine can tell sign instantly: it just reads bit 31.

### INT_MAX and INT_MIN — derive them, don't memorize blindly

**INT_MAX:** sign bit must be `0` (positive), all remaining 31 bits `1`:

```
0 1111…1111 = 2³⁰ + 2²⁹ + … + 2⁰ = 2³¹ − 1 = 2,147,483,647
```

**INT_MIN:** it is `−2³¹`, **not** `−(2³¹ − 1)`. The trick: `−2³¹` needs no bit besides the sign region. Take `2³¹ = 1000…000`, apply two's complement (flip → `0111…111`, +1 → `1000…000`), and the sign bit ends up `1` with all-zero magnitude:

```
−2³¹ = 1 0000…0000 = −2,147,483,648
```

The negative range is one wider than the positive range because `0` "uses up" a positive slot but negatives don't need to represent `−0`.

> ⚠ **Confusion resolved — the interview-only mental model for INT_MAX / INT_MIN**
> 
> **Why 31, not 32?** 32 bits total, but the leftmost bit is stolen for the **sign** (`0` = +, `1` = −). Only **31 bits** are left to hold the number's size. That's why `31` shows up everywhere, not `32`.
> 
> **Why `2³¹ − 1`? Where does the minus 1 come from?** It's just what "all ones" equals. **All-ones in `n` bits = `2ⁿ − 1`, never `2ⁿ`.**
> 
> - Decimal analogy: three digits all 9 → `999` = `1000 − 1` = `10³ − 1`. All-nines is always one less than the next power of ten.
> - Same in binary: `111 = 4+2+1 = 7 = 2³ − 1` (not 8).
> - So 31 magnitude bits all set = `2³¹ − 1`. The `−1` isn't a correction bolted on — it's literally _what all-ones is_.
> - And it's `2³¹` not `2³²` because only 31 bits were available (sign ate one).
> 
> **Why does INT_MIN not get the `−1`?** Split the fixed patterns into two teams:
> 
> |Side|Range|Count|
> |---|---|---|
> |Non-negative|`0` … `2³¹ − 1`|2³¹|
> |Negative|`−1` … `−2³¹`|2³¹|
> 
> The positive side spends one pattern on **zero**, so it stops one short → `2³¹ − 1`. The negative side never needs `−0`, so it gets the full run → `−2³¹`. Zero lives on the positive team; that's the entire asymmetry.
> 
> **Two's complement — always?** No. **Positive → plain binary. Negative → two's complement.** Only negatives get complemented. You never "make positive then complement again" as a routine.
> 
> **The one thing worth memorizing:** `~x == −(x + 1)`. Skip the flip-and-add-1 mechanics.

### Overflow on shifts

Left-shifting past the width overflows and gives garbage:

```
(2³¹ − 1) << 1   → overflows a 32-bit int
```

⚠ When left-shifting, respect the 32-bit boundary or you get weird/wrapped values. (Not an issue in Python — see below — but it _is_ the C++/Java mental model Striver teaches and what interviewers assume.)

---

## 6. ⊕ Python-Specific Notes (READ THIS — Striver teaches C++ 32-bit)

Striver's whole "32 bits, sign bit, overflow" model is the **C++/Java** reality. Python ints are **arbitrary precision** — no fixed width, no overflow. This changes real behavior:

|Concept|C++/Java (Striver)|Python|
|---|---|---|
|Int width|fixed 32 (or 64)|unbounded|
|`~x`|flip within 32 bits|`~x == -(x+1)`, conceptually infinite bits|
|`x >> 1` on negatives|depends on impl|**arithmetic** shift = floor division (`-3 >> 1 == -2`)|
|Overflow on `<<`|yes, wraps|never — number just grows|
|Get bit count|32 assumed|`x.bit_length()` (excludes sign)|

**Consequences that bite in interviews:**

- `~x == -(x + 1)` in Python, exactly. No 32-bit truncation happens.
- Right shift on negatives is **floor**, not truncation toward zero: `-3 >> 1 == -2` (because `-3 // 2 == -2` in Python). Watch this.
- To **emulate 32-bit** behavior (needed for problems like LC 190 Reverse Bits, LC 371 Sum of Two Integers where the expected answer assumes 32-bit wraparound), mask:

```python
MASK = 0xFFFFFFFF          # 32 ones
INT_MAX = 0x7FFFFFFF       # 2³¹ − 1

x &= MASK                  # keep only low 32 bits
# if result's sign bit (bit 31) is set, convert back to Python negative:
if x > INT_MAX:
    x = ~(x ^ MASK)        # undo the mask into a true negative
```

**Handy Python builtins for bit problems:**

```python
bin(13)              # '0b1101'
bin(13).count('1')   # popcount = 3
int('1101', 2)       # 13
(13 >> i) & 1        # read the i-th bit
13 | (1 << i)        # set the i-th bit
13 & ~(1 << i)       # clear the i-th bit
13 ^ (1 << i)        # toggle the i-th bit
13 & (13 - 1)        # ⭐ drop the lowest set bit (Brian Kernighan) — key for counting set bits
```

---

## My Learnings (Personal — Added as I Solve)

> Chapter 1 has no problems. First entries land when Striver's problem chapters start (Single Number, Set/Clear/Toggle bit, Count set bits, Power of two, etc.).

---

## Quick Recall (Read This During Revision)

|Thing|Rule|
|---|---|
|Dec → Bin|Divide by 2, remainders bottom→top|
|Bin → Dec|Sum of `2^index` for each set bit|
|One's complement|Flip all bits|
|Two's complement|Flip all bits, **+1**|
|`&`|all 1 → 1|
|`\|`|any 1 → 1|
|`^`|odd count of 1 → 1|
|`x << k`|`x * 2^k`|
|`x >> k`|`x // 2^k` (floor)|
|`~x`|`-(x + 1)`|
|Negative storage|two's complement of magnitude|
|Sign bit|bit 31: 0 = +, 1 = −|
|INT_MAX|`2³¹ − 1` = 2147483647|
|INT_MIN|`−2³¹` = −2147483648 (range asymmetric)|
|XOR identities|`x^0=x`, `x^x=0`, order-independent|
|Drop lowest set bit|`x & (x-1)`|
|Python `~`/`>>`|`~x=-(x+1)`; `>>` on neg = floor div|