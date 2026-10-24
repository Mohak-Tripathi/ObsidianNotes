# Learning Roadmap

We will learn Heap from **first principles**, the same way it was historically invented.

## Phase 1 – Why Heap Exists
- Why arrays weren't enough
- Why linked lists weren't enough
- Why BSTs weren't enough
- What real-world pain Heap solved

## Phase 2 – Build Heap from Scratch
- Complete Binary Tree
- Why complete?
- Why not any binary tree?
- Array representation
- Parent / Left Child / Right Child formulas (derived, not memorized)

## Phase 3 – Heap Operations
- Insert
- Heapify Up
- Delete
- Heapify Down
- Build Heap
- Peek
- Extract Min / Max

Understand **why** every operation has its complexity.

## Phase 4 – Complexity
Derive (not memorize):

- Insert → O(log n)
- Delete → O(log n)
- Peek → O(1)
- Build Heap → O(n)

Special focus: **Why Build Heap is O(n)**.

## Phase 5 – Priority Queue
A **Priority Queue** is the Abstract Data Type (ADT).

A **Heap** is the most common implementation of that ADT.

## Phase 6 – Interview Problems

1. Implement Heap
2. Kth Largest Element
3. Top K Frequent Elements
4. K Closest Points
5. Merge K Sorted Lists
6. Kth Smallest in Matrix
7. Median from Data Stream
8. Task Scheduler
9. Sliding Window Median
10. IPO
11. Find Maximum Capital
12. Smallest Range Covering K Lists

## Phase 7 – Revision Notes
This document will be updated after every session and will become the single revision handbook before interviews.

====================
# Goal

 **why Heap was invented**, 

Learning philosophy:

- Understand the historical problem.
- Understand why older data structures were insufficient.
- Derive the Heap from first principles.
- Learn implementation only after understanding the motivation.

---

# The Problem Before Heap

Many real-world systems repeatedly need the highest- or lowest-priority item.

Examples:

- CPU Scheduler
- Hospital Emergency Queue
- Flight Reservation System
- Printer Job Queue
- Event Simulation
- Dijkstra's Algorithm

The common operation is:

> "Give me the highest-priority element."

---

# Why Existing Data Structures Were Not Enough

## 1. Unsorted Array

Example:

```
[12, 5, 30, 8, 20]
```

### Find Maximum

Need to scan the entire array.

Time Complexity:

- Search max: **O(n)**

Insertion:

- Append at end: **O(1)**

Problem:

Very slow if we repeatedly need the maximum.

---

## 2. Sorted Array

Example:

```
[5, 8, 12, 20, 30]
```

Maximum:

- Last element
- **O(1)**

Insertion:

1. Find insertion position (Binary Search): **O(log n)**
2. Shift elements to make space: **O(n)**

Overall insertion:

**O(n)**

Important distinction:

This is **not** Insertion Sort.

Insertion Sort performs many such insertions, giving **O(n²)** overall.

---

## 3. Linked List

Two cases:

### Node already known

Only pointer updates.

Insertion:

**O(1)**

### Need to find location first

Search:

**O(n)**

Insertion:

**O(1)**

Overall:

**O(n)**

---

## 4. Binary Search Tree (BST)

BST Rule:

```
Left Subtree < Root < Right Subtree
```

Example:

```
        50
      /    \\
    30      80
   /  \\    /  \\
 20   40 60   90
```

Balanced BST Operations:

- Search: **O(log n)**
- Insert: **O(log n)**
- Delete: **O(log n)**

Observation:

BST maintains a **complete ordering** of all elements.

That is more information than a Priority Queue actually needs.
BST maintains a **global ordering** of every element.
Priority Queues do **not** need complete ordering.

---

# The Key Insight Behind Heap

For Priority Queue operations we only care about:

> "Who is the next highest (or lowest) priority?"

We do **not** care about the exact ordering of every other element.

So instead of maintaining full ordering (like BST), Heap maintains only a **partial ordering**.

Max Heap property:

> Parent >= Children

Min Heap property:

> Parent <= Children

---

# Heap Mental Model

Think of a tournament.

The winner reaches the root.

Children only need to beat their own subtrees.

Siblings are **not** ordered.

