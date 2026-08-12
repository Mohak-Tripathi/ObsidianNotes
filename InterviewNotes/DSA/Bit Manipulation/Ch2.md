# Bit Manipulation — Chapter 2 (Trick Problems)

> Striver A2Z · Chapter 2 · Last updated: Aug 2026

> These are the ~10 standard bit tricks every interviewer expects you to produce instantly. Each is a one-liner once you see the mechanic. `⊕` = my addition, not in Striver's video. Prereq: operators from `bit_manipulation.md` (ch1).

---

## When This Pattern Applies

- "Do X **without extra space** / without a third variable" → XOR trick
- Any per-bit operation: check / set / clear / toggle a specific bit
- "Is it a power of two?" / "Count set bits" / "Is it odd?"
- Interviewer wants an O(1) or O(set bits) answer instead of converting to a binary string and looping

The unifying idea: **build a mask `1 << i`, then combine it with the number using `&` / `|` / `^` / `~`.** Learn that one move and 5 of these fall out.

---

## The Mask: `1 << i`

`1 << i` = a number with a single `1` at position `i`, zeros everywhere else. This is the workhorse of the whole chapter.

```
1 << 0 = 0001
1 << 1 = 0010
1 << 2 = 0100
1 << 3 = 1000
```

Which operator you combine it with decides what happens at bit `i`:

|Operator with mask|Effect on bit `i`|Effect on other bits|
|---|---|---|
|`n & (1<<i)`|reads it|— (result is 0 or nonzero)|
|`n \| (1<<i)`|forces to 1 (set)|untouched|
|`n & ~(1<<i)`|forces to 0 (clear)|untouched|
|`n ^ (1<<i)`|flips it (toggle)|untouched|

---

## 1. Swap Two Numbers (no temp variable)

**Problem:** swap `a` and `b` without a third variable.

**Mechanic — XOR self-cancels** (`x ^ x = 0`, `x ^ 0 = x`):

```python
a = a ^ b     # a now holds a^b
b = a ^ b     # = (a^b)^b = a   → b becomes original a
a = a ^ b     # = (a^b)^a = b   → a becomes original b
```

⚠ **Two honest caveats (interview-relevant):**

- In **Python you'd never actually do this** — the idiomatic swap is `a, b = b, a`. The XOR version exists only to answer the interviewer's "can you do it _without_ a temp?" challenge. Know it, but say the tuple swap is what you'd ship.
- ⊕ **XOR swap breaks on aliasing.** If both operands are the _same_ slot (e.g. `arr[i], arr[i]` when `i == j`), the XOR version zeroes it out (`x ^ x = 0`). The tuple swap doesn't have this bug. Mention this if asked — it's the reason XOR swap is a party trick, not production code.

---

## 2. Check if i'th Bit Is Set

**Problem:** is bit `i` of `n` a 1?

**Two ways, both O(1):**

```python
# Way A — shift the mask up to bit i, AND
if n & (1 << i):        # nonzero → set
    ...

# Way B — shift the bit down to position 0, AND with 1
if (n >> i) & 1:        # 1 → set
    ...
```

Both isolate bit `i`. Way A leaves it at position `i` (result is `2^i` or 0); Way B brings it down to position 0 (result is `1` or `0`). Way B is the one you'll reuse most (it's how you read bits in a loop).

```
n = 13 = 1101, check i=2:
1101 & 0100 = 0100 (nonzero) → SET ✓
```

---

## 3. Set the i'th Bit (force to 1)

**Mechanic — OR forces a 1, leaves others alone:**

```python
n |= (1 << i)
```

```
n = 9 = 1001, set i=2:
1001 | 0100 = 1101 = 13 ✓
```

If the bit was already 1, `OR` leaves it 1 — idempotent, safe.

---

## 4. Clear the i'th Bit (force to 0)

