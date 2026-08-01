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






----------------------


---

# Python Learnings - When to Use `enumerate()`

One of the most common mistakes while learning Python is using `enumerate()` when it isn't needed.

## What does `enumerate()` return?

`enumerate(iterable)` returns:

```python
(index, element)
```

Example:

```python
arr = ['a', 'b', 'c']

for x in enumerate(arr):
    print(x)
```

Output:

```python
(0, 'a')
(1, 'b')
(2, 'c')
```

---

## Case 1: I only need the values (Most Common)

Do **NOT** use `enumerate()`.

```python
arr = ['a', 'b', 'c']

for ch in arr:
    print(ch)
```

Output:

```python
a
b
c
```

---

## Case 2: I need both key and value from a dictionary

Use `.items()`.

```python
freq = {
    'a': 3,
    'b': 2
}

for ch, count in freq.items():
    print(ch, count)
```

Output:

```python
a 3
b 2
```

---

## Case 3: I sorted dictionary items

```python
sorted_freq = sorted(freq.items())
```

Now every element is a tuple:

```python
('a', 3)
('b', 2)
```

So iterate like:

```python
for ch, count in sorted_freq:
```

NOT

```python
for ch in sorted_freq:
```

because each element contains **two values**.

---

## Case 4: I need the index as well

Only now use `enumerate()`.

```python
for i, (ch, count) in enumerate(sorted_freq):
```

Here:

```python
i
```

is the position in the list.

Example:

```python
sorted_freq = [
    ('a',3),
    ('b',2),
    ('c',1)
]
```

Iteration:

```python
i = 0
ch = 'a'
count = 3

i = 1
ch = 'b'
count = 2

i = 2
ch = 'c'
count = 1
```

This is useful when the index itself is part of the solution.

Examples:

- LeetCode 3016 (keyboard problem)
- Ranking problems
- Cost depends on position
- Every kth element

---

## Common Mistake

I wrote:

```python
for key, val in enumerate(sorted_freq):
```

Thinking:

```python
key = character
val = frequency
```

Wrong.

Actually:

```python
key = index

val = (character, frequency)
```

Example:

```python
enumerate(sorted_freq)

↓

(0, ('a',3))
(1, ('b',2))
```

So:

```python
key = 0
val = ('a',3)
```

which is not what I wanted.

---

## Rule of Thumb

Need only values?

```python
for x in arr:
```

Need dictionary key & value?

```python
for key, value in dict.items():
```

Need tuple values after sorting?

```python
for key, value in sorted(dict.items()):
```

Need index + value?

```python
for i, value in enumerate(arr):
```

Need index + tuple?

```python
for i, (key, value) in enumerate(sorted(dict.items())):
```

---

## Interview Tip

Before writing a `for` loop, ask yourself:

> **Do I actually need the index?**

- **No** → Don't use `enumerate()`.
- **Yes** → Use `enumerate()`.

This simple question prevents one of the most common Python mistakes.




-------------------------

---

# Python Learnings - `append()` vs `extend()`

Lists in Python provide two common ways to add elements:

- `append()`
- `extend()`

Understanding the difference is very important.

---

## 1. append()

`append()` adds **one object** to the end of the list.

Example:

```python
arr = ['a', 'b']

arr.append('c')
```

Output:

```python
['a', 'b', 'c']
```

---

Appending another list:

```python
arr = ['a', 'b']

arr.append(['c', 'd'])
```

Output:

```python
['a', 'b', ['c', 'd']]
```

Notice:

The entire list is inserted as **one element**.

---

## 2. extend()

`extend()` adds **each element of an iterable** individually.

Example:

```python
arr = ['a', 'b']

arr.extend(['c', 'd'])
```

Output:

```python
['a', 'b', 'c', 'd']
```

Instead of inserting one list, it inserts every element inside that list.

---

## Why did we use `extend()` in LeetCode 3517?

We had:

```python
left.extend([ch] * (count // 2))
```

Suppose:

```python
ch = 'a'
count = 6
```

Then

```python
[ch] * (count // 2)
```

becomes

```python
['a', 'a', 'a']
```

Then

```python
left.extend(['a', 'a', 'a'])
```

results in

```python
['a', 'a', 'a']
```

which is exactly what we want.

---

## What if we used append()?

```python
left.append(['a', 'a', 'a'])
```

Result:

```python
[['a', 'a', 'a']]
```

Now the list contains another list.

Then

```python
"".join(left)
```

would fail because `join()` expects a list of strings, not a list containing another list.

---

## Multiplying a List

A very useful Python feature:

```python
['a'] * 3
```

Output:

```python
['a', 'a', 'a']
```

Similarly,

```python
[5] * 4
```

Output:

```python
[5, 5, 5, 5]
```

This is commonly used when repeating the same element multiple times.

---

## Rule of Thumb

Need to add **one element**?

```python
arr.append(x)
```

Need to add **multiple elements from another iterable**?

```python
arr.extend(iterable)
```

