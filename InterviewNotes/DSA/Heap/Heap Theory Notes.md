# Heap Handbook (Cumulative Notes)

**Track:** Striver A2Z DSA • **Topic:** Heap • **Version:** Session 1

---

# Learning Roadmap

We will learn Heap from **first principles**, the same way it was  
historically invented.

## Phase 1 -- Why Heap Exists

- Why arrays weren't enough
    
- Why linked lists weren't enough
    
- Why BSTs weren't enough
    
- What real-world pain Heap solved
    

## Phase 2 -- Build Heap from Scratch

- Complete Binary Tree
    
- Why complete?
    
- Why not any binary tree?
    
- Array representation
    
- Parent / Left Child / Right Child formulas (derived, not memorized)
    

## Phase 3 -- Heap Operations

- Insert
    
- Heapify Up
    
- Delete
    
- Heapify Down
    
- Build Heap
    
- Peek
    
- Extract Min / Max
    

Understand **why** every operation has its complexity.

## Phase 4 -- Complexity

Derive (not memorize):

- Insert → O(log n)
    
- Delete → O(log n)
    
- Peek → O(1)
    
- Build Heap → O(n)
    

Special focus: **Why Build Heap is O(n)**.

## Phase 5 -- Priority Queue

A **Priority Queue** is the Abstract Data Type (ADT).

A **Heap** is the most common implementation of that ADT.

## Phase 6 -- Interview Problems

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
    

## Phase 7 -- Revision Notes

This document will be updated after every session and will become the  
single revision handbook before interviews.

---

# Why Was Heap Invented?

Imagine building:

- CPU Scheduler
    
- Printer Queue
    
- Hospital Emergency Queue
    
- Flight Reservation System
    

Repeated operation:

> "Give me the highest-priority task."

The challenge is to support this operation efficiently while still  
allowing fast insertions.

---

# Existing Data Structures

## 1. Unsorted Array

Example:

```
[12, 5, 30, 8, 20]
```

- Find maximum → O(n)
    
- Insert → O(1)
    

Problem: Repeated maximum queries are slow.

---

## 2. Sorted Array

Example:

```
[5, 8, 12, 20, 30]
```

- Maximum → O(1)
    

Insert 15:

```
[5, 8, 12, 15, 20, 30]
```

Cost:

1. Binary Search → O(log n)
    
2. Shift elements → O(n)
    

Overall insertion:

**O(n)**

### Important

This is **not Insertion Sort**.

Insertion Sort performs many such insertions, leading to **O(n²)**  
overall.

---

## 3. Linked List

If the insertion position (node) is already known:

- Insert → O(1)
    

If the position must first be searched:

- Search → O(n)
    
- Insert → O(1)
    

Overall:

**O(n)**

Finding the maximum also requires **O(n)**.

---

## 4. Binary Search Tree (BST)

Rule:

```
Left Subtree < Root < Right Subtree
```

Example:

```
        50
      /    \
    30      80
   /  \    /  \
 20   40 60   90
```

Balanced BST:

- Search → O(log n)
    
- Insert → O(log n)
    
- Delete → O(log n)
    

### Limitation

BST maintains a **global ordering** of every element.

Priority Queues do **not** need complete ordering.

---

# The Core Insight Behind Heap

Instead of maintaining:

```
Everything Sorted
```

Maintain only:

```
Parent >= Children   (Max Heap)

or

Parent <= Children   (Min Heap)
```

This partial ordering is sufficient because only the next highest (or  
lowest) priority element matters.

---

# Mental Model

Think of a tournament.

```
        100
      /     \
    80       70
   /  \     /  \
 40   60   50  20
```

- 100 beat everyone.
    
- 80 only beat its own subtree.
    
- 70 only beat its own subtree.
    
- Siblings are not ordered.
    

Heap is **partially ordered**, not fully sorted.

---

# What Does Heap Guarantee?

Only one guarantee:

- Max Heap → Root is the largest element.
    
- Min Heap → Root is the smallest element.
    

Nothing else is guaranteed.

---

# Top-K Elements

Need Top 5?

Repeatedly extract the root.

Each extraction:

```
O(log n)
```

Top K:

```
O(k log n)
```

This is why heaps are ideal for Top-K interview problems.

---

# Complexity Comparison

Data Structure Find Max Insert

---

Unsorted Array O(n) O(1)  
Sorted Array O(1) O(n)  
Linked List O(n) O(1)*  
Balanced BST O(log n) O(log n)  
Heap O(1) (Peek) O(log n)

*O(1) only if the insertion node is already known.

---

# Interview Takeaways

- Heap is **not** a sorted data structure.
    
- Heap maintains **partial ordering**.
    
- BST maintains **complete ordering**.
    
- Root always contains the minimum or maximum.
    
- Top-K is solved using repeated heap extraction.
    
- Heap is the standard implementation of a Priority Queue.
    

---

# Questions Answered So Far

### Why is sorted array insertion O(n)?

Finding the position is O(log n), but shifting elements is O(n), which  
dominates.

### Why is linked list insertion sometimes O(1) and sometimes O(n)?

- Given node → O(1)
    
- Search + Insert → O(n)
    

### What is a BST?

A Binary Search Tree where every node satisfies:

```
Left < Root < Right
```

### Does Heap only guarantee the root?

Yes. Only the root is guaranteed to be the minimum or maximum.

