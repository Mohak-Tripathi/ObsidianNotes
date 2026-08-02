
Yes, GCD stands for **Greatest Common Divisor** (also called **Greatest Common Factor - GCF** or **Highest Common Factor - HCF**). They all mean the same thing.

Since you're building your DSA fundamentals, let's make this into proper revision notes.

---

# GCD (Greatest Common Divisor)

## Definition

The **Greatest Common Divisor (GCD)** of two numbers is the **largest positive integer that divides both numbers without leaving any remainder.**

For example,

```
GCD(12, 18)

Factors of 12 = 1,2,3,4,6,12
Factors of 18 = 1,2,3,6,9,18

Common factors = 1,2,3,6

Greatest = 6
```

So,

```
GCD(12,18)=6
```

---

# Example 1

```
8 and 12
```

Factors

```
8  -> 1 2 4 8

12 -> 1 2 3 4 6 12
```

Common

```
1 2 4
```

Largest

```
GCD = 4
```

---

# Example 2

```
9 and 15
```

Factors

```
9 -> 1 3 9

15 -> 1 3 5 15
```

Largest common

```
3
```

---

# Example 3 (Co-prime)

```
7 and 13
```

Factors

```
7  -> 1 7

13 -> 1 13
```

Only common factor

```
1
```

So

```
GCD = 1
```

When GCD is 1, the numbers are called **co-prime (relatively prime)**.

---

# Mathematical Method 1 (Listing Factors)

This is only useful for small numbers.

Example

```
20 and 30

20 -> 1 2 4 5 10 20

30 -> 1 2 3 5 6 10 15 30

Largest common = 10
```

Time complexity is bad for large numbers.

---

# Mathematical Method 2 (Prime Factorization)

Example

```
12 = 2 × 2 × 3

18 = 2 × 3 × 3
```

Take only common prime factors.

```
12 = 2² × 3

18 = 2 × 3²
```

Common

```
2 × 3 = 6
```

So

```
GCD = 6
```

---

# Mathematical Method 3 (Euclidean Algorithm)

This is the most important one.

The idea is:

> The GCD of two numbers never changes if you replace the larger number with its remainder when divided by the smaller number.

Mathematically,

```
gcd(a,b)

=

gcd(b,a%b)
```

Repeat until remainder becomes zero.

---

Example

Find

```
GCD(48,18)
```

Step 1

```
48 ÷ 18

Quotient = 2

Remainder = 12
```

So

```
GCD(48,18)

=

GCD(18,12)
```

---

Step 2

```
18 ÷ 12

Remainder = 6
```

Now

```
GCD(18,12)

=

GCD(12,6)
```

---

Step 3

```
12 ÷ 6

Remainder = 0
```

Once remainder becomes zero,

```
Answer = 6
```

---

Why does this work?

Suppose

```
a = b × q + r
```

Any number that divides both `a` and `b` will also divide `r`.

So the common divisors never change.

Therefore,

```
gcd(a,b)=gcd(b,r)
```

This is the entire Euclidean algorithm.

---

# Programmatically

Recursive version

```python
def gcd(a, b):
    if b == 0:
        return a
    return gcd(b, a % b)
```

---

Iterative version

```python
def gcd(a, b):
    while b != 0:
        a, b = b, a % b
    return a
```

This is the version you'll usually write in interviews.

---

# Complexity

Each step makes the numbers significantly smaller.

```
Time : O(log(min(a,b)))

Space :
Recursive -> O(log n)

Iterative -> O(1)
```

---

# Trick to Remember

```
GCD = Biggest number that divides both numbers.

Euclidean Algorithm

gcd(a,b)

↓

gcd(b,a%b)

↓

repeat until b becomes 0

↓

answer = a
```

---

# Applying it to your LeetCode problem

The formula is:

[  
\frac{\text{nums}[i] \times \text{nums}[j]}{\text{gcd}(\text{nums}[i], \text{nums}[j])^2}  
]

Notice the behavior:

- If `gcd = 1` (co-prime numbers), the denominator is `1`, so the strength is simply the product of the two numbers.
    
- If the numbers share many common factors, the GCD becomes larger, and since you're dividing by **GCD²**, the strength decreases.
    

That's why in the example `[2, 3, 5]`, choosing `(3, 5)` gives the maximum strength:

- `gcd(3,5) = 1`
    
- Strength = `(3 × 5) / 1² = 15`
    

As you continue with DSA, you'll see GCD appear frequently in number theory, array problems, fractions, and modular arithmetic. It's one of the foundational mathematical tools worth becoming comfortable with.



You're **very close**, but there is one major logic mistake.

### Your code is only checking adjacent pairs.

You wrote:

```python
for i in range(len(nums)-1):
    curr_gcd = findGcd(nums[i], nums[i+1])
```

This only compares:

```
(0,1)
(1,2)
(2,3)
...
```

But the problem says:

> **Choose exactly one pair of distinct indices i and j.**

That means you must check **every possible pair**, not just neighbors.

For example, if:

```python
nums = [6, 10, 15]
```

Your code checks:

```
(6,10)
(10,15)
```

But it completely misses:

```
(6,15)
```

which might actually give the maximum answer.

---

### You need two loops

```python
for i in range(len(nums)):
    for j in range(i + 1, len(nums)):
        curr_gcd = findGcd(nums[i], nums[j])
        curr = (nums[i] * nums[j]) // (curr_gcd * curr_gcd)
        res = max(res, curr)
```

Notice that:

- `i = 0`
    
    - `j = 1`
        
    - `j = 2`
        
    - `j = 3`
        
- `i = 1`
    
    - `j = 2`
        
    - `j = 3`
        
- ...
    

This checks **all** pairs.

---

### One small improvement

Instead of:

```python
curr_gcd ** 2
```

I recommend:

```python
curr_gcd * curr_gcd
```

It's slightly faster and avoids using the exponent operator.

---

### Time Complexity

- Number of pairs = (n(n-1)/2)
    
- GCD takes (O(\log(\min(a,b))))
    

Overall:

```
O(n² × log(max(nums)))
```

---

This is a classic beginner mistake, and it's actually a good sign—you focused on implementing the GCD correctly. The key takeaway is to **read the wording carefully**: when a problem says "choose any pair," your default thought should be, _"I probably need two nested loops unless there's an optimization."_