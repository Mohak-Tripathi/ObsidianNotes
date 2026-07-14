# Trees — DSA Revision Notes

_Striver A2Z/SDE — Tree section. Language: Python. Built once, reread forever._

---

## 0. The Spine (read this first, every pass, until it's automatic)

### 0.1 Recursive Traversals

▸ **CRUX** — you know these. Only writing them so every later pattern can say "standard recursive traversal" without re-deriving.

```python
def preorder(root, res):
    if not root: return
    res.append(root.val)
    preorder(root.left, res)
    preorder(root.right, res)

def inorder(root, res):
    if not root: return
    inorder(root.left, res)
    res.append(root.val)
    inorder(root.right, res)

def postorder(root, res):
    if not root: return
    postorder(root.left, res)
    postorder(root.right, res)
    res.append(root.val)
```

N-ary version: replace `root.left`/`root.right` with a loop over `root.children or []`.

### 0.2 Iterative Traversals (interview-standard — asked as a follow-up constantly: "can you do it without recursion?")

▸ **CRUX**

**Preorder (1 stack)** — push right before left, so left pops first:

```python
def preorder_iter(root):
    if not root: return []
    res, stack = [], [root]
    while stack:
        node = stack.pop()
        res.append(node.val)
        if node.right: stack.append(node.right)
        if node.left: stack.append(node.left)
    return res
```

**Inorder (1 stack, curr pointer)** — the one pattern to actually memorize by hand:

```python
def inorder_iter(root):
    res, stack, curr = [], [], root
    while stack or curr:
        while curr:
            stack.append(curr)
            curr = curr.left
        curr = stack.pop()
        res.append(curr.val)
        curr = curr.right
    return res
```

**My solved version** (same algorithm, `while True` + `break` instead of `while stack or curr` — functionally identical):

```python
def inorderTraversal(self, root) -> List[int]:
    if root is None:
        return []

    stack = []
    inorder = []
    node = root

    while True:
        if node:
            stack.append(node)
            node = node.left
        else:
            if len(stack) == 0:
                break
            node = stack.pop()
            inorder.append(node.val)
            node = node.right

    return inorder
```

**Gotcha 0.2-B — `curr` has two distinct roles, not one continuous pointer. This is the trap.**

- While the inner `while curr:` loop runs, `curr` is a **descending explorer** — diving into unvisited left subtrees, pushing itself first because it can't be printed yet (its own left side isn't done). Same shape as `cur = cur.next` in a linked list, purely walking down.
- The moment `curr` becomes `None`, that explorer is **dead** — nothing left to descend into on this branch.
- `curr = stack.pop()` does **not** resurrect or continue the dead explorer. It recovers a completely different node — the most recently deferred **ancestor** whose left subtree just finished — prints it, then pivots to explore _that ancestor's right subtree_ via `curr = curr.right`.
- **WRONG mental model**: "curr just keeps moving forward like one continuous pointer the whole time."
- **CORRECT mental model**: curr = descending explorer _before_ it hits None; curr = popped-ancestor's-right-subtree-root _after_ the pop. Two different jobs sharing one variable name.
- **Trace** — tree `2(left=1, right=3)`:
    
    ```
    curr=2     -> push 2, curr=1              stack=[2]curr=1     -> push 1, curr=1.left=None    stack=[2,1]curr=None  -> pop 1, print 1, curr=1.right=None   stack=[2]curr=None  -> pop 2, print 2, curr=2.right=3      stack=[]curr=3     -> push 3, curr=3.left=None    stack=[3]curr=None  -> pop 3, print 3, curr=3.right=None   stack=[]curr=None, stack empty -> loop ends.  result=[1,2,3]
    ```
    
    At line 3: `curr` was `1`, then died to `None` inside the inner loop. The pop does **not** bring "1" back as a continuation — it's popped fresh as an ancestor to print, disconnected from curr's prior dead state.

**Gotcha 0.2-C — initial state is structurally different from preorder, don't copy that habit over.**

