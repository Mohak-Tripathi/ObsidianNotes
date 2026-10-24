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
