# Bit Manipulation — Chapter 3 (Minimum Bit Flips)

> Striver A2Z · Chapter 3 · Last updated: Aug 2026

> Single-problem chapter. This is the first place ch1 + ch2 combine: **XOR to find which bits differ, then count them.** Prereqs: XOR properties (`bit_manipulation.md`), count-set-bits (`bit_manipulation_ch2.md` §8).

---

## LC 2220 — Minimum Bit Flips to Convert a Number

**Problem:** given `start` and `goal` (non-negative ints), return the minimum number of bit flips to turn `start` into `goal`. A flip changes one bit (`0↔1`).

```
start = 10 = 1010
goal  =  7 = 0111
         ────
differ:  1101 → 3 positions differ → 3 flips
```

---

## The Insight — Why XOR

You need to count the positions where the two numbers **differ**. Walk the operators:

- `AND` / `OR` can't tell "same" from "different" — both give 1 when both bits are 1.
- **`XOR` gives 1 exactly when the two bits differ** (`0^1 = 1`, `1^1 = 0`, `0^0 = 0`).

So `start ^ goal` produces a number whose **set bits are precisely the positions that must be flipped.** Count those set bits → answer.

```
Step 1:  diff = start ^ goal      # set bits = positions to flip
Step 2:  answer = popcount(diff)  # count them
```

---

## Solution (Python)

**One-liner (what you'd ship):**

```python
def minBitFlips(self, start: int, goal: int) -> int:
    return (start ^ goal).bit_count()      # Python 3.10+
```

**Interview version — spell out the count** (in case they want the mechanic, or bit_count isn't allowed):

```python
def minBitFlips(self, start: int, goal: int) -> int:
    diff = start ^ goal
    count = 0
    while diff:                 # Brian Kernighan — see ch2 §8
        diff &= (diff - 1)      # drop lowest set bit
        count += 1
    return count
```

Either counting method from ch2 §8 works here — `bin(x).count('1')`, the shift loop, or Brian Kernighan. Don't re-derive them; they're in ch2.

---

## Complexity

- **Time:** O(number of bits in `start ^ goal`). Striver counts to 31 (fixed int width); with the divide/Kernighan loop it's O(log(start^goal)) ≈ O(#differing bits) — no need to always walk all 31.
- **Space:** O(1).

⊕ In Python there's no fixed 31-bit ceiling (arbitrary precision), so the loop naturally runs only as far as the highest set bit — cheaper than Striver's fixed 0→31 traversal, same answer.

---

## My Learnings (Personal — Added After I Solve)

> LC 2220 — log your V1 here after a blind attempt: did you reach for XOR immediately, or try to compare bit-by-bit the long way?

---

## Quick Recall

|Step|Op|Why|
|---|---|---|
|Find differing bits|`start ^ goal`|XOR = 1 iff bits differ|
|Count them|popcount|set bits = flips needed|
|Ship|`(start ^ goal).bit_count()`|—|

**Pattern to generalize:** "count positions where two things differ" → **XOR then popcount.** This combo recurs (e.g. Hamming Distance, LC 461 — literally the same solution).