- Preorder starts with `stack = [root]` — root goes **straight into the stack**, because preorder prints on pop immediately; there's no deferral, so no need for a separate "current" variable at all.
- Inorder starts with `stack = []` and a **separate** `node`/`curr` variable set to root — root is deliberately kept _out_ of the stack until the descending loop pushes it. This is because inorder can never print a node the instant it's seen; the leftmost node must be found first. If you reflexively pushed root into the stack up front (preorder habit), you'd either double-push it or break the "push-then-descend" sequence that makes the algorithm correct.
- **Rule to keep**: preorder's initial container = the stack. Inorder's (and postorder's) initial container = a pointer/cursor variable; the stack starts empty and fills only as the traversal descends.

**Postorder (2 stacks — the interview-safe version; 1-stack postorder is fiddly and low-yield, skip it)**:

```python
def postorder_iter(root):
    if not root: return []
    s1, s2 = [root], []
    while s1:
        node = s1.pop()
        s2.append(node.val)
        if node.left: s1.append(node.left)
        if node.right: s1.append(node.right)
    return s2[::-1]
```

▹ **WHY — build it from a trivial example first, not the general case.**

Postorder is the odd one out: Preorder (Root L R) prints on sight — easy for a stack, which naturally hands you the most recent thing first. Postorder (L R **Root**) needs the root printed _last_, after both children are fully done — a plain stack has no memory of "have both children finished yet," which is exactly why 1-stack postorder needs an extra marker and is fiddly (skipped here on purpose).

**The trick, on the smallest possible tree** — `1(left=2, right=3)`:

- `st1` pops `1`, pushes children **left first then right** (`2`, then `3`) → right sits on top → pops next.
- Order produced: `1, 3, 2` — that's **Root, Right, Left**.
- Reverse it: `2, 3, 1` — that's **Left, Right, Root** = postorder. Done, for this tiny tree that's the whole idea.

**The one-line mnemonic**: _mirror preorder (swap L/R) → reverse it → you get postorder._

**Why push left before right (the part people flip by accident)**: pushing left-then-right puts **right on top**, so right pops first, giving Root-Right-Left. If you pushed right-then-left instead, left would pop first, giving Root-Left-Right (=preorder again) — reversing _that_ gives Right-Left-Root, which is wrong. The push order is the entire lever controlling which mirrored order you generate.

**Why it still works once the tree has depth** (not just the 2-node case): if st1's full output is `Root + (right subtree in Root-R-L order) + (left subtree in Root-R-L order)`, reversing the _whole_ sequence gives `reverse(left part) + reverse(right part) + Root` — and since each subtree's part is itself in Root-R-L order, reversing it turns that part into postorder too, recursively, one level down. One top-level reversal fixes every subtree at once.

`st2` is purely the reversal device — a stack reverses whatever you feed it via LIFO, same effect as collecting into a list and doing `[::-1]` at the end (which is what `s2[::-1]` above does directly, skipping the second stack).

**0.2.1 — Stack (DFS) vs Queue (BFS): the confusion to kill permanently** ▸ **CRUX** — Iterative preorder (this section) and Level Order (Pattern 3) look superficially similar — both are "pop, print, push children" loops — but they're structurally opposite:

||Iterative Preorder (DFS)|Level Order (BFS)|
|---|---|---|
|Container|**Stack** (LIFO)|**Queue** (FIFO)|
|Explores|one branch fully deep, then backtracks|one full level, then the next|
|Inner `for _ in range(len(q))` loop|**not needed** — no concept of "level" to snapshot|**required** — snapshots level boundary before children get mixed in|
|Push order matters because|right must be _under_ left so left pops next|doesn't matter, order within a level is push-order = pop-order (FIFO preserves it)|

▹ **WHY** — the `for` loop in BFS exists purely to draw a boundary around "this level" before its children start entering the same queue. DFS has no such boundary to draw — depth, not breadth, is the axis being walked, so nothing needs snapshotting; you just keep popping until the stack empties.

**Gotcha 0.2-A** — Preorder pushes right-then-left (so left pops first). Postorder's s1 pushes left-then-right (so right pops first, since we're building the reverse). If you swap these, you silently get the wrong order with no crash — dangerous because it _looks_ right on symmetric test trees.

### 0.3 The O(h) Space Law

▸ **CRUX** — Time = O(n) always, regardless of traversal order or shape (every node visited once, O(1) work each). **Space = O(h)**, h = tree height:

- Balanced → h = O(log n)
- Skewed → h = O(n)

Output array doesn't count as auxiliary space — it's the required return value.

▹ **WHY** — peak stack depth = length of the **current root-to-node path**, not total nodes visited over the run. A balanced tree visits all n nodes eventually, but the stack unwinds and repushes between branches, so peak depth never exceeds ~log n. A skewed tree has nothing to unwind until the single leaf — peak depth = n. (10 levels ≈ 1024 nodes, 20 ≈ 1M, 30 ≈ 1B — use this to sanity-check height claims fast in an interview.)