**Mechanic — AND with an all-1s mask that has a single 0 at bit `i`.** Build it by NOT-ing the plain mask:

```python
n &= ~(1 << i)
```

```
1 << 2  = 0100
~(1<<2) = 1011   ← single 0 at bit 2, rest 1s
n = 13 = 1101
1101 & 1011 = 1001 = 9 ✓
```

Every other bit ANDs with 1 (unchanged); bit `i` ANDs with 0 (killed).

---

## 5. Toggle the i'th Bit (flip)

**Mechanic — XOR flips exactly the masked bit:**

```python
n ^= (1 << i)
```

```
n = 13 = 1101, toggle i=1:
1101 ^ 0010 = 1111 = 15   (0→1)
n = 13 = 1101, toggle i=2:
1101 ^ 0100 = 1001 = 9    (1→0)
```

`XOR` with 1 flips, `XOR` with 0 leaves alone — so only bit `i` changes.

---

## 6. Remove the Last (Rightmost) Set Bit

**Mechanic — `n & (n-1)`:**

```python
n &= (n - 1)
```

**Why it works (the key observation of this chapter):** subtracting 1 turns the rightmost `1` into `0` and flips all the `0`s to its right into `1`s; everything left of it is unchanged. AND-ing with the original keeps the left part, kills the rightmost set bit and everything below it.

```
n   = 12 = 1100
n-1 = 11 = 1011
1100 & 1011 = 1000 = 8   ← rightmost set bit (at pos 2) removed ✓
```

This single identity powers both power-of-two and the fast set-bit count below.

---

## 7. Check if Power of Two

**Mechanic:** a power of two has **exactly one** set bit. Removing it → 0.

```python
def is_power_of_two(n: int) -> bool:
    return n > 0 and (n & (n - 1)) == 0
```

⚠ **REJECTION TRAP — `n > 0` is not optional.** Striver's one-liner and most cheat sheets write just `(n & (n-1)) == 0`. That returns **True for n = 0** (`0 & -1 == 0`), but 0 is _not_ a power of two. It's also wrong for negatives. **LC 231 has 0 and negatives in the test cases** — omit the `n > 0` guard and you fail. Always lead with `n > 0 and ...`.

```
16 = 10000, 15 = 01111 → 10000 & 01111 = 0 → power ✓
13 = 01101, 12 = 01100 → 01101 & 01100 = 01100 ≠ 0 → not ✓
 0 → guard catches it → not ✓
```

**Anchor:** LC 231 Power of Two.

---

## 8. Count Set Bits (popcount)

**Two approaches — know both and their complexity.**

**Approach A — divide-by-2 / shift, check last bit each step. O(log n) ≈ O(31):**

```python
def count_set_bits(n: int) -> int:
    count = 0
    while n > 0:
        count += n & 1      # last bit is 1 iff odd
        n >>= 1             # divide by 2
    return count
```

**Approach B — Brian Kernighan, `n & (n-1)`. O(number of set bits) — usually faster:**

```python
def count_set_bits(n: int) -> int:
    count = 0
    while n:
        n &= (n - 1)        # drop the lowest set bit each iteration
        count += 1
    return count
```

Approach B loops **once per set bit**, not once per bit. For sparse numbers (few 1s) it's much faster; worst case (all 1s) both are ~31.

⊕ **Python builtins (use in a real solve):**

```python
bin(n).count('1')     # simplest
n.bit_count()         # Python 3.10+, fastest
```

C++ equivalent is `__builtin_popcount(n)`.

**Anchors:** LC 191 Number of 1 Bits, LC 338 Counting Bits.

---

## 9. Odd / Even Check

**Mechanic — the last bit is 1 iff the number is odd:**

```python
if n & 1:        # odd
    ...
else:            # even
    ...
```

**Why:** every place value except `2^0` is even; the only way to be odd is to have the `2^0` (last) bit set. `13 = 8+4+1` → last bit set → odd. `6 = 4+2` → last bit clear → even.