---

## JavaScript ↔ Python Mapping

| JavaScript | Python |
|------------|--------|
| `arr.push(x)` | `arr.append(x)` |
| `arr.push(...anotherArray)` | `arr.extend(anotherArray)` |
| `[...arr1, ...arr2]` | `arr1.extend(arr2)` |

---

## Interview Tip

Ask yourself:

> **Am I adding one object or many objects?**

- One object → `append()`
- Many elements → `extend()`

Remember:

```python
append()
```

adds **1 object**.

```python
extend()
```

adds **N elements**.




---------------------




Absolutely. Here's a **Python HashMap (dictionary) crash course** focused on DSA and interviews.

---

# Python HashMap (Dictionary) Crash Course

## 1. Create

```python
mp = {}
```

or

```python
mp = dict()
```

---

## 2. Insert / Update

No `add()` or `set()`.

Simply use:

```python
mp[key] = value
```

Example

```python
mp["apple"] = 5
mp["banana"] = 10
```

Result

```python
{
    "apple": 5,
    "banana": 10
}
```

If the key already exists,

```python
mp["apple"] = 20
```

updates it.

---

## 3. Access

```python
value = mp[key]
```

Example

```python
print(mp["apple"])
```

Output

```text
20
```

⚠️ If the key doesn't exist, Python raises a `KeyError`.

---

## 4. Safe Access (`get()`)

Instead of

```python
mp[key]
```

use

```python
mp.get(key)
```

If absent

```python
mp.get(key)
```

returns

```python
None
```

Or provide a default

```python
mp.get(key, 0)
```

Example

```python
count = mp.get("orange", 0)
```

Output

```text
0
```

---

## 5. Frequency Counting ⭐ (Most Important)

Instead of

```python
if x in mp:
    mp[x] += 1
else:
    mp[x] = 1
```

just write

```python
mp[x] = mp.get(x, 0) + 1
```

Example

```python
nums = [2,2,3,2,5]

mp = {}

for x in nums:
    mp[x] = mp.get(x, 0) + 1
```

Result

```python
{
    2:3,
    3:1,
    5:1
}
```

This is probably the single most common hashmap pattern in interviews.

---

# Nested HashMap

Create

```python
players = {}
```

Suppose

```python
player = 0
color = 2
```

First make sure the player exists.

```python
if player not in players:
    players[player] = {}
```

Now update the color frequency.

```python
players[player][color] = players[player].get(color, 0) + 1
```

Done.

No loops.

---

Example

After processing

```text
(0,2)
(0,2)
(0,5)
(1,3)
```

Dictionary becomes

```python
{
    0:{
        2:2,
        5:1
    },
    1:{
        3:1
    }
}
```

---

## Check if key exists

```python
if key in mp:
```

or

```python
if key not in mp:
```

Example

```python
if "apple" in mp:
    print("Found")
```

---

## Iterate

Keys

```python
for key in mp:
    print(key)
```

---

Values

```python
for value in mp.values():
    print(value)
```

---

Key-Value

```python
for key, value in mp.items():
    print(key, value)
```

Example

```python
{
    2:3,
    5:1
}
```

prints

```text
2 3
5 1
```

---

## Delete

```python
del mp[key]
```

---

# DSA Patterns to Remember

### Frequency Map

```python
mp[x] = mp.get(x, 0) + 1
```

---

### Presence Check

```python
if x in mp:
```

---

### Nested HashMap

```python
if player not in players:
    players[player] = {}

players[player][color] = players[player].get(color, 0) + 1
```

---

## Bonus: `defaultdict` (Very Useful)

Instead of checking whether a key exists every time, Python provides `defaultdict`.

```python
from collections import defaultdict

mp = defaultdict(int)
```

Now

```python
mp[5] += 1
```

works even if `5` wasn't present before.

For a nested hashmap:

```python
from collections import defaultdict

players = defaultdict(dict)

players[player][color] = players[player].get(color, 0) + 1
```

Or even more elegantly:

```python
from collections import defaultdict

players = defaultdict(lambda: defaultdict(int))

players[player][color] += 1
```

This removes the need for existence checks entirely.

---

## Interview Cheat Sheet (copy into `notes.md`)

```python
# Create
mp = {}

# Insert / Update
mp[key] = value

# Get safely
mp.get(key, default)

# Frequency counting
mp[x] = mp.get(x, 0) + 1

# Exists?
if key in mp:
if key not in mp:

# Iterate
for k in mp:
for v in mp.values():
for k, v in mp.items():

# Nested HashMap
if p not in players:
    players[p] = {}

players[p][c] = players[p].get(c, 0) + 1

# defaultdict
from collections import defaultdict

freq = defaultdict(int)
freq[x] += 1

nested = defaultdict(lambda: defaultdict(int))
nested[p][c] += 1
```

For LeetCode and interviews, if you become comfortable with just these patterns, you'll be able to solve the vast majority of hashmap-based problems.