### 0.4 Tree Taxonomy (only as a lens for reasoning about h — don't memorize as trivia)

|Type|Definition|h implication|
|---|---|---|
|Full|every node has 0 or 2 children|no guarantee on h|
|Complete|all levels full except possibly last, filled left→right|h = O(log n), guaranteed|
|Perfect|all internal nodes have 2 children, all leaves same level|h = log₂(n+1) − 1 exactly|
|Balanced|height diff of subtrees ≤ 1 at every node|h = O(log n)|
|Skewed|each node has ≤1 child|h = O(n)|

### 0.5 One-Pass All-Three Traversal (State-Tagged Stack)

▸ **CRUX — trigger**: "give me preorder, inorder, and postorder in a single traversal" — rare but a real ask, and a clean test of whether you actually understand what each traversal's "visit point" means relative to recursing into children.

**Core template** — push `(node, state)`, state = which visit this pop represents:

```python
def all_three(root):
    preorder, inorder, postorder = [], [], []
    if not root: return preorder, inorder, postorder
    stack = [(root, 1)]
    while stack:
        node, state = stack.pop()
        if state == 1:
            preorder.append(node.val)
            stack.append((node, 2))                 # re-schedule self for inorder visit
            if node.left: stack.append((node.left, 1))
        elif state == 2:
            inorder.append(node.val)
            stack.append((node, 3))                 # re-schedule self for postorder visit
            if node.right: stack.append((node.right, 1))
        else:
            postorder.append(node.val)
    return preorder, inorder, postorder
```

- **State 1** = "preorder visit due, haven't recursed left yet."
- **State 2** = "preorder done + left subtree done, inorder visit due, haven't recursed right yet."
- **State 3** = "everything below is done, postorder visit due."

Re-pushing the _same node_ with an incremented state is a manual substitute for "return control to this stack frame later" — the thing a real call stack gives you for free in recursion.

**Gotcha 0.5-A — Problem**: pushing `(node.left, 2)` / `(node.right, 3)` instead of `(node, 2)` / `(node, 3)`. This silently swaps in a _child's identity_ where the algorithm needs to resume work on the _current node_. Symptom: preorder comes out right (state-1 logic is untouched), but inorder/postorder come out wrong, and any leaf lacking that child crashes on `node.data`/`node.val` when the pushed `None` gets popped and treated as a real node. **Fix**: always re-push `(node, next_state)` — never a child — when deferring further work on the current node.

Time O(n) (each node pushed exactly 3 times, O(1) work per pop). Space: still O(h) — same law as Section 0.3, since at any moment the stack holds one pending re-scheduled entry per ancestor on the current path plus one live child, not one entry per total node.

**Anchor problems**: All-in-one traversal (single-pass preorder+inorder+postorder) — Striver/GfG variant.

---

## 1. Postorder Bottom-Up Return Value

_The single highest-yield tree pattern. Children return an answer → parent combines → returns up._

▸ **CRUX — trigger phrases**: "height", "diameter", "balanced", "max path sum", "children sum property", "largest BST in a binary tree" — anything where a subtree needs to report something about itself to its parent.

**Core template:**

```python
def solve(node):
    if not node:
        return BASE_CASE
    left = solve(node.left)
    right = solve(node.right)
    # combine left, right, node.val -> possibly update a global/nonlocal answer
    return VALUE_TO_RETURN_TO_PARENT
```

**Gotcha 1-A — the return value ≠ the recorded answer.** This is where most candidates get rejected on Diameter / Max Path Sum.

