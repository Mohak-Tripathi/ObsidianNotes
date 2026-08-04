
I like this approach much more than solving random Heap questions. We'll solve **patterns**, not individual problems. Once you master a pattern, dozens of LeetCode questions become easy.

Here's the roadmap I'd recommend for a FAANG interview.

---

# Pattern 1 — Top K / K-th Element (⭐⭐⭐⭐⭐ Highest Priority)

This is the foundation of Heap interviews.

|Order|LeetCode|Problem|
|---|--:|---|
|1|**215**|Kth Largest Element in an Array|
|2|**703**|Kth Largest Element in a Stream|
|3|**347**|Top K Frequent Elements|
|4|**692**|Top K Frequent Words|
|5|**973**|K Closest Points to Origin|
|6|**658**|Find K Closest Elements|

### Concepts you'll learn

- Fixed-size Min Heap
    
- When to use Min Heap vs Max Heap
    
- Keep only the best K elements
    
- Heap + HashMap
    

---

# Pattern 2 — Merge Multiple Sorted Structures

| Order | LeetCode | Problem                                                                                  |
| ----- | -------: | ---------------------------------------------------------------------------------------- |
| 1     |   **23** | Merge K Sorted Lists                                                                     |
| 2     |  **378** | Kth Smallest Element in a Sorted Matrix                                                  |
| 3     |  **632** | Smallest Range Covering Elements from K Lists  (HARDEST PROBLEM TILL NOW. Need revision) |
| 4     |  **373** | Find K Pairs with Smallest Sums                                                          |

### Concepts

- Multi-way merge
    
- Heap stores one candidate from each list
    
- Merge pattern
    

---

# Pattern 3 — Streaming / Two Heaps

|Order|LeetCode|Problem|
|---|--:|---|
|1|**295**|Find Median from Data Stream|
|2|**480**|Sliding Window Median|

### Concepts

- Max Heap + Min Heap
    
- Balance two heaps
    
- Running median
    

---

# Pattern 4 — Greedy + Heap

|Order|LeetCode|Problem|
|---|--:|---|
|1|**621**|Task Scheduler|
|2|**502**|IPO|
|3|**630**|Course Schedule III|
|4|**253**|Meeting Rooms II _(Premium, but excellent concept)_|
|5|**857**|Minimum Cost to Hire K Workers|

### Concepts

- Choose the best available option
    
- Dynamic optimization
    
- Greedy + Heap
    

---

# Pattern 5 — Heap Design & Advanced Applications

|Order|LeetCode|Problem|
|---|--:|---|
|1|**703**|Kth Largest Element in a Stream _(Design version)_|
|2|**355**|Design Twitter|
|3|**767**|Reorganize String|
|4|**1642**|Furthest Building You Can Reach|
|5|**2402**|Meeting Rooms III|

### Concepts

- Designing systems using heaps
    
- Event simulation
    
- Scheduling
    
- Priority-based processing
    

---

# ⭐ The Order I Recommend (FAANG Optimized)

This is the exact order I'd teach:

### Foundation

1. **215** — Kth Largest Element in an Array ⭐⭐⭐⭐⭐
    
2. **703** — Kth Largest Element in a Stream
    
3. **347** — Top K Frequent Elements
    
4. **973** — K Closest Points to Origin
    

---

### Merge Pattern

5. **23** — Merge K Sorted Lists ⭐⭐⭐⭐⭐
    
6. **378** — Kth Smallest Element in a Sorted Matrix
    
7. **373** — Find K Pairs with Smallest Sums
    

---

### Two Heaps

8. **295** — Find Median from Data Stream ⭐⭐⭐⭐⭐
    
9. **480** — Sliding Window Median
    

---

### Greedy + Heap

10. **621** — Task Scheduler
    
11. **502** — IPO
    
12. **630** — Course Schedule III
    

---

### Advanced

13. **767** — Reorganize String
    
14. **1642** — Furthest Building You Can Reach
    
15. **2402** — Meeting Rooms III
    

---

# 🎯 My recommendation

Don't solve all 15 immediately.

These **8 problems** are the highest return on investment for FAANG interviews:

1. ✅ **215** – Kth Largest Element in an Array
    
2. ✅ **347** – Top K Frequent Elements
    
3. ✅ **23** – Merge K Sorted Lists
    
4. ✅ **295** – Find Median from Data Stream
    
5. ✅ **621** – Task Scheduler
    
6. ✅ **502** – IPO
    
7. ✅ **973** – K Closest Points to Origin
    
8. ✅ **703** – Kth Largest Element in a Stream
    

If you deeply understand these eight, you'll recognize and solve many other Heap questions because they represent the core interview patterns.

I suggest we start with **LeetCode 215 – Kth Largest Element in an Array**. It teaches the single most important Heap insight in interviews:

> **Why do we use a Min Heap to find the Kth largest element instead of a Max Heap?**

That question changes how you think about Top K problems, and it's the perfect bridge from learning the data structure to applying it.