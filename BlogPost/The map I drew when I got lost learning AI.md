
June 26, 2026·10 min read

![Four layers of the AI climb — domain depth, agentic systems, full-stack builder, specialist](https://mohaktripathi.com/assets/posts/the-map-i-drew-learning-ai-hero.png)

For a few weeks I'd been learning AI tooling the way you eat at a buffet with no plan. Claude Code. Cowork. Skills. Hooks. Subagents. LangChain, then LangGraph. Each one made sense on its own. Together they made a pile, not a picture. I could tell you what a subagent was. I couldn't tell you why I was learning it, or where it led.

I'm a systems thinker — I get twitchy using the parts before I understand the whole. So I stopped collecting tools and drew a map: where is all of this actually going, and where am I standing on it?

This post is that map, and the bet I'm making on it. I'll be straight about what kind of thing it is: a map of where a fast-moving field is heading is a forecast, not a fact. I'm not announcing the future. I'm telling you how I read it right now, and I'm putting the next five years of my own time behind that read. If I turn out to be wrong, you'll get the post where I say so.

## The map

When I sorted the pile, the tools weren't random. They sat at different heights of the same climb. I see four layers.

**Layer 1 — The specialist.** This is where most engineers start: you own one slice of the stack and hand work off at the boundary. A frontend developer who builds the interface but depends on someone else for the API. A backend developer who writes the service but never touches the database migrations. A mobile developer who ships the app but calls an endpoint someone else designed. The work is real, but it's a piece — you're a cog in a larger machine, and you can't ship anything alone.

**Layer 2 — The full-stack builder.** This is where I've spent the last few years. You can take a customer problem, break it into a solution, and ship the whole thing end to end: data model, backend, frontend, deploy, App Store, monitoring, the lot. That's what I did lately — a multi-tenant applications, I built solo, running on web, iOS, and Android from one GraphQL API. At this layer you own everything from the requirement to production, and you live with every decision yourself.

**Layer 3 — Agentic systems.** This is where my buffet pile was pointing. Instead of software that does exactly what you programmed, in the order you programmed it, you build software that _acts on its own_. You hand it an intent and it figures out the steps. A concrete example: today, a customer wanting a refund clicks through four screens — find the order, select a reason, submit the form, wait for an email. In a Layer 3 system, the customer says "handle my refund" and the software reads the order, checks the return policy, verifies there's no fraud flag, processes the refund, emails the confirmation, and updates the CRM — without anyone designing that exact sequence of clicks. The model is the intelligence. The thing that holds it all together — what's allowed to happen, in what order, with what memory, and what to do when a step fails — is called **orchestration**. That's where every tool I'd been learning fits.

**Layer 4 — Domain depth.** This is the layer above, and where I think the real businesses live. It's the same acting software, but fused with deep, specific knowledge of a messy real-world field. Not "AI for law" as a thin chatbot wrapper over legal documents — but a system that understands case law precedent, jurisdiction-specific filing deadlines, the difference between a motion and a brief, and when to flag something for a human because the edge case is genuinely ambiguous. Or in healthcare: not just summarizing patient notes, but understanding drug interactions, insurance pre-authorization rules, and the difference between a symptom that's worth noting and one that changes the diagnosis. The domain knowledge isn't a bolt-on — it's the product.

There are layers above even that — what all of this does to whole industries and economies. I have views. I'm deliberately leaving them out, because I'm an engineer, this is a technical bet, and the technical ground is the only ground I can actually stand on. So the map is four heights, and I'm planted on the second with a foot on the third.

## The bet

Here's the part that's a forecast, and the reason I'm rearranging my next few years around it.

I think Layer 3 — building agents — is about to become a commodity, fast. Right now there's an asymmetry: knowing how to wire these systems together feels like an edge. But the tools are racing to make it easy, the patterns are converging, and frameworks like LangGraph are doing to agent-building roughly what REST did to web APIs — turning a craft into a standard. (If that reference is new: REST is the convention that made "how a program talks to a server over the web" a settled, boring thing anyone could follow. Before REST, every API was a snowflake; after REST, a junior developer could integrate one in an afternoon. The same settling is happening right now to "how you wire an agent.")

The lens I trust most here is [second-order thinking](https://fs.blog/second-order-thinking/), a concept I picked up from Howard Marks: don't ask what a change does — ask what happens _after_ the obvious consequence plays out. The first-order effect of great agent tooling is "I can build agents." The second-order effect is "so can everyone — so building agents, by itself, is no longer worth much." It's the same pattern as cloud computing: the first-order effect was "servers are easy now"; the second-order effect was that the edge moved from _running_ servers to _what you built on them_.

If that's right, the edge doesn't vanish. It moves, to two places the tooling can't hand you. The first is the scars from running these systems in real conditions — I'll come back to that, because it's the one part of this whole map I've actually touched. The second is the domain fusion at Layer 4: the messy, specific, hard-won knowledge of a real field, which no framework will ever abstract away, because it isn't software — it's reality. So the bet, in one line: the building blocks commoditize, and the durable value moves to production judgment and domain depth. I'm spending my time accordingly.

I want to be honest about the status of that claim. It's a pattern I'm projecting forward — the same move anyone makes choosing a career or a direction, reading the present and guessing at what it becomes. I could be reading it wrong. But you can't wait for certainty in a field moving this fast; by the time it's certain, the move is already over. So I'm picking a direction now, on purpose, with the information I have. That's not the same as claiming to be right. It's just refusing to wait.

## The one thing I actually know

Everything above is forecast. This part isn't — it's the one stretch of the map I've walked directly, and the most useful thing I've figured out so far.

I'd assumed Layer 3 was the hard, exciting part, and that once I "learned the tools" I'd basically be there. Wrong, and seeing _why_ it's wrong reset my whole plan. Building an agent that works in a demo is easy; I've done versions of it. Building one that survives reality is a different sport. In a demo the input is clean, the API never times out, the user asks exactly what you expected, and nothing is on the line.

In production, everything changes. A customer types "my payment failed and now my order disappeared" — that's two problems tangled together, not one clean intent. The payment gateway times out mid-refund and your agent has processed half the steps but not the other half. The model confidently routes a billing complaint to the technical support agent because the customer mentioned "error." The cost of running the agent on one request quietly hits ten times what you budgeted because it retried a failing tool call in a loop. Someone asks the agent to "delete everything" and it takes them literally. These aren't edge cases — they're Tuesday.

> I've seen the front door, not the basement. I know what these systems look like when they work. I haven't yet lived through enough of them breaking to know what they look like when they don't — and the breaking is where the skill lives.

And they fail in a stranger way than normal software. Normal software fails _predictably_: it throws an error, you read the error, you fix it. These fail _semantically_ — they do the wrong thing while looking like they did the right thing. There is no stack trace for "understood you incorrectly, very confidently." It's like the difference between a car that won't start (easy to diagnose) and a car that drives you to the wrong address without complaint (much harder). That gap, between knowing the tools and being any good with them, is exactly the part the standardizing frameworks will never cross for you.

Which is also why the bet hangs together. If the easy part is commoditizing and the hard part is the scars, the move is obvious: go get the scars.

## What I'm doing about it

So the plan is boring, and boring is correct: build, ship, break, fix, write it down. Repeat. I'm going to work up Layer 3 one piece at a time — how these systems are wired together, how they remember things, how you measure whether they're any good, how they fail and recover, what they cost to run, and how you make one trustworthy enough to act on someone's behalf. Each of those is its own post. I'll write them as I earn them — the failures most of all.

And in parallel I'll start watching, on purpose, for Layer 4: the painful, expensive, repetitive problems inside some real domain where this kind of software could eventually be trusted. Not to find a startup idea this week — just to build the radar early.

That's the skin in the game, and it's why this is a thesis and not a hot take. I'm not pasting a prompt and publishing whatever comes back. I'm rearranging my actual time around this read. If the read is wrong, I'm the one who pays for it — which is exactly why I bothered to think it all the way through.

## The map will change

Some of these layers will collapse into one. Some of my labels are wrong. One day I'll meet someone who has lived up here for years and realize I've been describing the lobby with great confidence. Good. Drawing the map badly and correcting it in public — out loud, with a date on it — is the point. A year from now I might write the post that says I had this backwards. That post would be a feature, not an embarrassment.

For now it's enough that I know why I'm learning what I'm learning, where I think it leads, and what I'm betting on. If you were lost in the same buffet, maybe this helps you draw your own map — and place your own bet.

This is the first post in a series. The next ones go up Layer 3 one floor at a time.

[← All writing](https://mohaktripathi.com/blog/)

### Get the next one by email

One email when I publish. No cadence, no marketing, no list-sharing. Unsubscribe in one click.

Email addressSubscribe

Or follow along by [RSS](https://mohaktripathi.com/feed.xml).

© 2026 Mohak TripathiPlain HTML & CSS · no tracking · [RSS](https://mohaktripathi.com/feed.xml)