||Diameter|Max Path Sum|
|---|---|---|
|**Returns to parent**|height of subtree|max single-branch sum through this node (can't fork)|
|**Records/updates globally**|left_height + right_height (a path _through_ this node, which can't be returned upward without breaking the recursion)|left_gain + right_gain + node.val (a path that forks at this node)|

WRONG (diameter):

```python
def diameter(node):
    if not node: return 0
    l = diameter(node.left)
    r = diameter(node.right)
    return max(l, r, l + r + 1)   # BUG: returning a forked path upward
```

CORRECT:

```python
def diameter(root):
    ans = 0
    def height(node):
        nonlocal ans
        if not node: return 0
        l = height(node.left)
        r = height(node.right)
        ans = max(ans, l + r)          # forked path recorded here, never returned
        return 1 + max(l, r)           # only the height goes up
    height(root)
    return ans
```

▹ **WHY** — a "path through this node" uses both children at once, so it cannot be extended further up (a path can't branch twice). Returning it upward would let the parent treat it as extendable, silently producing wrong answers on trees with ≥3 levels — this bug passes trivial 2-level test cases and fails only on deeper ones, which is exactly why it slips through in interviews.

**Anchor problems**: **104. Maximum Depth of Binary Tree** ✓solved · **110. Balanced Binary Tree** ✓solved · **559. Maximum Depth of N-ary Tree** ✓solved (N-ary generalization — loop over `root.children or []` instead of two fixed branches; watch the `children or []` guard, `children` can be `None` on a leaf) · Diameter of Binary Tree · Maximum Path Sum · Children Sum Property · Largest BST Subtree in BT.

---

## 2. Top-Down Parameter Passing (Preorder)

_Parent hands state DOWN. Contrast with #1: here you push info down instead of pulling an answer up._

▸ **CRUX — trigger phrases**: "root-to-leaf", "path sum equals target", "sum of root-to-leaf numbers", "validate BST" (bounds version).

**Core template:**

```python
def solve(node, state):
    if not node: return
    state = update(state, node)      # e.g. running sum, path list, (low, high) bounds
    if is_leaf(node):
        record(state)
        return
    solve(node.left, state)
    solve(node.right, state)
```

**Validate BST bounds (classic top-down):**

```python
def isValidBST(node, low=float('-inf'), high=float('inf')):
    if not node: return True
    if not (low < node.val < high): return False
    return isValidBST(node.left, low, node.val) and isValidBST(node.right, node.val, high)
```

**Gotcha 2-A** — checking only `node.left.val < node.val < node.right.val` is a rejection-tier bug: it ignores that _every_ node in the left subtree must be less than an ancestor further up, not just the immediate parent. Bounds must be threaded down, not compared locally.

**Comparison table — Pattern 1 vs Pattern 2:**

||Pattern 1 (bottom-up)|Pattern 2 (top-down)|
|---|---|---|
|Data flow|children → parent|parent → children|
|Use when|answer depends on subtree aggregate|answer depends on ancestor path|
|Typical return|a computed value|usually `None`, records via list/nonlocal|

**Anchor problems**: Path Sum I/II · Root to Leaf paths · Sum Root to Leaf Numbers · Validate BST.

---

## 3. Level-Order / BFS Family

▸ **CRUX — trigger**: "level", "level order", "zigzag", "view" (top/bottom/left/right), "average of levels", "max width".

**Core template — the level-snapshot idiom** (memorize the `for _ in range(len(q))` line, it's the whole pattern):

```python
from collections import deque
def levelOrder(root):
    res, q = [], deque([root] if root else [])
    while q:
        level = []
        for _ in range(len(q)):          # snapshot size BEFORE mutating q
            node = q.popleft()
            level.append(node.val)
            if node.left: q.append(node.left)
            if node.right: q.append(node.right)
        res.append(level)
    return res
```

**Gotcha 3-A — Problem**: using `while q` with a live `len(q)` inside the loop → levels bleed into each other. **Fix**: capture `len(q)` into a variable/`range()` _before_ the inner loop starts appending children.

**Gotcha 3-B — space complexity here is NOT the O(h) law from Section 0.3, and mixing the two up is a real interview tell.**

- Recursive/DFS traversals (Sections 0.1–0.2, Patterns 1–2): space = O(h) — call stack depth = current root-to-node path length.
    
- BFS/queue traversal (any level-order problem, this pattern): space = **O(w)**, w = width of the widest level, not O(h). The queue holds an entire level's worth of nodes at once, not a path. **w depends on tree shape, it isn't a fixed fraction of n:**
    
    - Perfect/complete tree → last level ≈ n/2 nodes → w = O(n), the worst case.
    - Skewed tree (one child per node) → every level has exactly 1 node → w = O(1) — cheaper than recursion's O(n) call stack on the same tree. Worth sitting with: BFS can beat DFS on space for degenerate shapes, the reverse of the usual intuition.
- **Why "n/2" is linear, not exponential — the trap inside the trap.** The 2^depth doubling (1024 nodes by level 10, from Section 0.3) is exponential _in depth_, not in n. Complexity is always stated as a function of n, and n already bakes that exponential relationship in — for a perfect tree, n = 2^(h+1)−1, so the last level (2^h nodes) works out to **≈ n/2, a plain linear fraction of n**. Don't read "n/2 nodes in the last level" as evidence of exponential space — it's O(n) with a constant of ~1/2, nothing more exotic.
    
    **Worked example — perfect tree, height 5 (levels 0–5, 6 levels total):**
    
    |Level|Nodes|
    |---|---|
    |0 (root)|1|
    |1|2|
    |2|4|
    |3|8|
    |4|16|
    |5 (last)|32|
    
    Total n = 1+2+4+8+16+32 = **63**. Last level alone = **32**. Everything _above_ the last level combined (levels 0–4) = 1+2+4+8+16 = **31**. Notice: **32 = 31 + 1** — the last level is just one more than the sum of every level before it, combined. This falls straight out of geometric doubling: 2^h = (2^0+2^1+...+2^(h-1)) + 1, always. So last level (32) vs total n (63) → 32 ≈ n/2 (n/2 = 31.5, off by the same rounding "+1"), and Big-O discards that rounding anyway.
    
    Why this is the space complexity: right when BFS finishes popping level 4 and starts level 5, the queue holds all 32 last-level nodes at once — none popped yet, all already pushed. That peak **is** the space bound, and it's ≈ n/2 → O(n).
    
    **Interview one-liner**: _"In the worst case — a complete or perfect binary tree — the last level alone holds roughly half of all nodes, because each level doubles the one before it. So the queue's peak size is O(n), even though the tree's height is only O(log n)."_
    
- **The trap that started this**: don't paste "O(N), N/2 nodes in queue" as the space complexity for a _recursive_ solution to the same problem (e.g. Max Depth solved recursively) — that reasoning is specific to the BFS/queue approach and has nothing to do with call-stack depth. If your code doesn't use a queue, this justification doesn't apply to it, no matter how correct the fact is in general.
    

**Max width — indexing trick:** Assign each node an index (root=0, left=2i+1, right=2i+2). Width of a level = last_index − first_index + 1. **Gotcha 3-C** — raw indices overflow for skewed/deep trees. Fix: re-base index to 0 at the start of each level (`idx - first_idx_of_level`).

**Right/Left View — two valid approaches, pick by context:**

|Approach|How|When better|
|---|---|---|
|BFS level order|take last (or first) element of each level list|more intuitive, easier to explain live|
|DFS (preorder variant)|recurse right-then-left, record first node seen at each depth|O(h) space instead of O(width) — better if asked to optimize|

**Anchor problems**: Level Order Traversal · Zigzag Traversal · Right/Left View · Top View · Bottom View (also #4) · Average of Levels · Maximum Width of Binary Tree.

---

## 4. Coordinate/Hash-Indexed Traversal

_Assign each node a synthetic coordinate, bucket into a map, read out sorted._

▸ **CRUX — trigger**: "vertical order", "top view", "bottom view" (when done via coordinates rather than BFS-first-seen).

**Core template:**

```python
from collections import defaultdict, deque
def verticalOrder(root):
    col_map = defaultdict(list)   # col -> list of (row, val)
    q = deque([(root, 0, 0)])     # node, col, row
    while q:
        node, col, row = q.popleft()
        col_map[col].append((row, node.val))
        if node.left: q.append((node.left, col - 1, row + 1))
        if node.right: q.append((node.right, col + 1, row + 1))
    for col in sorted(col_map):
        col_map[col].sort(key=lambda x: (x[0], x[1]))  # sort by row, then val on tie
        yield [v for _, v in col_map[col]]
```

**Gotcha 4-A — the entire difficulty of this pattern is the tie-break.** Same column AND same row (two nodes land at the same coordinate) → must sort by **value** as the tiebreaker, or the answer is nondeterministic and wrong. This is the detail interviewers probe on directly.

**Top view vs Bottom view vs Vertical order** — same coordinate system, different aggregation:

||Aggregation rule per column|
|---|---|
|Vertical order|keep all nodes, sorted by row then value|
|Top view|keep only the **first** node encountered per column (BFS order guarantees first = topmost)|
|Bottom view|keep the **last** node encountered per column (later BFS entries overwrite)|

**Anchor problems**: Vertical Order Traversal · Top View of BT · Bottom View of BT.

---

## 5. Two-Node Relationship / LCA Family

▸ **CRUX — trigger**: "lowest common ancestor", "distance between two nodes", "nodes at distance K", "time to burn tree" (fire spreading from a target node).

**LCA (binary tree, no parent pointers):**

```python
def lca(root, p, q):
    if not root or root == p or root == q:
        return root
    left = lca(root.left, p, q)
    right = lca(root.right, p, q)
    if left and right: return root      # p and q on different sides -> root is LCA
    return left or right
```

**Gotcha 5-A — Problem**: candidates try to solve "distance between two nodes" or "nodes at distance K" by adapting LCA recursion directly, and it gets messy fast. **Fix — the actual crux of this pattern**: build a parent-pointer map with one BFS/DFS pass, then treat the tree as an **undirected graph** and BFS from the target node. This single conversion unlocks three problems at once (nodes at distance K, burn time, distance between two nodes) instead of needing three bespoke recursions.

```python
def build_parent_map(root):
    parent = {}
    q = deque([root])
    while q:
        node = q.popleft()
        for child in (node.left, node.right):
            if child:
                parent[child] = node
                q.append(child)
    return parent

def nodes_at_distance_k(root, target, k):
    parent = build_parent_map(root)
    visited, q, dist = {target}, deque([target]), 0
    while q and dist < k:
        for _ in range(len(q)):
            node = q.popleft()
            for nxt in (node.left, node.right, parent.get(node)):
                if nxt and nxt not in visited:
                    visited.add(nxt)
                    q.append(nxt)
        dist += 1
    return [node.val for node in q]
```

▹ **WHY** — a tree has no "up" pointer natively, so distance-based problems (which need to move in _any_ direction from a node) are awkward in pure recursion. Converting to a graph via a parent map removes the directionality constraint entirely — it's the same idiom as "min time to rot all oranges" BFS, just on a tree.

**Anchor problems**: LCA of Binary Tree · Nodes at Distance K · Minimum Time to Burn a Binary Tree · Distance Between Two Nodes.

---

## 6. Structural Comparison & Symmetry

▸ **CRUX — trigger**: "same tree", "symmetric", "subtree of another tree", "invert", "univalued tree" — any problem comparing two trees or a tree against its mirror.

**Core template — the `f(a, b)` two-pointer recursion:**

```python
def same(a, b):
    if not a and not b: return True
    if not a or not b: return False       # exactly one is None -> mismatch
    return a.val == b.val and same(a.left, b.left) and same(a.right, b.right)
```

**Symmetric tree** = `same(root.left, mirror-compared root.right)`:

```python
def isSymmetric(root):
    def mirror(a, b):
        if not a and not b: return True
        if not a or not b: return False
        return a.val == b.val and mirror(a.left, b.right) and mirror(a.right, b.left)
    return mirror(root, root)
```

**Gotcha 6-A — the null-handling truth table everyone botches:**

|a|b|Correct result|Common bug|
|---|---|---|---|
|None|None|True|—|
|None|Node|False|forgetting this branch → crash on `a.val`|
|Node|None|False|same|
|Node|Node|recurse on `.val` equality|comparing before null-checking → AttributeError|

Always check both-None, then either-None, **before** touching `.val`.

**Anchor problems**: Same Tree · Symmetric Tree · Subtree of Another Tree · Invert Binary Tree · Univalued Binary Tree.

---

## 7. Tree Construction from Traversals

▸ **CRUX — trigger**: "construct tree from preorder and inorder", "from postorder and inorder", "construct BST from preorder", "serialize/deserialize".

**Core idea**: one traversal tells you the **root** (first of preorder, last of postorder); inorder tells you the **split** between left and right subtrees.

```python
def buildTree(preorder, inorder):
    idx_map = {val: i for i, val in enumerate(inorder)}   # O(1) root-splitting
    self_pre_idx = [0]
    def build(l, r):
        if l > r: return None
        root_val = preorder[self_pre_idx[0]]
        self_pre_idx[0] += 1
        root = TreeNode(root_val)
        mid = idx_map[root_val]
        root.left = build(l, mid - 1)
        root.right = build(mid + 1, r)
        return root
    return build(0, len(inorder) - 1)
```

**Gotcha 7-A** — without the hashmap, finding `mid` via a linear scan of inorder makes this O(n²). The hashmap is not an optimization, it's the expected solution.

**Why preorder+postorder alone is insufficient** (but preorder+inorder or postorder+inorder is): ▹ **WHY** — preorder+postorder can't distinguish a node with only-left-child vs only-right-child (both traversals look identical in that case) — the tree isn't uniquely reconstructible unless the tree is guaranteed full (every node has 0 or 2 children). Inorder breaks this ambiguity because it separates left-subtree-values from right-subtree-values explicitly.

**Anchor problems**: Construct BT from Preorder & Inorder · Construct BT from Postorder & Inorder · Construct BST from Preorder · Serialize and Deserialize Binary Tree.

---

## 8. In-Place Restructuring

▸ **CRUX — trigger**: "flatten to linked list", "O(1) space traversal", "without recursion or stack" — this is the pattern that breaks the O(h) space law from Section 0.

**Flatten BT to Linked List (reverse-postorder trick):**

```python
def flatten(root):
    def rev_postorder(node, prev=[None]):
        if not node: return
        rev_postorder(node.right, prev)
        rev_postorder(node.left, prev)
        node.right = prev[0]
        node.left = None
        prev[0] = node
    rev_postorder(root)
```

▹ **WHY** — visiting right, then left, then node (reverse of postorder) means each node is processed _after_ its correct successor in the final flattened list has already been linked — so you can wire `node.right = prev` in one pass with O(h) space, no extra list.

**Morris Inorder Traversal — O(1) space, the interviewer's favorite follow-up to "can you avoid the stack entirely?"**

```python
def morris_inorder(root):
    res, curr = [], root
    while curr:
        if not curr.left:
            res.append(curr.val)
            curr = curr.right
        else:
            pred = curr.left
            while pred.right and pred.right != curr:
                pred = pred.right
            if not pred.right:
                pred.right = curr        # thread: temporarily link back
                curr = curr.left
            else:
                pred.right = None        # unthread: restore tree
                res.append(curr.val)
                curr = curr.right
    return res
```

**Gotcha 8-A — Problem**: forgetting to unthread (`pred.right = None`) leaves the tree permanently corrupted with a cycle — looks correct on the current traversal, silently breaks any future traversal of the same tree. **Fix**: every thread you create must be removed exactly once, in the `else` branch, before moving on.

**Anchor problems**: Flatten Binary Tree to Linked List · Morris Inorder Traversal · Morris Preorder Traversal.

---

## 9. Counting / Property Exploitation

▸ **CRUX — trigger**: "complete binary tree", "count total nodes" — where a full O(n) traversal is a rejection because the problem states a guaranteed shape you're expected to exploit.

**Count Nodes in Complete Binary Tree — O(log²n):**

```python
def countNodes(root):
    def height(node, go_left):
        h = 0
        while node:
            h += 1
            node = node.left if go_left else node.right
        return h
    if not root: return 0
    lh, rh = height(root, True), height(root, False)
    if lh == rh:
        return (1 << lh) - 1              # perfect subtree, count via formula
    return 1 + countNodes(root.left) + countNodes(root.right)
```

▹ **WHY** — a complete tree guarantees that if left-height == right-height, that subtree is perfect (count = 2^h − 1, O(1)). Otherwise recurse — but each recursive call does O(log n) height work, and there are O(log n) levels of recursion, giving O(log²n) instead of O(n). Naive traversal here signals to the interviewer you didn't register the "complete" constraint as exploitable — it's a red flag at Google/Meta bar specifically because this problem exists to test exactly that.

**Anchor problems**: Count Complete Tree Nodes.

---

## My Learnings (Personal — Added as I Solve)

**#1 — N-ary Preorder, type-error bug (seeded from prior session)**

- **Bug**: original code passed `node.val` instead of `node` into the recursive call.
- **Why it matters**: recursion needs the _node object_ to keep traversing children; passing `.val` (a leaf value, e.g. an int) breaks the recursive contract — the next call tries to call `.children` on an int and crashes. Easy to miss because for a single-level test tree the type mismatch doesn't surface until you hit a real child.
- **WRONG**:
    
    ```python
    def preorder(node, res):    res.append(node.val)    for child in node.children or []:        preorder(child.val, res)   # BUG
    ```
    
- **CORRECT**:
    
    ```python
    def preorder(node, res):    res.append(node.val)    for child in node.children or []:        preorder(child, res)       # pass the node, not node.val
    ```
    
- **Fix pattern locked in**: `node.children or []` — safely handles both `None` and `[]` without an extra `if` guard. Reuse this idiom everywhere N-ary children are iterated.
- **Trace**: root(1) → children [2,3]. Call `preorder(root)` → appends 1 → loop hits child `2` (a TreeNode) → WRONG version calls `preorder(2.val, res)` = `preorder(2, res)` where `2` is now a bare int → next line `for child in node.children` → `AttributeError: 'int' object has no attribute 'children'`. CORRECT version passes the node object `2` itself, so `.children` resolves fine and recursion continues into its children safely.

**#2 — Iterative Inorder: `node` has two distinct roles, not one continuous pointer**

- **Confusion**: felt like `node` should behave as one continuous cursor (`cur = cur.next` style), the same way it's used walking left. But in the `else` branch, `node = stack.pop()` doesn't continue anything — it's a jump backward to a stashed ancestor, not a forward step.
- **Why it matters**: `if node:` uses node as a _descending explorer_ (diving into unvisited left subtrees, pushing itself first since it can't be printed yet). The moment `node` becomes `None`, that explorer is dead — there's nothing left to descend into. `else:` recovers a **different node entirely** (the most recently deferred ancestor whose left side just finished) and pivots to explore _its_ right subtree. Treating these as the same "current position" is the exact confusion that causes people to write incorrect variants on first attempt.
- **WRONG mental model**: "node just keeps moving forward like a linked-list pointer the whole time."
- **CORRECT mental model**: node = descending explorer pre-null; node = popped-ancestor's-right-subtree-root post-null. Two jobs, not one.
- **Trace** — tree: `2(left=1, right=3)`:
    
    ```
    node=2            -> push 2, node=1            stack=[2]node=1            -> push 1, node=1.left=None   stack=[2,1]node=None         -> pop 1, print 1, node=1.right=None   stack=[2]node=None         -> pop 2, print 2, node=2.right=3       stack=[]node=3            -> push 3, node=3.left=None   stack=[3]node=None         -> pop 3, print 3, node=3.right=None    stack=[]node=None, stack empty -> break.  result=[1,2,3]
    ```
    
    Notice at step 3: node was `1`, then became `None` (dead explorer) — the `else` branch does NOT resurrect "1" as a continuation, it pops `1` fresh off the stack as an ancestor to print, unrelated to node's prior dead state.

**#3 — Max Depth: pasted BFS complexity analysis onto a recursive solution**

- **Confusion**: wrote a recursive (postorder bottom-up) solution but justified its space complexity as "O(N), N/2 nodes in queue" — that's the reasoning for a completely different, iterative BFS/queue-based solution to the same problem.
- **Why it matters**: complexity must be derived from the code you actually wrote, not from a related approach you've seen elsewhere. Recursive space = O(h) (call stack depth = current path length, per Section 0.3). BFS space = O(w) (widest level, since the queue holds a full level's worth of nodes at once) — for a perfect tree w ≈ n/2, giving O(n), even though h = O(log n) for that same tree. These are two different bounds on two different implementations of the same problem, not two ways of saying the same thing.
- **Also caught in this same solve**: an unused `maxi` parameter threaded through every recursive call, never read or updated — dead state, a real interview smell (signals uncertainty about what needs tracking, left uncleaned).
- **Rule to keep**: before stating Big-O, ask "what structure is actually growing in _my_ code — a call stack, or a queue?" That answer alone tells you whether you're in O(h) or O(w) territory.

_(Next entries added as you solve — paste your struggle point, I format it.)_

---

## Quick Recall Table

|Trigger phrase in problem|Reach for|
|---|---|
|"height", "balanced", "diameter", "max path sum"|Pattern 1 — Postorder bottom-up return|
|"children sum property", "largest BST subtree"|Pattern 1|
|"root-to-leaf path", "path sum == target"|Pattern 2 — Top-down parameter passing|
|"validate BST"|Pattern 2 (bounds threaded down)|
|"level order", "zigzag"|Pattern 3 — BFS level-snapshot|
|"max width of tree"|Pattern 3 (re-based indexing)|
|"left/right view"|Pattern 3 (BFS last-seen) or DFS variant — pick by space constraint|
|"vertical order traversal"|Pattern 4 — coordinate + hashmap, sort tie by value|
|"top view" / "bottom view"|Pattern 4 (first-seen vs last-seen per column)|
|"LCA"|Pattern 5 — recursive LCA|
|"distance between two nodes", "nodes at distance K", "burn time"|Pattern 5 — parent map + BFS-as-graph|
|"same tree", "symmetric", "subtree of", "invert"|Pattern 6 — `f(a,b)` two-pointer recursion|
|"construct tree from two traversals"|Pattern 7 — hashmap root-split|
|"serialize / deserialize"|Pattern 7|
|"flatten to linked list"|Pattern 8 — reverse-postorder threading|
|"O(1) space traversal", "no stack, no recursion"|Pattern 8 — Morris traversal|
|"complete binary tree" + "count nodes"|Pattern 9 — height-comparison exploit, O(log²n)|