### How do we get Top-K?

Repeatedly extract the root.

Time:

```
O(k log n)
```

---

# Next Session

We will derive:

1. Why a Heap **must** be a Complete Binary Tree.
    
2. Why pointers are unnecessary.
    
3. Why Heap is stored in an array.
    
4. Parent/Child index formulas from first principles.
    
5. Heapify intuition.


===============================

# Heap Handbook - Session 2.1 Addendum

## 1. Rotation

A rotation is a small restructuring operation used in self-balancing  
Binary Search Trees.

Before:

```
    30
   /
 20
/
10
```

After a right rotation:

```
   20
  /  \
10   30
```

The sorted order is preserved. Only the shape changes.

---

## 2. Balancing Algorithm

A balancing algorithm checks if the tree has become too skewed.

If yes, it performs one or more rotations to reduce the height.

Heap does **not** use balancing algorithms.

---

## 3. Binary Tree vs BST vs Heap

```
Tree
└── Binary Tree
    ├── Binary Search Tree (BST)
    └── Heap
```

### Binary Tree

- At most two children.
    
- No ordering rule.
    

### Binary Search Tree

- Binary Tree.
    
- Left < Root < Right.
    

### Heap

- Binary Tree.
    
- Complete Binary Tree (shape property).
    
- Parent >= Children (Max Heap) or Parent <= Children (Min Heap).
    

A Heap is **not** a BST.

---

## 4. Why Learn It as a Tree if We Store It in an Array?

The algorithm thinks in terms of parent and child relationships.

The computer stores it in an array because a Complete Binary Tree has a  
predictable layout.

Tree = logical model.

Array = physical representation.

Next session proves why this mapping works.


==============================================

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


======================================


# Heap Handbook – Session 2.2 (Addendum)
## Topic: Why Array Instead of a Pointer-Based Tree?

---

# Question

If Heap is conceptually a tree, why don't we simply implement it using the normal tree structure?

```java
class Node {
    int value;
    Node left;
    Node right;
}
```

Why do we store it in an array instead?

---

# Important Answer

A Heap **can** be implemented using tree nodes.

There is nothing mathematically wrong with doing so.

However, engineers choose an array because it is **more efficient** for a Complete Binary Tree.

The reason is not that arrays are always better.

The reason is that **Heap has a very special shape**.

---

# Array vs Tree

Neither data structure is universally better.

Each is designed for different purposes.

## Array

Advantages

- O(1) random access
- Excellent cache locality
- Very little memory overhead

Disadvantages

- Insert/Delete in the middle is expensive
- Requires contiguous memory

---

## Pointer-Based Tree

Advantages

- Flexible structure
- Easy to grow dynamically
- No requirement for contiguous memory

Disadvantages

- Every node stores extra pointers
- Higher memory usage
- Poor cache locality because nodes may be scattered in memory

---

# Can Heap Be Implemented Using Nodes?

Yes.

Example:

```java
class Node {
    int value;
    Node left;
    Node right;
}
```

This would still satisfy the Heap Property.

So why doesn't everyone implement Heap like this?

Because the pointers provide **no additional information**.

---

# The Key Observation

A Heap is always a **Complete Binary Tree**.

Example:

```
        A
      /   \
     B     C
    / \   / \
   D  E  F  G
```

The position of every node is already predictable.

Therefore, storing pointers is redundant.

Instead of storing:

- A.left → B
- A.right → C

we can calculate these relationships directly from the array index.

---

# Pointer vs Formula

Using Tree Nodes:

```
node.left
node.right
```

Using Array:

```
Left Child  = 2i + 1
Right Child = 2i + 2
Parent      = (i - 1) / 2
```

Both approaches give O(1) navigation.

The array simply avoids storing unnecessary pointers.

---

# Memory Comparison

Pointer-Based Node

```
Value
Left Pointer
Right Pointer
```

Every node stores extra information.

Array

```
Value
```

Only the values are stored.

This saves a significant amount of memory for large heaps.

---

# Cache Locality

Array Memory

```
100 90 80 70 60 50
```

All elements are stored next to each other.

The CPU cache works very efficiently.

---

Pointer-Based Tree

```
100 -> Address A

90  -> Address X

80  -> Address P

70  -> Address M
```

Nodes may be located anywhere in memory.

The CPU must jump between memory locations, making traversal slower.

---

# Engineering Decision

The reasoning was:

1. We need a Priority Queue.
2. We need a short tree.
3. Therefore choose a Complete Binary Tree.
4. A Complete Binary Tree has a predictable layout.
5. Therefore pointers become unnecessary.
6. Store the Heap in an array.

Notice that the implementation follows naturally from the mathematical property.

It was **not** an arbitrary design choice.

---

# Interview Answer

**Q. Why is a Heap implemented using an array instead of tree nodes?**

Because a Heap is always a Complete Binary Tree. The position of every node is predictable, so parent-child relationships can be computed using indices. This removes the need for pointers, reduces memory usage, improves CPU cache locality, and still allows O(1) navigation between parent and child.

---

# Key Takeaways

- Heap is conceptually a tree.
- Heap is physically stored as an array.
- Pointer-based implementation is valid but inefficient.
- Arrays remove redundant pointers.
- Complete Binary Tree property makes array representation possible.
- The array implementation is an engineering optimization, not a mathematical requirement.



=======================================