⊕ Competitive/interview code prefers `n & 1` over `n % 2 == 1` — bitwise is marginally faster and reads as "I know bits."

---

## 10. Divide by 2

```python
n >>= 1        # same as n // 2 (for n ≥ 0)
```

⊕ This is why binary-search mid is often written `mid = (lo + hi) >> 1` instead of `(lo + hi) // 2`. Same result for non-negatives, slightly faster. ⚠ In Python this is cosmetic (no overflow); in C++/Java `>> 1` also dodges the `(lo+hi)` overflow bug — but only if you handle it right, so `lo + (hi-lo)//2` is still the safest overflow-proof form.

---

## ⭐ One-Liner Cheat Sheet

**Python (your stack — primary):**

|#|Operation|One-liner|
|---|---|---|
|1|Swap two numbers|`a ^= b; b ^= a; a ^= b` (or just `a, b = b, a`)|
|2|Check i'th bit set|`(n >> i) & 1` → 1 if set|
|3|Set i'th bit|`n \|= (1 << i)`|
|4|Clear i'th bit|`n &= ~(1 << i)`|
|5|Toggle i'th bit|`n ^= (1 << i)`|
|6|Remove last set bit|`n &= (n - 1)`|
|7|Check power of 2|`n > 0 and (n & (n-1)) == 0` ⚠ keep `n > 0`|
|8|Odd / even|`n & 1` → 1 = odd, 0 = even|
|9|Divide by 2|`n >> 1`|
|10|Count set bits (builtin)|`n.bit_count()` or `bin(n).count('1')`|
|11|Count set bits (loop)|`c=0` then `while n: n &= n-1; c += 1`|

**C++ originals (from the video comment — Striver's form):**

```cpp
1)  Swap:            Num1 ^= Num2; Num2 ^= Num1; Num1 ^= Num2;
2)  Check i'th bit:  if((Num & (1<<i)) != 0) SET; else NOT SET;
3)  Set i'th bit:    Num = (Num | (1<<i));
4)  Clear i'th bit:  Num = (Num & (~(1<<i)));
5)  Toggle i'th bit: Num = (Num ^ (1<<i));
6)  Remove last set: Num = (Num & (Num-1));
7)  Power of 2:      if((Num & (Num-1)) == 0) ...   // ⚠ add Num>0 guard
8)  Odd / even:      if((Num & 1) == 1) odd; else even;
9)  Divide by 2:     Num = (Num >> 1);
10) Popcount (C++):  int ans = __builtin_popcount(Num);
11) Popcount (loop): while(Num){ Num &= Num-1; count++; }
```

---

## My Learnings (Personal — Added as I Solve)

> First entries land when you run the anchor problems: LC 231 (Power of Two), LC 191 (Number of 1 Bits), LC 338 (Counting Bits).

---

## Quick Recall (Read This During Revision)

|Trick|One-liner|Mechanic|
|---|---|---|
|Mask a single bit|`1 << i`|one 1 at pos i|
|Read bit i|`(n >> i) & 1`|shift down, AND 1|
|Set bit i|`n \| (1<<i)`|OR forces 1|
|Clear bit i|`n & ~(1<<i)`|AND with 0-at-i mask|
|Toggle bit i|`n ^ (1<<i)`|XOR flips|
|Drop lowest set bit|`n & (n-1)`|key identity|
|Power of 2|`n>0 and n&(n-1)==0`|one set bit; **guard 0**|
|Odd|`n & 1`|last bit = 2⁰|
|÷2|`n >> 1`|shift right|
|Count bits (fast)|`while n: n&=n-1; c+=1`|O(#set bits)|
|Swap|XOR ×3|`x^x=0`; ⚠ aliasing bug|

**Two things that get you rejected here:** (1) power-of-two without the `n > 0` guard, (2) claiming XOR swap is production-safe (aliasing bug).