Therefore:

Heap is **not a sorted tree**.

It is a **partially ordered tree**.

---

# What Does Heap Guarantee?

Only one thing.

Max Heap:

Root is the largest element.

Min Heap:

Root is the smallest element.

Nothing else is guaranteed.

Example:

```
        100
      /     \\
    90       80
   /  \\     /  \\
 70   60   20   50
```

We know:

100 is largest.

But we cannot determine the complete ranking of all remaining nodes.

---

# How Do We Get Top-K Elements?

Repeatedly remove the root.

Each extraction:

**O(log n)**

Top K elements:

**O(k log n)**

This is much faster than sorting everything when K is small.

---

# Why Heap Exists

Heap optimizes repeated access to the minimum or maximum element while avoiding the overhead of maintaining a fully sorted structure.

It is the standard implementation of a **Priority Queue**.

---

# Complexity Summary

| Data Structure | Find Max | Insert |
|----------------|----------|--------|
| Unsorted Array | O(n) | O(1) |
| Sorted Array | O(1) | O(n) |
| Linked List | O(n) | O(1)* |
| Balanced BST | O(log n) | O(log n) |
| Heap | O(1) (peek) | O(log n) |

*Insertion is O(1) only if the insertion location/node is already known.

---

# Interview Takeaways

- Heap is **not** a sorted data structure.
- Heap stores only the ordering required to expose the highest/lowest priority element.
- BST maintains full ordering.
- Heap maintains partial ordering.
- Root is always guaranteed to be the answer (min or max).
- Top-K problems are naturally solved using repeated heap extraction.

---
# Next Session

We will derive:

1. Why a Heap **must** be a Complete Binary Tree.
2. Why pointers are unnecessary.
3. Why Heap is stored in an array.
4. Parent/Child index formulas from first principles.
5. Heapify intuition.

# The Real Reason Complete Binary Trees Were Chosen

Many people think:

> "Heap uses a Complete Binary Tree because that's the definition."

It's actually the opposite.

Engineers wanted:

- Small height (`O(log n)`). BST also do not gurantee o(H) height. It could be skewed. So height issue and global ordering is the issue in BST.
- No expensive balancing logic.
- Efficient array representation.
- Simple insertions and deletions.

The **Complete Binary Tree** is the simplest shape that satisfies all of those goals.

# First-Principles Summary

When designing a priority queue, engineers wanted:

- Fast access to the highest-priority element.
- Fast insertion and deletion.
- A tree that never becomes too tall.
- No complicated balancing.
- A layout that can be stored efficiently in an array.

A **Complete Binary Tree** is the simplest shape that satisfies all these requirements.

from textwrap import dedent
import pypandoc

text=dedent("""
# Heap Handbook - Session 2.1 Addendum

## Questions Clarified

### 1. Rotation (Very Brief)

A rotation is a small restructuring operation used in self-balancing Binary Search Trees (like AVL or Red-Black Trees).

Example:

Before:

```
    30
   /
 20
/
10
```

After one right rotation:

```
   20
  /  \\
10   30
```

The purpose is **not** to change the sorted order. It only changes the shape to keep the tree balanced.

---

### 2. Balancing Algorithm

A balancing algorithm checks whether one side of the tree has become much taller than the other after insertion or deletion.

If it has, it performs one or more rotations to make the height small again.

Heap never performs these balancing rotations.

---

### 3. Binary Tree vs Binary Search Tree vs Heap

These are different concepts.

```
Tree
└── Binary Tree
    ├── Binary Search Tree (BST)
    └── Heap
```

**Binary Tree**
- At most two children.
- No ordering rules.

**Binary Search Tree (BST)**
- A Binary Tree.
- Left < Root < Right.

**Heap**
- A Binary Tree.
- Must be Complete.
- Parent >= Children (Max Heap) OR Parent <= Children (Min Heap).

A Heap is **NOT** a Binary Search Tree.

---

### 4. Why Learn It as a Tree if We Implement It Using an Array?

Conceptually, a Heap is a tree because the parent-child relationships define the algorithm.

Implementation-wise, because the tree is always complete, we can store it in an array without pointers.

Think of it this way:

- **Tree** explains the logic.
- **Array** is the memory representation.

Just like a string is conceptually a sequence of characters but is stored as an array of characters.

In the next lesson we'll prove why a complete binary tree naturally maps to an array.
""")

