# LeetCode Learning Notes (Running Document)

---

# LeetCode 3016 – Minimum Number of Pushes to Type Word II

## Problem Insight

- Unlike 3014, characters can repeat.
    
- Since keys can be remapped arbitrarily, assign the most frequent letters to the cheapest positions.
    
- Cost of each position:
    
    - Index 0–7 → 1 push
        
    - Index 8–15 → 2 pushes
        
    - Index 16–23 → 3 pushes
        
    - Formula: `cost = index // 8 + 1`
        

## Python Learnings

### Counter

```python
from collections import Counter

freq = Counter(word)
```

Returns a dictionary-like object mapping each character to its frequency.

---

### items()

```python
freq.items()
```

Returns `(key, value)` tuples.

Example:

```python
{'a':3,'b':2}.items()

↓

('a',3)
('b',2)
```

Useful when both key and value are needed.

---

### sorted()

```python
sorted(iterable)
```

Returns a **new sorted list**.

Does **not** modify the original object.

---

### Lambda Function

```python
lambda x: x[1]
```

Equivalent to

```python
def get_value(x):
    return x[1]
```

Used when a small one-time function is needed.

Example:

```python
sorted(freq.items(),
       key=lambda x: x[1],
       reverse=True)
```

Meaning:

- Take each `(character, frequency)` pair.
    
- Compare only the frequency (`x[1]`).
    
- Sort in descending order.
    

---

### enumerate()

```python
for i, value in enumerate(arr):
```

Returns both the index and value.

Example:

```python
enumerate(['a','b','c'])

↓

(0,'a')
(1,'b')
(2,'c')
```

Useful when the index is part of the solution.

---

### Pattern Learned

Whenever I need to process elements by descending frequency:

1. Count using `Counter`
    
2. Sort using
    

```python
sorted(counter.items(),
       key=lambda x:x[1],
       reverse=True)
```

or simply

```python
sorted(counter.values(),
       reverse=True)
```

3. Use `enumerate()` whenever the index determines the answer.
    

---

### Complexity

- Counting: O(n)
    
- Sorting: O(26 log 26) ≈ O(1)
    
- Overall: O(n)
    

---

### New Python Concepts Learned

- Counter
    
- items()
    
- sorted()
    
- lambda
    
- reverse=True
    
- enumerate()
    
- tuple unpacking
    

---

# LeetCode 3536 – Maximum Product of Two Digits

## Problem Insight

Need the two largest digits of a number.

Possible approaches:

1. Convert digits into a list → sort → multiply last two digits.
    
2. Scan once while maintaining the largest and second largest digit.
    

The second approach is optimal because sorting is unnecessary.

---

## Pattern Learned

Decision tree:

- Need maximum → Maintain one variable.
    
- Need largest & second largest → Maintain two variables.
    
- Need Top K → Think Heap.
    
- Need complete ordering → Sort.
    

This problem is **NOT** a heap problem.

---

## Python Learnings

### Extract digits from an integer

```python
digit = n % 10
n //= 10
```

Example:

```text
6382

digit = 2
n = 638

digit = 8
n = 63
```

---

### Sentinel Initialization

General:

```python
largest = float('-inf')
second = float('-inf')
```

For digits only:

```python
largest = -1
second = -1
```

Both work.

---

### Maintain Largest & Second Largest

Reusable interview template:

```python
largest = float('-inf')
second = float('-inf')

for x in data:
    if x > largest:
        second = largest
        largest = x
    elif x > second:
        second = x
```

This finds the two largest values in one pass.

---

## Common Mistakes / Learnings

- Initially considered using a Max Heap.
    
- Learned that a heap is unnecessary when only the top two elements are required.
    
- Sorting also works but is less efficient than a single scan.
    

---

## Complexity

- Time: O(d), where d is the number of digits.
    
- Space: O(1)
    

---

## Python Concepts Learned So Far

- Counter
    
- items()
    
- sorted()
    
- lambda
    
- reverse=True
    
- enumerate()
    
- tuple unpacking
    
- Integer digit extraction using `%` and `//`
    
- `float('-inf')`
    
- One-pass largest & second-largest tracking
    
- Choosing between sorting, heap, and linear scan





---

# Python Learnings - String & List Operations

These operations are extremely common in LeetCode and should become muscle memory.

## 1. String → List

Convert a string into a list of characters.

```python
s = "hello"

arr = list(s)
```

Output:

```python
['h', 'e', 'l', 'l', 'o']
```

Equivalent in JavaScript:

```javascript
str.split("")
// or
[...str]
```

---

## 2. List → String

Convert a list of characters back into a string.

```python
arr = ['h', 'e', 'l', 'l', 'o']

s = "".join(arr)
```

Output:

```python
"hello"
```

Think of `join()` as:

> Join every element of the list using the given separator.

Examples:

```python
"".join(['a','b','c'])
```

Output:

```text
abc
```

```python
",".join(['a','b','c'])
```

Output:

```text
a,b,c
```

This is the standard Python way of converting a character list into a string.

---

## 3. Reverse a String

```python
s = "abcd"

s[::-1]
```

Output:

```text
dcba
```

Explanation:

Slice syntax:

```python
[start:end:step]
```

A step of `-1` means move backwards.

This is equivalent to JavaScript:

```javascript
str.split("").reverse().join("")
```

but much shorter.

---

## 4. Reverse a List

```python
arr = ['a','b','c']

arr[::-1]
```

Output:

```python
['c','b','a']
```

This returns a **new reversed list**.

To reverse the same list in-place:

```python
arr.reverse()
```

Difference:

```python
arr[::-1]
```

- Creates a new list.
- Original list remains unchanged.

```python
arr.reverse()
```

- Modifies the original list.
- Returns `None`.

---

## 5. Build a Palindrome Efficiently

Instead of filling characters from both ends of an answer array:

1. Build only the left half.
2. Convert it to a string.
3. Reverse it.
4. Append the middle character (if any).

Example:

```python
left = ['a','b','b','c']
middle = ""

left_str = "".join(left)

answer = left_str + middle + left_str[::-1]
```

Result:

```text
abbccbba
```

Key Insight:

A palindrome is completely determined by:

- Left half
- Optional middle character
- Mirror of the left half

Therefore, only the left half needs to be constructed explicitly.

---

## JavaScript ↔ Python Cheat Sheet

| JavaScript | Python |
|------------|--------|
| `str.split("")` | `list(str)` |
| `[...str]` | `list(str)` |
| `arr.join("")` | `"".join(arr)` |
| `str.split("").reverse().join("")` | `s[::-1]` |
| `arr.reverse()` | `arr.reverse()` *(in-place)* |
| `[...arr].reverse()` | `arr[::-1]` *(returns a new list)* |

---

## Pattern Learned

Whenever a problem asks to construct a palindrome:

- Count frequencies.
- Build the left half in lexicographical order.
- Store the odd-frequency character as the middle (if any).
- Mirror the left half to obtain the right half.

This avoids complicated two-pointer or front/back filling logic.