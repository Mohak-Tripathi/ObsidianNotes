

from textwrap import dedent
import pypandoc

md_text = dedent("""
# Heap Notes (FAANG Interview Prep)
**Course:** Striver A2Z DSA Sheet  
**Topic:** Heap  
**Session:** 1 (First Principles)

---

# Goal

Understand **why Heap was invented**, not just how to code it.

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