=================

# Heap Handbook – Session 2.2
## Topic: Why Can a Heap Be Stored in an Array?

---

# Objective

Understand why a Heap is **conceptually a tree** but **implemented using an array**.

This is possible because of the **Complete Binary Tree** property.

---

# Recap

In the previous session we learned that a Heap has two independent properties:

1. **Shape Property**
   - Must be a Complete Binary Tree.

2. **Heap Property**
   - Parent ≥ Children (Max Heap)
   - Parent ≤ Children (Min Heap)

The Shape Property is what makes array implementation possible.

---

# Traditional Tree Implementation

Normally, a binary tree node looks like this:

```java
class Node {
    int value;
    Node left;
    Node right;
}
```

Each node stores:

- Value
- Pointer to Left Child
- Pointer to Right Child

This works for any binary tree.

---

# Observation 1

Consider this Complete Binary Tree.

```
        100
      /     \
     90      80
    /  \    /  \
   70  60  50  40
```

Notice:

- Every level is completely filled.
- There are no gaps.
- Nodes naturally appear level by level.

---

# Observation 2

Write the nodes level by level.

```
100

90 80

70 60 50 40
```

Remove the line breaks.

```
100 90 80 70 60 50 40
```

This is simply:

```
Index : 0   1   2   3   4   5   6

Value :100 90 80 70 60 50 40
```

Without storing a single pointer.

---

# Why Does This Work?

Because the tree is Complete.

There are **no empty positions** before the last node.

This means every node gets a predictable position in the array.

---

# What If the Tree Were Not Complete?

Example:

```
        100
       /    \
     90      80
       \       \
       60       40
```

Array representation becomes:

```
100 90 80 ? 60 ? 40
```

Problems:

- Empty gaps
- Wasted memory
- Parent-child relationships become complicated

The elegant array representation breaks.

---

# Engineering Insight

The Complete Binary Tree gives us two benefits:

1. Height remains O(log n).
2. We can remove left/right pointers completely.

This saves:

- Memory
- Pointer overhead
- Cache misses

Arrays are stored contiguously in memory, making Heap operations very cache-friendly.

---

# Logical View vs Physical View

## Logical View (Algorithm)

Think in terms of:

- Parent
- Left Child
- Right Child

```
        90
      /    \
    70      60
```

This is how we reason about Heap algorithms.

---

## Physical View (Memory)

The same Heap is stored as:

```
[90, 70, 60]
```

The array is only the storage representation.

The algorithm still thinks in terms of parent-child relationships.

---

# Key Takeaway

Tree = Logical Structure

Array = Physical Storage

We learn Heap as a tree because the algorithm is based on parent-child relationships.

We implement Heap as an array because a Complete Binary Tree has a predictable layout.

---

# What's Next?

Now that every node has a fixed position in the array, the next question is:

> Given an index `i`, how do we find its:

- Left Child
- Right Child
- Parent

Instead of memorizing:

- Left = 2i + 1
- Right = 2i + 2
- Parent = (i - 1) / 2

we will derive these formulas from first principles.

---

# Interview Takeaways

- Heap is conceptually a tree but physically stored as an array.
- Array implementation is possible only because Heap is a Complete Binary Tree.
- Complete trees have no gaps before the last node.
- Pointer-based implementation is unnecessary.
- Tree explains the algorithm.
- Array optimizes memory and performance.
  
  So => we started with:

1. We need a Priority Queue.
2. We need low height.
3. Therefore, choose a Complete Binary Tree.
4. A Complete Binary Tree has a predictable layout.
5. Therefore, an array becomes the best representation.

The implementation **follows** from the mathematical property.

It wasn't an arbitrary choice.

---

# One sentence to remember for interviews

If an interviewer asks:

> **"Why is Heap implemented using an array instead of nodes?"**

A strong answer is:

> **Because a Heap is always a Complete Binary Tree. The position of every node is predictable, so parent-child relationships can be computed from indices. Pointers become redundant, reducing memory usage and improving cache locality while keeping operations O(1) for navigation.**
================


