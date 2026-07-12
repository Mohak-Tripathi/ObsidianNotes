Session debrief

This was a Hire interview

###### at **Mid-Level**

Some answers flirt with senior-style breadth in ownership and business framing, but the missing rigor around results, stakeholder validation, and communication keeps this solidly in the mid-level band.

Overall

##### Overall

This was a **hire at mid-level**. You showed strong ownership, high comfort with ambiguity, and credible perseverance across multiple stories with real stakes: a production UI revamp under unrealistic executive pressure, a three-iteration internal proposal tool, and a zero-to-one CRM build with meaningful technical tradeoffs. The best answers had a pattern I like for mid-level engineers: you noticed when the original framing was wrong, built a more grounded plan, and then executed it rather than just critiquing it.

The strongest signals were in ownership, ambiguity, conflict handling, and practical leadership. You didn't just describe work; you described decisions, tradeoffs, and why they mattered. The proposal-tool story was especially useful because it showed failure, diagnosis, and adaptation instead of a polished success-only narrative. You also did a good job connecting engineering decisions to business consequences, which is often where mid-level loops are thin.

The reasons this doesn't rise above a straightforward hire are mostly about rigor and communication quality, not capability. Several answers were too sprawling, which made strong substance land softer than it should have. A few stories also stopped short of the highest bar on validation: you sometimes inferred stakeholder needs instead of directly checking them, and some 'impact' stories leaned more on personal growth than on measurable user or business outcomes. If you tighten the storytelling and bring sharper evidence of outcomes and stakeholder calibration, you'd be operating near the top of the mid-level band.

##### Signal areas

Below the bar

At the bar

Above the bar

Scope

You described work that is meaningful for mid-level scope: rebuilding a 50-page production UI safely under time pressure, shipping a zero-to-one CRM across web and mobile, and improving internal proposal throughput. The main limitation is that some of the largest stories were either solo side-projects or individual execution-heavy, so the scope is strong for mid-level but not yet consistently team-scaling or org-shaping.

Ownership

Ownership was one of the clearest strengths in the loop. You consistently used 'I' for key decisions, took responsibility for failures in V1/V2 of the proposal tool, and translated problems into concrete action plans rather than waiting for direction.

Ambiguity

You were strong when working through unclear product and technical spaces: choosing a multi-tenant design, scoping around missing backend dependencies, and pivoting the proposal tool only after re-understanding sales behavior. The signal would be even stronger with more evidence of how you validated uncertain choices after the fact, not just how you reasoned into them.

Perseverance

The best example here was pushing through two failed versions of the proposal-generation system, changing approach instead of defending sunk cost, and carrying V3 to a measurable business improvement. Some other answers framed perseverance more as personal motivation than as a concrete recovery path, but the core signal is still strong for mid-level.

Conflict Resolution

You handled disagreement with the CEO professionally: no public arguing, a fact-based risk mitigation plan, and full commitment once alignment was reached. The only real miss is that you mostly inferred the CEO's reasoning rather than directly testing the business driver before counter-proposing.

Growth

Your learning approach is structured and above average for mid-level: primary sources, mental models, hypothesis-driven validation, and lightweight team mechanisms like Friday learning syncs. The gap is that some reflections stayed at the process or tooling level instead of naming deeper judgment changes in how you now operate.

Communication

You showed strong instincts in translating technical concerns into business terms and in repairing trust with clients through demos and update cadences. What holds this below high is delivery: several answers were verbose and stream-of-consciousness, and you sometimes left key points like stakeholder alignment or outcome measurement implied instead of explicit.

Leadership

For a mid-level engineer, you showed good leadership through influence rather than title: organizing team learning, aligning HR and leadership on AI upskilling, reassigning work by module familiarity, and embedding with sales to reshape a failing internal product. This is solid mid-level leadership, though not yet the broader execution leverage expected at senior.

##### What worked

- Handled a real disagreement with the CEO calmly and constructively, replacing a risky two-day mandate with an evidence-based eight-day plan that shipped 50 pages with zero data-layer breakage.
    
- Showed strong product and technical ownership in the proposal-generation story by recognizing that V1 and V2 were failing, abandoning sunk cost, and rebuilding around actual sales behavior rather than technical assumptions.
    
- Demonstrated thoughtful architectural judgment in the CRM story, especially in the multi-tenant tradeoff discussion and the explicit mitigation for row-level isolation risk.
    
- Translated technical concerns into business language repeatedly, whether with a non-technical CEO, anxious clients, or the business case for continuing the internal sales-tool investment.
    
- Used concrete mechanisms to improve execution quality, including guardrails for AI-assisted changes, integration tests, Sentry, evals, and incremental feedback loops with users.
    
- Showed mid-level leadership through influence: weekly learning syncs, paired upskilling, HR collaboration on adoption, and workload allocation based on prior module familiarity.
    

##### Where to focus

Communication

Several strong stories were harder to evaluate than they needed to be because the delivery was long, repetitive, and sometimes buried the key decision or result; the project-impact answer in particular covered many threads without a tight throughline.

**Try this:** Use a stricter structure: context, decision, action, result, learning. For impact stories, lead with the business or user outcome first, then cover only the 2-3 decisions that made that outcome happen.

Conflict Resolution

In the CEO disagreement story, you built a solid counter-plan, but you mostly inferred why the two-day deadline existed instead of explicitly asking what business event or commitment was driving it.

**Try this:** Before pushing back, ask one direct constraint-finding question such as 'what makes two days important?' That often changes the shape of the solution and is a stronger signal of mature disagreement handling.

Scope

The most impactful-project story leaned heavily on a solo side project with early traction, but the results stayed thin: four trial customers, pre-revenue, and mostly personal engineering growth rather than demonstrated customer or business change.

**Try this:** For future loops, pick examples with clearer external impact, or quantify the effect of the work more directly: time saved, conversion improvement, defect reduction, adoption, retention, or revenue influence.

Growth

Your reflections were often real but tactical; for example, after the CEO conflict and the client escalation, you focused more on AI guardrails or demo cadence than on the deeper judgment error that caused the situation.

**Try this:** State the personal pattern explicitly: what assumption you used to make, why it was incomplete, and what you now do differently. That shows growth in judgment, not just added process.

###### How was this practice?




###### Behavioral Practice

O

Other

Mid-level

Q6

Session debrief

This was a Hire interview

###### at **Mid-Level**

Some answers flirt with senior-style breadth in ownership and business framing, but the missing rigor around results, stakeholder validation, and communication keeps this solidly in the mid-level band.

Overall

###### What was a situation where you didn't agree with your manager or superior's decision?

“So, my CEO wanted a full UI and UI revamping, which needs to be done in two days, and through Claude, Claude code. So, I disagreed with him, and I didn't argue in that room, and I went away and, you know, came up with a risk mitigation plan, which is like we can shift this in seven to eight days rather than the two days. So, basically the whole context was, my CEO is a non-technical person. He's reasonably very capable, and he's excited for the recent development which has happened through Claude code and Codex. And also, the product, the flagship product which we have been building called Javo AI, is basically, has been built in the last two years, and therefore, it has made, there are so many changes happen, and that leads to a UX flow which is broken. So, he ordered a revamp, and once the revamp design is ready, he wanted me to, you know, do the revamping in two to three days. So, this is, and the code is around two years in the production. It has been built in the two years, and that was the, he wanted to do it, and therefore there is a risk involved at this because there is an API contract and the data layer and the front-end sales. So, what I did as an action is, I didn't litigate it in that room and went back and created a risk mitigation plan with a specific failure mode of whiteboarding into the mature production database, production codebase. So, there is a chances of API breakage, data layer integrity, security on the client-supplied data, versus a greenfield project. Because if it is a greenfield project, that could be whiteboarded and that would not have that much problem, there would not be that much problem as compared to working in the two years old codebase. So, I brought back and explained him the risk in terms of business terms, and he agreed on it with some hesitancy, and told me to take some time but do it right. I turned out the, I created a plan with three people side together, we created a guardrails, we put the constraint very well, and we created Claude.md file, we did all those constraints, and then on that basis, we prioritized the work as well. And the allocation was basically on the modules which the engineers worked on earlier. I reassigned them the same module so that they will have the familiarity and we can move faster. The result was that around 50 pages were redesigned in eight days against a two-day task. And it has been pushed in the staging and production with zero data layer breakage. So, roughly it was conventionally, it was a one-month work, but we are able to achieve it through AI and through Claude coding in seven to eight days. So, my learning was that AI tooling is a multiplier and it works great when you are prototyping and doing the greenfield project from start. But when you are working on the mature codebase, it's a discipline which you have to maintain. You have to put the guardrails, contract, you have to take the ownership, and so to make it safe. So, translating, second thing is that when you are talking to non-technical people, it's very important that you translate the technical risk into the business terms to, you know, convince all, everybody to be onboarded on that decision-making. And don't litigate ever, take evidence and then, you know, plan it. When you have evidence, convincing, your odds go in your favor and your convincing capability increases. So, that is what the whole, one of the conflicts which I had with my CEO directly.”

Follow-up

What was driving your CEO's two-day deadline specifically? Did you ask him about it directly, and did his answer change anything about the plan you brought back?

“Okay. So, as I said that non-technical people, it is pretty obvious when anybody who's not coming from tech background or any other field where you do not have experience, what generally happens is that we underweigh the complexity. So, when he says two days, broadly, he's over-optimistic for the plot code and all the AI assistant coding IDs and all. So, according to him, broadly, he used to also building applications through white coding, and it works really well in the green field. So, that was his intention that it could be done really well and fast. And as I said that, for example, we have been building it in the Next.js, and it's not a server-side rendering completely. There is the client-side rendering. So, there is so much coding involved in the front end itself. It's not just doing the rendering like in the terms of all the HTML, CSS, all back is coming from back end and you are just rendering it, right? So, you have to maintain the state management, like Redux is involved, all the API contract is involved, and then there is a UI layer is also involved. So, changing UI is relatively easy, but when you are working with the API contract, you are working with the data layer, then that point of time things become a little complicated and requesting. So, my, so when his enthusiasm towards the AI recent AI development and not knowing exactly the technical complexity created that two-day deadline. But when I came up with a plan and I explained him all the business risks, the technical risk in terms of business value, and I told him the work needs to be done, then it becomes easy to convince him. And so, my plan was when I got to know how he is saying two days, he is mostly focused on the UI development and UI revamping, but he completely neglected the data layer, which also needs to be taken care. So, I emphasized on that as well when I was creating a risk mitigation plan, and when I highlighted those things and therefore I am able to convince him.”

Follow-up

Were there any moments during the eight-day execution where the plan hit unexpected friction, and how did you handle it?

“New UI development does, it was not completely, there is some new module or maybe just what happened was in the older module also, some new component has been added as well. So for those parts, there was no backend development at all. And when, and everybody was expecting that it's just a UI revamping, but there was a backend development which is also involved. So, and that was unexpected. And so what I told the team is that we'll focus on the UI and whatever the API backend development we have already done, we'll first implement that, and whatever things which we do not have, we create a stub in the frontend and, you know, create the design through dummy data. And once we ship everything and then in seven to eight days, and then whatever the new development which we have to do in the backend is consider as a change request, and then we do that development later on after completing the UI development. Because UI revamp is all about whatever we have already built the backend and complete that. Because if we focus on the backend development as well, then it would be really difficult to complete in seven to eight days deadline which we have set up. And that was a new changes, new UI changes which requires backend. These are like a new feature which needs more time to discuss and then implement end-to-end.”

Follow-up

How did this experience change the way you personally decide when to push back versus when to absorb a directive and move forward quickly?

“I think I have a very objective criteria for this, when to push back and when to move forward. It's pretty simple. So, when anybody who is making an assumption and forecast, whether the person has all the facts or not, that is the most important thing. So, just imagine if the deadline would have been coming from, because I am the technical side, so I am saying that if the deadline would have been coming from the technical lead, I am sure that it would be different, and it would be more generous in nature, and generous in number. But it was coming from non-technical person who does not know the in and out depth of it. Then he will, it cannot be completely correct. He can be, person can be broadly correct and can be broadly wrong as well. So, my job is to put, give the broader perspective of the depth of work and then allocate and decide the time. Because at the end of the day, we are in the same company and everybody will suffer, because like you are sinking and swimming together. So, it's important that you have to stand up and push back when it is necessary, because you are working collectively for the collective good of the company. And it's important that everybody is aware of the whole work which needs to be done. And I realize when everybody has that depth of knowledge of our work which needs to be done, people do converge on the similar line. So, that's my job. If I feel that all the facts has taken into consideration while making a decision, and the things which is already known and has been missed out, then I push back. Otherwise, I do accept and move forward and try to complete the task even though the deadline is a little aggressive.”

Feedback

👍 Good answer. You're a natural!

---

Summary

This is a solid pass at mid-level. You picked a substantive disagreement with real production risk, handled it professionally without public confrontation, built a credible alternative plan, executed it fully, and shipped a strong result. The two dimensions that keep this at a 4 rather than a 5 are: you inferred your CEO's reasoning rather than explicitly validating it with him, and your self-reflection focused more on AI tooling lessons than on how your own judgment or approach to disagreement evolved.

What went well

- The disagreement is genuinely consequential: a two-year production codebase with API contracts, data layer integrity, and state management risk compressed into two days is exactly the kind of team-affecting tradeoff expected at mid-level.
    
- You avoided public confrontation, went away to build evidence, and returned with a business-framed risk mitigation plan. That's the right sequence and shows strong professional judgment.
    
- Your constructive path was detailed and creative: module familiarity-based allocation, Claude.md guardrails, stub strategy for missing backend work, and treating new feature backend as a change request to protect the timeline.
    
- Post-decision commitment was exemplary. You stopped debating, coordinated a three-person team, and shipped 50 pages to production with zero data layer breakage in eight days against a notional one-month effort.
    
- Your framework for when to push back versus absorb (does the decision-maker have all the relevant facts?) is principled and clearly articulated.
    

What needs improvement

- You diagnosed your CEO's reasoning by inference rather than by asking him directly what was driving the two-day deadline. A stronger answer would show you explicitly validated whether there was an external commitment, demo, or business event creating urgency, because that might have changed your proposal.
    
- The self-awareness reflection centers on lessons about AI tooling discipline and communicating with non-technical stakeholders. These are real insights, but they don't show how your personal approach to disagreement or your own judgment gaps evolved from this experience.
    

Suggestions to improve

- On understanding the manager's reasoning: explicitly say whether you asked your CEO if there was a hard external deadline (investor demo, customer commitment, board meeting) before building your counter-proposal. If you did ask and there wasn't one, say so. If you didn't ask, acknowledge that and note what you'd do differently. This closes the gap between diagnosing his mental model and validating his actual constraints.
    
- On self-awareness: add one sentence about something you personally would do differently next time, separate from the AI tooling or communication lessons. For example, whether you'd surface the complexity risk earlier in the design phase before a deadline was ever named, or how you'd calibrate your own confidence when working in a mature codebase under AI-assisted acceleration.
    

Questions Behind the Question

Interviewers are trying to gather detail which helps them feel more confident about their assessment. It's their job to ask questions to get this signal, and it's your job to provide a rich answer which helps them feel like you've performed at level.

✓ Confident

You provided enough detail for the interviewer to assess these areas.

- Was the disagreement substantive enough to reveal judgment?
    
- Did the candidate try to understand the manager's reasoning before pushing back?
    
- Did the candidate express disagreement with candor and respect?
    
- Did the candidate work toward a constructive path rather than just opposing the decision?
    
- How did the candidate behave after the final decision was made?
    
- Did the candidate show honest self-awareness and learning from the disagreement?
    

###### Behavioral Practice

O

Other

Mid-level

Q6

Session debrief

This was a Hire interview

###### at **Mid-Level**

Some answers flirt with senior-style breadth in ownership and business framing, but the missing rigor around results, stakeholder validation, and communication keeps this solidly in the mid-level band.

Overall

###### Describe your most impactful project

“My most impactful project is Terrysage. So, Terrysage is a B2B real estate CRM I built from zero to one, like a sole engineer, over eight to nine months, alongside a full-time job. It's live on web, iOS, and Android, and it is an active pilot with four trial customers. So, the problem which I was trying to solve is the Indian property portals are spammy and fraud-heavy, and agents end up juggling leads across Magicbricks, 99acres, old CRM, WhatsApp. So, my brother-in-law saw this opportunity, and I owned the, you know, entire technical side of it. So, the four things which made it hard, I feel, is, and I walk you through each. One is the multi-tenant architecture decision. Number two is the lead capturing integration. Third is AI extraction reliability. And fourth is holding quality together as a solo dev on the spec when the things keep moving, when the feature list keeps changing. So, this was the whole context. And on the action part, if I talk about, I will talk about on those four points only. So, architecture side, the decision was whether should I build, you know, integrate multi-tenancy from the day one or not. And if I do that, on which kind of a multi-tenancy I will go with, because there is a database per tenant, with a schema per tenant, or shared schema with row-level isolation. So, I rejected the database and the schema per tenant level isolation in the multi-tenancy architecture. The reason being is we are not handling any kind of sensitive data, we are not serving the financial institutes, and there is no too much PII information as well. And the whole point of making the product viable is when you are having a shared resource, because just imagine if I have to host per database, one client, tenant, then it would be very costly as well. So, that's the reason I went with row-level multi-tenancy architecture. I chose shared schema row-level, and the only problem in this is, the trade-off side is, it's difficult to, you know, create isolation, and there is a probability of data leakage. Because if you missed tenant ID in anywhere, then it's possible that the cross-tenant operation can be done. So, I resolved this problem through adding a middleware layer, where any call when it comes to, from the tenant, I will fetch the tenant ID and attach it immediately. So, further downstream operation, everything will get filtered on the basis of tenant ID. So, that is how there can never be a scenario where the tenant ID isolation and filtration is not happening. So, that is how I handled the biggest trade-off, like a problem in the row level. So, that is how I chose the most cost-effective and easy to implement at the same time, avoiding the data leakage problem by adding a middleware from the very start. I also chose GraphQL over the REST API most of the time, because we are building it for multiple clients, like I had some mobile application is also there, web application is also there. So, I chose GraphQL so that the client can overfetch, underfetch as per their own need. So, this is the first leg architecture. Second is the integration. So, for integration, it was hard for me because I need to integrate Meta integration and Magicbricks and 99acres in the pipeline right now. We are trying to get the API endpoints from them. And Meta integration has already been done. And the bigger challenge was the burden of proof because I was handling clients' client data. So, B2B tenant is my client and their leads which I have supposed to handle. So, the burden of proof is enormous. And Meta has asked so many questions, and I need to do the compliance as well, legal side as well, and then integrate their APIs as well. So, giving every tenant the opportunity to integrate their Facebook pages, and then if they are running ads, that could be captured in my CRM as per the correct tenant ID. So, that is the integration part, which is a little challenging. And then the AI part, that's the third layer. So, I integrated a couple of AI features in the product as well. So, for example, one is voice to text agent notes, and second is LLM property description extraction that autofills the property form. The reason is that there is so many notes creation which is there, and people want to, do not want to write it. So, therefore, voice feature is there, which will, and there is very important that it will capture the Indian accent and all. So, therefore, I use OpenAI Whisper API. And second is property description. The property form is a multi-step form, and that requires a lot of filling. So, generally, we realized that from the input that they will get a description in the WhatsApp and all. So, what I did is, I take that description, put it in one layer, and then I extract all the relevant information and pre-fill all the form as much as possible, so that the agent just needs to check out whether the details is correct, and then it can just press, hit the button, and the property will get saved. And then last is, in these also some of the issues were come, like a reliability challenge which has come. And for that, I integrated evals and model grader, and that is how I made the system more reliable, these features more reliable. And then last is reliability under solo constraint. So, that is also a big challenge. And how I solved is that the problem which was coming is whenever we were testing it, we were not getting confidence, and every time even the tested modules were creating a problem. And therefore, I started writing very robust integration test cases through supertest. And there is a regression testing as well. So, if any bug will, I find, I write a test case for this, and that is how I solved this problem. I also integrated Sentry, which is fixing and finding the bugs automatically or any API which is responding slow. So, I integrated that as well. In that process, I figured out so many N+1 GraphQL queries and fixed it before even user is complaining. Then last is uncertainty as well because found talking to a lot of agents and they are telling their problems. So, we were adding features, and the features were also keep changing. So, I had to work on the uncertainty as well, which I taken care. So, this is the action part. So, result was that I shipped all the product, backend, frontend, deployment I taken care. And right now, four trial customers we have, we are pre-revenue, and we have 200 prospects in the pipeline. And the outcome I learned, claim is like engineering one, I will say that is the better outcome right now, not in the terms of business but in terms of personal engineering growth. So, I basically learned how to ship end-to-end product. I never got this opportunity end-to-end. So, I designed, I did the designing, I did the frontend development, backend development, and then the deployment, then the after production, taking care observability and solving bugs through Sentry, observability for that I also integrated uptime robot. So, those are the things which is a learning. So, I got a confidence that I can ship end-to-end product. So, this is the learning part. And yeah, so this is what I, this is my project which I am proud of and my biggest project till now.”

Follow-up

What was the hardest moment where the project looked like it might stall or fail, and what specifically did you do to get it back on track?

“So, I will like to answer this in non-technical and technical manner, both the side. So, in non-technical manner, I will say the hardest thing was keeping your momentum, keeping your motivation up to the mark because as I said, it's a very long duration, around nine to ten months we have, I have spent along with a full-time job. A lot of my weekends has been exhausted and got invested here. So, the motivation, keeping your motivation high is extremely important and that is something I tried to do. And as I said that, on the technical side, I will say the biggest challenge was I did not know most of the things, a lot of things I did not know. I have never, for example, I have never shipped any end-to-end product before. I have worked in some pieces of it, but never end-to-end, so I was not confident enough. So, that was the biggest challenge. I never, for example, integrated front-end, back-end, and DevOps side, and the proper deployment and all. I never faced the issue of, like, the biggest frustration was when the errors were keep coming, it was never-ending loop. It was like when you are testing and then again next day the same kind of error, different kind of error is coming in the module. And there I realized that manual testing will not work and therefore that was a pain, and then I tried to solve, and then I got to know about Sentry. I got to know about integration testing. So then I written so many integration tests and then I have written up Sentry as well, so to fix bugs without even, you know, manual testing when it is not figuring it out. So, that was a big problem. That is how I got some confidence because as a sole developer I have a very less bandwidth and I can't even test each and everything. So, relying on the tester tools was an important thing. And to be very honest, I did not even knew these tools exist. So, that is also a big thing. And right now the bigger challenge which I am facing is where the product will work or not, I don't know, in the term. So we are still pre-revenue. And the customer understanding is very important. So therefore I got to know about Hotjar that which checks the user experience and how the user is using the product. And so I am trying to integrate that as well. So the risk is still there. I am not saying that the product is ready and gonna fly. It's an engineering success, but it's a business side still needs to work, and it can still fail. So we are on the, I am on the thin edge right now. And yeah, on the technical side I will say when I was integrating AI features as well, the reliability was a very big issue. Therefore I got to know about evals and how the evals needs to be executed. I got to know about model grade, data, you know, you need to create a data set to test. All those things is so new. Meta integration was also a big challenge for me. I did not know I can be able to pull it off. The Meta compliance were very huge. So these are the technical side, non-technical side, it was a very big challenge in terms of scope, in terms of features, in terms of the unpredictability. So I literally pushed my limit.”

Follow-up

How did you decide which features to build next when the requirements kept shifting, and were there cases where you pushed back on or deferred something your brother-in-law wanted to add?

“Yes, so whenever you are deciding anything, you have to take into account the constraints. And here the biggest constraint was human resource, as I was the sole developer, as I mentioned earlier as well. So the first thing is that the scope of work which is already there. So the biggest challenge was building feature non... the CRM which we are building is, it's not something really unique, right? So, the usefulness is when you have a good number of features which is reinforcing each other, and that is how you are creating a value. So we have, I'm never gonna say that it's a zero to one original idea. It's like an idea which is already there, and you improve the product 30 to 40 percent. Okay, so when you are doing and improving the product, you have to build the full product as well. So that is the number one thing. So there are so many cases where this tussle happened between me and brother-in-law regarding what features to prioritize and what to differ. So the biggest one of the rubric of deciding is whether it's, what is the engineering effort which will be required. So, and what, how much the customer value addition will happen. So if both are going high in out of one to ten, if the engineering effort is less and business value or the customer value is more, then that is what the prioritization will be. That will be the highest priority. So like integration of meta is the highest priority, property module, AI feature integration feature on the property, filling is higher value because these are the module which client will work on day-to-day, lead ingestion module and all. These are the module which are mostly like a crux of it. So that is the number one thing, how less engineering effort required and how much better business value or customer value is getting created. And so this is the filter which we keep putting and that is the lens through which we kept on seeing all the features. And we ruthlessly ask whether this feature is just a technical embellishment or it is truly adding the value to the customer. Because we do not want to add, keep on adding feature which and make the product so much feature-oriented that customers started getting, and it becomes UX nightmare. So that is the way how I decided. And there will be so many pushback because my brother-in-law never know the tech side and engineering effort. So once we add these two things together, then we decide and prioritize.”

Follow-up

Pick one technical decision you made during Terrysage where you genuinely didn't know the right answer upfront, describe what information you had, what you were uncertain about, and how you ultimately validated whether the call was correct.

“Asking related to Terrace Sage product only, and there are various time it has happened. But I will say one of the things is the data modeling, the time when I was doing the data modeling of a property module. Generally, I am very confident in the data modeling and all, so that's not a problem. But here the data modeling has a sheer volume, like a sheer complexity. I will tell you how. So there is a property, that is the number one. Then there is a property category, whether it could be residential, commercial, and or agriculture. Then among these three types, there are 15 property types as well, like apartment, villa, or shop or commercial office and warehouse. So that is how there are 15 property types as well. And then in every property type, in some of the property, it could be available for rent as well and sale as well. So I have to create like a tree-like structure where there is a main property module, then per property module I have to create a property type module, and then per property type module also I need to do that particular property type rent or property type sale. So that is how I created for all property type. And at that point of time, I was not sure whether this is correct or not. And I had less people to get the validation as well. I did not have the very experienced senior software engineer who can guide me at that point of time that I was making a right decision or not. But that is a very normalized way of designing the table. I thought of denormalized it as well because you have to do so much joining and maybe later on it can become a bottleneck in terms of data fetching because property module is a hot module, which is going to be utilized on every single day. So that was, you know, trade-off I was thinking whether I am doing too much normalization and should I focus on denormalization. But the idea was that first let the problem come, and if it will come, then I will denormalize it and try to solve it. And then I put some indexing as well. And if I thought of I will put some more indexing because that module requires. So why I have not pre-engineered the indexing as well? Because I have added up to where I know the keyword, but where I do not know, I was like I will analyze the access behavior of a module and then I will add. And so denormalization and the indexing was, the more indexing was a little bit deferred. And that is where I kind of, you know, was not confident in designing. Apart from that, I will not say in terms of engineering outcome, anything which was very challenging. The business outcome is challenging and whether it will be accepted by or not because I was not on the field and whether the product will go on or not. But I am trying to be engineering perspective, giving that engineering perspective. I have built better and harder features in terms of like meta integration and all. But uncertainty wise, I will say the data modeling of a property module was uncertain I was. Because meta integration is also a difficult feature, but I was not uncertain. I knew the value addition is high and what I need to do. I need to comply with the compliance of a meta which meta has provided.”

Feedback

You're on the right track.

---

Summary

You show genuine technical breadth, clear solo ownership, and real problem-solving instincts across a complex project. The main gap holding this back is the results framing: you lean heavily on personal learning and engineering growth rather than connecting outcomes to user, business, or operational impact. Strengthening how you articulate results and sharpening your ambiguity-handling narrative would make this a solid pass.

What went well

- The problem scope is well-grounded: you clearly articulate why Indian real estate agents face real pain (spammy portals, fragmented lead management), giving the project genuine product significance beyond a personal side project.
    
- Personal ownership is unambiguous throughout. You consistently use 'I' with specific decisions: choosing row-level multi-tenancy, integrating the middleware layer, picking GraphQL, integrating evals for AI reliability.
    
- The feature prioritization framework (engineering effort vs. customer value) in the third follow-up is concrete and shows real mid-level judgment, including that you pushed back on your brother-in-law using explicit criteria.
    
- You demonstrate intellectual honesty about uncertainty, for example acknowledging you deferred indexing decisions until access patterns emerged rather than pre-engineering prematurely.
    
- Proactively finding and fixing N+1 GraphQL queries via Sentry before users complained shows good engineering instinct and ownership beyond the initial plan.
    

What needs improvement

- The results section is the weakest part: 'four trial customers, pre-revenue, 200 prospects' is thin, and you then pivot to framing impact as personal engineering growth, which is not what interviewers at mid-level are looking for.
    
- The hardest-moment answer focuses on motivation and reactively discovering tools (Sentry, integration testing) rather than showing you proactively restructured a plan or adapted ownership when the project was at risk.
    
- The data modeling follow-up meanders and never clearly states how you validated the decision was correct, which is what the question asked for. The answer trails off into general uncertainty rather than a crisp validation story.
    
- The narrative is significantly longer than needed, with multiple restated points and filler phrases, which can obscure the strongest signals and test an interviewer's patience.
    

Suggestions to improve

- Reframe your results around observable user or operational outcomes, not personal growth. For example: 'Agents in the pilot reduced their lead-juggling time because all Facebook leads now land in one place' is far stronger than 'I learned how to ship end-to-end.'
    
- When describing the hardest moment, structure it as: situation changed, here is the specific decision I made to adapt, here is what I did differently as a result. Avoid framing obstacles as learning opportunities unless you also show a concrete course correction.
    
- For the data modeling validation question, close the loop explicitly: state what signal (query performance, pilot feedback, error rates) you would use or did use to confirm the normalized schema was the right call, even if the answer is 'we have not hit the bottleneck yet and here is why I am confident we will not at current scale.'
    
- Practice a 90-second version of the core story: problem, your key decision, one obstacle you adapted around, and one concrete outcome. Use the longer version only if the interviewer asks to go deeper.
    

Questions Behind the Question

Interviewers are trying to gather detail which helps them feel more confident about their assessment. It's their job to ask questions to get this signal, and it's your job to provide a rich answer which helps them feel like you've performed at level.

✓ Confident

You provided enough detail for the interviewer to assess these areas.

- Was the problem meaningfully important for the candidate's level?
    
- Did the candidate make their personal ownership and decisions clear?
    
- Did the candidate show strong judgment under ambiguity or tradeoffs?
    
- Did the candidate explain results credibly and proportionally?
    

? Unsure

The interviewer got some signal but may want to probe deeper in these areas.

- Did the candidate drive the work through obstacles instead of stopping at the initial plan?
    

###### Behavioral Practice

O

Other

Mid-level

Q6

Session debrief

This was a Hire interview

###### at **Mid-Level**

Some answers flirt with senior-style breadth in ownership and business framing, but the missing rigor around results, stakeholder validation, and communication keeps this solidly in the mid-level band.

Overall

###### How do you approach learning new things?

“So now with 3.5 years in the industry, what I realize is that there is a huge amount of resources available, so, and there is too much noise. So what I do is that I am very restrictive in terms of from where I am learning. And the best thing which I do is, if I am learning, I learn from the original sources. So if I am learning, for example, currently with my SD-2 skill set, I am also learning the agentic AI development. So my clear focus is to understand, build the mental model, what this AI engineering and the agentic AI development is. What are the key domains which I need to learn? So like I am creating a tree in my mind, like LLM is in the center, then there is a memory is involved, then there is a knowledge space is involved, then the evals is involved, and then the production deployment is involved, and then finally, relearning from the production environment, and then, you know, doing that same thing again. So that is the core mental model. And then I am just filling those components with the right sources through documentation. And then I am building from the quick start, trying to build and breaking things up, and doing the, get my hands dirty, and build some prototype out of it to get the hunch of it. And then when the real problem comes, then I try to build architecture, and then try to see or to solve that problem, how much knowledge gap I have, and fulfill that through the documentation again. So it's never be, when I am learning, I'm just trying to understand in depth. And when I am implementing something in the production, in the real world, then I go deeper in that particular module. But it's never the intent that read the module end-to-end and try to absorb every knowledge possible, because that is generally do not gonna work in long run because technology frameworks and all change. So core concept learning is important. And that is how I approach new learning now.”

Follow-up

What happens when your learning stalls, say you've read the docs and built a prototype but something still isn't clicking? Walk me through how you've pushed through that and what the outcome looked like.

“Yes, so whenever I am learning anything, I also create a hypothesis around it. Okay, so whenever I am learning, I do create, okay, what is, what could be done, and this is my hypothesis. And when I am learning through building prototype, reading documentation, whether I verify that hypothesis or that hypothesis gets failed. So if it verifies, if I am able to accomplish that hypothesis, that means my learning has been reinforced, and I feel like I completed one checkpoint. If it fails, then the whole reasoning is why it failed, and what is the correct answer. And that is how I create a new hypothesis, and then I try to reinforce that hypothesis by repeating the same process. So that is the whole way. So for example, I am creating a system prompt, I am creating the prompt, and how can I validate this whether this will work in all the way the user is, you know, interacting with that. So for me, I need to create thousands of, maybe, you know, data set, and then try to create multiple ways of user questions, and then very categorically create a model evaluator, programmatic evaluator, and a human evaluator as well, some of them. And then I try to run that data set and see where the average score is coming. And that hypothesis, it's all about, can I get reliability in the user prompting? And for me, if the score is more than 95%, then I can say the system is reliable, otherwise it is not. Because in the traditional software engineering, the threshold is around 99.99%, and AI at least 95% and closer to that is the way for me to validate the hypothesis, break the hypothesis. So that is, if you have, and that is how this paradigm I created, so test-driven development. Because you first of all have the problem, you create test cases, and then you try to, when you build the solution, you try to focus on the test cases whether it is getting green or red. So the point which I'm trying to make is, you should have the problem statement and you should have a success criteria. And then if you are learning, and you are able to recall the success criteria, that means your learning is completed. So do not learn without the final goal.”

Follow-up

Give me a specific example of a time your learning process broke down for days or weeks, not just a single failed hypothesis, and you had to find a fundamentally different approach to get unstuck. What did you try, what finally worked, and did anyone else on your team benefit from how you resolved it?

“Okay, at the team level, I believe in collaborative learning. So, for example, right now my company is focusing a lot on AI upskilling. And therefore, what I integrated in my team is that like, entropic courses you have to do, and everybody is busy in their own daily work as well. So, we divided the team in two-person and three-person max. And that's all about, you have to discuss and learn from each other. If somebody is completing some course and somebody else, then they are sharing their knowledge with each other. And there is a Friday sync-up also I organize, where anybody, whatever the team members have learned on the week, they will share with each other, and they share the technology. For example, I got to know about Hotjar, that user experience can be tracked qualitatively through Hotjar. That is a new learning I have been exploring, and that is again shared to the team as well, and everybody will get benefit out of it, because on the weekend they can also explore the same. So, the collective consciousness to increase, and that's why we enforce that. There is a weekly learning sync-up, where whatever the people have learned and experimented, they can share. And we also believe in the team learning and the group learning, because they are the people who sometimes, they push each other. So, there is some target of learning as well, and that is what they have to fulfill and accomplish that goal as well, so that broadly everybody will get benefit from each other. That is how the whole group get benefit and remain updated with the technology. So, my initiative is learn by building teams, and the second is weekly sync-up of knowledge transfer, knowledge, new technology learning. That's the two initiatives I've taken.”

Follow-up

How long did it take you to get genuinely productive with the agentic AI stack you described, and was there a specific point where progress felt blocked for more than a few days? What did you do to push through it?

“I'm genuinely productive in 10 to 12 days because I am able to automate my emails. I am able to automate, I linked my email, my calendar, and what I need to prioritize. So, my email drafting, my email responses. So there are so many automation, my learning outcome I learn by creating projects, and that has been automated a lot. So I have become productive, what I want, genuinely productive in 10 to 12 days. And things do get halted because the workload in the office is also unpredictable, and that makes consistency harder. Therefore, rather than seeing daily discipline, I consider the weekly discipline. And for me, it's important that if there is any week which is very busy in the working, like office work, then I should be, I try to prioritize my personal learning and my agentic AI learning in the weekends. So, broadly, I try to catch up on a weekly quota, weekly basis. So that is how the learning do get halted, but I try to catch up in the weekends as well to be broadly on the correct timeline.”

Feedback

👍 Good answer. You're doing great!

---

Summary

You demonstrate a clearly structured, hypothesis-driven learning process with concrete team-level knowledge sharing, which is solidly above average for mid-level. The main gap is that perseverance under sustained difficulty never surfaced with real specificity: every block you described resolved quickly or was attributed to workload, and the team-sharing answer pivoted away from a personal struggle story. That missing signal keeps this at a 4 rather than a 5.

What went well

- Your mental model tree approach (LLM at center, memory, knowledge space, evals, deployment, feedback loop) shows genuine structural thinking about how to decompose a new domain, which is strong mid-level signal.
    
- The hypothesis-driven validation loop you described, forming a hypothesis, building a prototype, measuring against a success criterion like 95% reliability, is a concrete and credible way to close the learning loop.
    
- Your team initiatives (paired learning groups, Friday knowledge sync-ups) are specific and practical, showing that your learning converts into team benefit rather than staying private.
    
- You articulated a sensible depth-calibration principle: learn core concepts broadly, go deeper only when a real production problem demands it, which avoids both over-study and shallow trial-and-error.
    

What needs improvement

- Perseverance under sustained difficulty was never demonstrated. Every block you described resolved within days or was explained by workload, and you never walked through a moment where your approach fundamentally failed and you had to change strategy.
    
- The depth-calibration dimension stayed somewhat abstract. You stated the principle well but did not give a clear example of a moment where you consciously chose to go shallow on one area and deeper on another within the same project.
    
- The team-sharing answer pivoted to organizational initiatives rather than answering the follow-up's core ask: a specific personal breakdown and how you pushed through it. That left the perseverance signal at LOW.
    

Suggestions to improve

- When asked about a time your learning broke down for days or weeks, anchor to a specific moment: name the technology, describe what was not clicking, and explain what you tried first that failed before you found what worked. Concrete details make the story credible.
    
- To strengthen the depth-calibration dimension, add one sentence that names a deliberate trade-off: for example, 'I chose not to go deep on the memory module yet because it was reversible, but I went deep on the eval framework because getting that wrong would affect every downstream decision.'
    
- For the team-sharing dimension, briefly connect the initiative back to a measurable outcome, such as how many team members upskilled or how it reduced repeated questions, so the impact is tangible rather than just structural.
    

Questions Behind the Question

Interviewers are trying to gather detail which helps them feel more confident about their assessment. It's their job to ask questions to get this signal, and it's your job to provide a rich answer which helps them feel like you've performed at level.

✓ Confident

You provided enough detail for the interviewer to assess these areas.

- Does the candidate learn proactively and with structure?
    
- Does the candidate validate understanding through application and feedback?
    
- Does the candidate turn learning into sustained improvement for themselves or others?
    

? Unsure

The interviewer got some signal but may want to probe deeper in these areas.

- Does the candidate adapt the depth and speed of learning to the situation?
    

Think we got it wrong?Report bad feedback

Behavioral Practice | Hello Interview


###### Behavioral Practice

O

Other

Mid-level

Q6

Session debrief

This was a Hire interview

###### at **Mid-Level**

Some answers flirt with senior-style breadth in ownership and business framing, but the missing rigor around results, stakeholder validation, and communication keeps this solidly in the mid-level band.

Overall

###### Tell me about a time a project you were driving hit serious obstacles. What did you do?

“This-based company and sales has to turn a proposal around as fast as possible, so otherwise leads will become hot to cold. And therefore, the lag was costing real deals. And I have to build an AI-driven product which can help to build a FRD in the proposal. It's a proposal generation tool which I have to build into it to make sales proposal send cycle as small as possible and short as possible, and so that they can send proposal fast. So, to be very honest, I created, already created two versions, V1 and V2, which failed miserably. So that is a very big blocker. The reason is, version 1 was a traditional software which is like we build 40 questions along with me and my CEO and the idea was these 40 questions will be answered by the customer and sales representative executive will assist. But that did not work at all because sales team said that those 40 questions are too much in nature, number one. Number two is the sales requirement is very case-to-case basis and you cannot compartmentalize in these 40 questions and they are very rigid in nature. So that is the big problem. Second version where we tried to build a RAG pipeline as well which will, and we reduced the questions from 40 to 12, very core questions, and we build a RAG pipeline where all the proposals of previous proposal of last five years has been embedded in the vector database. And the intention was that if any question among those 12 can be answered and any messy requirement or the custom requirement which sales people do not have the expertise and where they need technical assistance from the technical team. But if the proposal is already have that in the past, then the sales team will not be dependent upon the technical team. And that is how it will get speed up. But still that did not work because the accuracy of that pipeline, the RAG pipeline was not up to the mark. And those 12 questions also not adhering to the way salespeople do ask questions because they're saying that we do not ask those questions straightforward. We, you know, build a story and rapport with the client and then we try to mold the client and try to extract those questions implicitly. So that is also pretty hard. Some of the questions were like, you cannot ask implicitly till the point you ask explicitly. So that also kind of failed. Then the third version which got successful, so that's a different story. But you asked me the biggest roadblocks, so I mentioned the two versions which failed for the product which is finally called Scopely.”

Follow-up

What did you do differently when V2 failed, and how did you personally drive the decision to move toward a third approach rather than abandoning the project or waiting for direction?

“So, first thing which you are asking what I did differently. So, first of all, version two was built on the top of version one only. So, it's like I was trying to salvage, therefore I reduced from 40 to 12 questions but the foundation was not strong enough. And I was trying to salvage the version one. And so the third version where what I did was, I was ruthless in questioning the sales team. I was spending time with them and trying to understand their day-to-day functionality and how they operate. So, I was close to my end-user, number one. And this time I was thinking zero to one rather than one to n. I was not trying to salvage whatever I have in the technical side. I was trying to understand what the genuinely pain point for customer. And rather than, you know, taking the input from the CEO much, I was trying to take the input from the sales representative and from various experience line. Because the 10-year person who is working in the company have different kind of a problem because he knows the product end-to-end and he can sell. But the person who has joined immediately will have less product knowledge as well. So, they may have less sales experience at the same time, less product experience as well. So, first of all, I extracted my technical hat. I literally put down and trying to understand from the customer perspective, first principle, how the sales team operate and where they struggle and why there is a lag in the sales and proposal. So that was the biggest thing. And then I was getting the real insight that. The biggest challenge which they got is, because they select a product which is standard. But that's not a problem because that information is available in the documentation as well and there is a detailed documentation for the sales team as well to understand. The biggest challenge is when the requirement is custom, when there is a custom requirement and when they have to put the effort hour as well. And because these are the projects which are broadly time basis, so you cannot go wrong on the effort hour because every effort hour is chargeable and a custom requirement can... Because if the effort hour wrong, if it is under number, then the company will have a project over and then if it is more, then you can lose the client itself. So effort hour and the custom function, how much effort hour and how much possibility of viability of that customization option whether available or not, whether it's possible or not is also a big challenge. So these are the bigger challenge for them and they said that if you can solve this, then it's very good. And they gave the solution as well that verification through the official documentation and whether these custom solution is possible and bird-eye view of effort hour so that we broadly should be right. Then 10%, 20% inaccuracy works but not more than that. So when I sat with them, understand the deeper level, then I literally discarded my, I was not trying to salvage my product, the already technical product which I built. So third version was complete overhaul. I did not try to salvage anything and I built from scratch and every time I was talking to every day whenever I was adding any feature, I was taking feedback from the sales representative and that is how third product got success, third version got success.So this is the action and the final outcome which I got is that the productivity of proposal has increased by 40%. So now, every earlier there will be around 10 proposals the one sales executive on average able to send in a month, and now it is able to send 13 to 14 proposals. So around 40% proposal efficacy has increased. And so the learning side what I learned is, be customer focused. Do not try to build a solution from the technical side, but try to understand the dear customer problem, and then do the solutioning. And keep customer in loop throughout the end-to-end building cycle, not when you build a complete product, but when you are even adding small features. And because if the problem is severe enough, customer will try to invest time with you as well. And that is also a validation that because if the customer is giving you money or time, that means you are solving the real-world problem, which is worth solving.”

Follow-up

Were there moments between V2 failing and V3 gaining traction where you seriously considered stopping, or where others pushed back on continuing the project? How did you handle that pressure?

“Yes, definitely there was a pushback, and the only thing is that what I truly believe, because the pressure is because you are a resource to the company and there is opportunity cost. I have been an experience of full stack, and there is other full stack projects of a customer, which is also getting delayed because of this initiative. So, for me, why I pushed more on this? Because the problem was genuine. Even 40% increment which has happened in the proposal sending. Just imagine even there is a four team members in the sales, and that means we are able to send 16 more proposals. And even if two or three get successful and converted to deal, and even if they are, for example, 30 lakh rupees on average, because that is the average order value in my company. So, it is like 90 lakh to one CR profit, share profit with my product. So, on every month. So, just imagine even if you make it at 12 months, that is like 10 to 12 CR, which is, if I was thinking in the business outcome side, I realized, though this problem is worth solving. And that is how I, you know, make a decision that I need to break the shackle and give one more attempt, because it's worth solving. And number two, why I pushed harder for the version 3 is because the feedback were coming, and I have not exhausted all my options. And when I started sitting with them and figuring it out why it is not working, I realized there is a loophole in my understanding in the version 1 and 2, and therefore the product did not pull off. So, the problem was in my end, in my execution, my learning, so what to build in the first place. So, because there was a scope of improvement and the business outcome was meaningful, so therefore, even though there was a pushback, I persevered and took ownership and leadership to focus on and build this as well. And obviously, I was doing other full stack projects as well, which is other customer, but I dedicated some amount of time to this scope leap project as well and completed it. And now once it is working, so yeah. So, you have to have intuition, you have to have some objective criteria. For me, it was there was a scope of improvement. I had not exhausted all my options, and there is a clear share of business outcome which was very clearly visible to me. And that is the reason I pushed hard for the third attempt as well.”

Follow-up

You described rebuilding V3 completely from scratch while also handling other client projects. How did you structure your time and set interim checkpoints to make sure V3 was actually making progress, rather than just feeling busy?

“Yeah, so I use a time blocking technique. Officially, I have an eight-hour shift, and I used to prioritize my client work from morning to the second half, till six hours. I work on the client's work because that is the external projects, which where the deadline is also, you have to meet. And then for the next last two hours, I was working in this Scopely project. So 25% of time is going basically in Scopely. And because working in the end of a day, even if I have to push a little 30 minutes extra, I can do and try to end at a correct checkpoint of a V3 development as well. And it was a little quick as well because you know what to do and you have the two versions you already built, you have the infrastructure already there. So that is, more two hours is sufficient enough, and the internal, because it's an internal project, you can be a little flexible with the deadlines. So that is the way I prioritize official client work first and then internal project later, and later of a day for two hours.”

Feedback

👍 Good answer. Nice work!

---

Summary

This is a solid mid-level pass. You demonstrate genuine diagnostic depth across two failed versions, real ownership in rebuilding from scratch, and honest self-reflection that avoids blame. The main gap is communication: you show you made a business case when pushed back on, but you don't describe how you proactively kept stakeholders informed as V3 progressed. The scope is also primarily individual, with limited evidence of influencing team-level execution beyond your own tasks.

What went well

- You clearly separate symptoms from root causes across both V1 and V2, identifying specific failure modes (rigidity of questions, RAG accuracy, mismatch with how salespeople actually communicate) rather than vague difficulty.
    
- You explicitly abandoned sunk-cost thinking, stopped trying to salvage prior work, and rebuilt zero-to-one after embedding with end users. This shows strong ownership and adaptation.
    
- Your resilience reflection is genuine and self-accountable. You say the problem was in your own execution and understanding, and you articulate a concrete behavioral lesson about customer-first development.
    
- The business case you constructed to justify continuing (ROI calculation, deal conversion math) shows maturity in connecting engineering decisions to business outcomes.
    
- The time-blocking approach (6 hours client work, 2 hours Scopely) shows practical self-management under competing priorities.
    

What needs improvement

- Communication is the weakest dimension. You describe reacting to pushback with a business case, but you don't describe proactively surfacing risks, sharing tradeoffs, or updating your CEO or stakeholders as V3 was being built.
    
- The scope stays largely individual. You coordinated with sales reps for feedback, but there's no evidence you influenced how others executed, coordinated cross-team delivery, or improved the plan for anyone beyond yourself.
    
- The answer is quite long and unfocused in places, especially the ROI calculation section. In a real interview, this can cause interviewers to lose the thread of your key decisions.
    

Suggestions to improve

- On communication, add one or two concrete moments where you proactively updated your CEO or a stakeholder before being asked. For example, did you share a summary after V2 failed explaining what you learned and what you planned to try differently? That kind of early, structured update is what mid-level interviewers look for.
    
- On scope, try to include at least one example of your work affecting someone else's execution. Did any sales rep change how they ran demos based on your findings? Did your research help the CEO or product team make a different decision? Even a small example of influence beyond your own tasks strengthens this dimension.
    
- Tighten the narrative structure: open with the business context in one sentence, spend most of your time on the V2-to-V3 pivot decision and what you did differently, and close with the outcome and lesson. The ROI math is compelling but can be one sentence rather than a full walkthrough.
    

Questions Behind the Question

Interviewers are trying to gather detail which helps them feel more confident about their assessment. It's their job to ask questions to get this signal, and it's your job to provide a rich answer which helps them feel like you've performed at level.

✓ Confident

You provided enough detail for the interviewer to assess these areas.

- Did the candidate recognize early that the effort was not going as planned and correctly diagnose the real problem?
    
- Did the candidate take ownership and adapt their approach rather than merely endure the difficulty?
    
- Did the candidate sustain progress in a way that matched the scope of their role?
    
- Did the candidate show resilience with reflection rather than blame or empty optimism?
    

? Unsure

The interviewer got some signal but may want to probe deeper in these areas.

- Did the candidate communicate candidly and proportionally as the situation evolved?
    

Think we got it wrong?Report bad feedback

Behavioral Practice | Hello Interview


###### Behavioral Practice

O

Other

Mid-level

Q6

Session debrief

This was a Hire interview

###### at **Mid-Level**

Some answers flirt with senior-style breadth in ownership and business framing, but the missing rigor around results, stakeholder validation, and communication keeps this solidly in the mid-level band.

Overall

###### Give me an example of an initiative you undertook because you saw that it could benefit the whole company or your customers, but wasn't within any group's individual responsibility.

“As I stated that I was improving and doing bootcamps to improve myself in the AI engineering and agentic development. So, when I was learning through Anthropic courses as well, what I realized that these are useful, and AI fluency is extremely important in the team and my team and holistically in the organization as well. Therefore, I talked to my CEO as well and told him that we should encourage the team members to be AI fluent. And that is why we encourage the customers, sorry, we encourage the team members to sign up in Anthropic Skill Jar, where Anthropic Academy, and understand how the AI works, what is the basic LLM and how the agentic development happens. So, this is the initiative. And second is within my group, my team group, I also had, as I said, weekly half an hour to 40 minutes of learning sync-up, where everybody is supposed to share what new things they have learned. And that forces everybody to learn something new as well. And that is how everybody gets benefit out of it. So, just these are the initiatives which I took, which is getting attraction and the benefit as well. Now people in my team and overall, they understand the AI, they understand they can work with Claude 4 work, they can work with Claude code. So, that is how their productivity is increasing, and they are having more, they are getting the job done. Quantifiably, I cannot define, but broadly, when I'm talking to the team members, they are saying the statement that they are more productive now, they understand the fundamentals how AI works, rather than just a black box, where you are just using it as a chatbot. So, and everybody is on a weekly basis improving and integrating some of the AI workflow in their current workflow development. So, that is the learning outcome, and that is the impact outcome as well.”

Follow-up

What resistance or competing priorities did you encounter when rolling this out, and how did you adjust your approach to get people on board?

“After taking an approval from the CEO for this initiative, I took the help of HR department, HR as well, and HR has, and we both planned and basically created a team. Like there is a technical team, there is a delivery team, there is a sales team, and that is, and we created a live leaderboard as well, scoreboard as well. And where whoever is completing the course and submitting their certificate, that is moving, you know, towards the goal. And that is how the healthy competition has been created among the team members. And that is how there is a soft nudge as well to complete the course. And that is how the due to healthy competition, soft nudge, and taking the help of HR, I'm able to create the curiosity and create an atmosphere where people are learning and growing in the way. So I learned the collaboration is extremely important and these HRs and all can be able to have that much influence and that's a great way to keep track of it because learning outcome traction is also very important because for me, if I'm taking any initiative, it's important how to measure it. So that is why the HR collaboration was important, and therefore I took the help and implemented this. And right now there are around seven teams, and two teams has already accomplished 80% of the certificates among the 13 courses which it has. And other teams are also crossed around 50%.”

Follow-up

How did you know the AI fluency gap was a real organizational problem rather than something that mattered mainly to you personally? What evidence or signals did you gather before going to the CEO?

“You, basically, I have been a proactive learner, and my company has been in the service sector and doing the IT implementation for the various enterprise clients. So, when I was basically experimenting with it and I realized the importance of, rather than going with hype, I integrated the AI learning in my personal workflow and my, you know, work, official workplace. I realized it has some significant improvement which has been made, and those learning outcomes I shared with my CEO in terms of how we can automate the daily tasks, how we can automate the client requirements. So, for example, rather than relying on the UI/UX, I started using Clotco, Clot design, one of the features of Clod, and through which I was able to give the prototype, UI/UX prototype to the client. And if the client is agreeing on it, I do not need to rely on the UI/UX team. And after taking some help, I can, and with the Clotco, I am able to do the designing faster. So, this is one of the examples. There are so many other examples as well, like Clod Code, agentic AI development and all. So, that is how I am improving a lot. And that was a very clear-cut way to convince the CEO as well to get that benefit to the organization as well. And to be very honest, AI is something which everybody is aware of. So, convincing was not that difficult. But that course is Skilljar courses, which very beautifully and in a simplified way explained things. So, that was a contribution to create that awareness of those courses. That was my initiative, and then HR collaboration was my initiative to implement this feature in the organization level.”

Follow-up

What specific signals are you tracking, beyond team members saying they feel more productive, that would tell you this initiative is actually delivering business value for your company or clients?

“So, basically, we, so this is the, I will not say just my initiative, but there was the management initiative where they also added a 20 lakh rupees of reward pool, where if the project is getting fulfilled, like getting completed on time, that will be shared in the form of an incentive. So, generally in this company, my company, there is always a project gets delayed, and there will be a lot of escalations, and that has become a very prevalent scenario, and that is why the management has come up with this idea that they will create a 20 lakh rupees of cash pool because to avoid the project overrun, and that's a big, big issue. So I also collaborated with the PMOs of all the projects. And it is happy to know that this time with the AI initiative also in place, and the individual incentive is also acting as a booster, but AI has multiplied that effect. And now this time, that 20 lakh rupees cash pool has been kind of exhausted in two months only because there are so many projects which has been almost completed on time, which was not the case earlier. So I think when the people already have the motivation, and when they try to complete it, AI acts as a multiplier, and these agentic workflow which has been integrated and the AI workflow and AI tooling has helped the team to close the projects on time. And that is a direct significant impact, and that is the biggest metric for me that the AI is working for them, for the company as a whole.”

Feedback

👍 Good answer. You're doing great!

---

Summary

This is a solid pass for mid-level. You show real initiative, constructive cross-functional influence through HR, and a concrete business outcome tied to the initiative. The main gap is that your problem identification leans heavily on personal conviction rather than pre-existing organizational evidence, and the ambiguity-handling story lacks a clear scoping or phasing narrative. Tightening those two elements would make this a strong answer.

What went well

- You identified a real organizational gap (AI fluency) and connected it to a business pain point (project delays and escalations), which gives the initiative legitimacy beyond personal interest.
    
- Your HR collaboration and leaderboard design show genuine cross-functional influence. You understood that a technical nudge alone wouldn't drive adoption and brought in the right partners.
    
- The final follow-up surfaced a compelling, quantifiable outcome: the 20-lakh incentive pool being exhausted in two months due to on-time project completions, which is a strong business-level result.
    
- Certificate completion rates across seven teams (two at 80%, others at 50%) give concrete adoption signal, which is exactly what mid-level interviewers want to see.
    

What needs improvement

- Your problem validation story is weak. When asked how you knew this was an organizational problem, you mostly described your own personal productivity gains rather than signals gathered from peers, managers, or clients before going to the CEO.
    
- The ambiguity-handling dimension lacks a scoping narrative. You jumped from 'talked to the CEO' to 'HR collaboration and leaderboard' without explaining how you defined the scope, sequenced the rollout, or handled any teams that were reluctant to participate.
    
- The ownership framing is slightly inflated in places. The 20-lakh incentive pool was a management initiative, not yours, and conflating it with your AI initiative makes it harder for the interviewer to attribute impact cleanly to your work.
    

Suggestions to improve

- When describing problem identification, lead with external signals rather than personal experience. For example, mention specific conversations with team leads, recurring client complaints, or observable delivery metrics you noticed before approaching the CEO. This makes the problem feel discovered, not invented.
    
- Add a brief scoping story to your ambiguity-handling section. Explain how you decided which teams to start with, what a 'phase 1' looked like, and how you adjusted based on early feedback. Even one sentence like 'we started with the delivery team as a pilot because they had the most urgent deadline pressure' would significantly strengthen this dimension.
    
- Cleanly separate your initiative from the management incentive pool when describing impact. Say something like 'management had already introduced a cash incentive for on-time delivery, and my AI fluency program acted as a multiplier on top of that.' This is actually a stronger framing because it shows your work amplified an existing investment, rather than blurring credit.
    

Questions Behind the Question

Interviewers are trying to gather detail which helps them feel more confident about their assessment. It's their job to ask questions to get this signal, and it's your job to provide a rich answer which helps them feel like you've performed at level.

✓ Confident

You provided enough detail for the interviewer to assess these areas.

- Did the candidate identify a problem worth solving, rather than just an interesting side project?
    
- Did the candidate create clarity and momentum in the face of ambiguous ownership?
    
- Did the candidate influence others constructively rather than acting like a lone hero?
    
- Did the candidate follow through to measurable adoption or impact?
    
- Was the candidate's ownership calibrated to their level rather than inflated or passive?
    

Think we got it wrong?Report bad feedback

Behavioral Practice | Hello Interview



###### Behavioral Practice

O

Other

Mid-level

Q6

Session debrief

This was a Hire interview

###### at **Mid-Level**

Some answers flirt with senior-style breadth in ownership and business framing, but the missing rigor around results, stakeholder validation, and communication keeps this solidly in the mid-level band.

Overall

###### Give me an example of a tough or critical piece of feedback you received.

“So, first-time client escalated my management that they're losing confidence in whether the work is progressing or not, and they were not confident that the project will complete on time. So basically, my company is a service-based company, and what happens is there is an MSME, like one project which I was working on, an MSME self-assessment portal. And I had, I built, you know, I took a technically sound order, which is where I was building the architecture and then API contract, backend development, and frontend development, which comes together fast when the backend is solid. But in this process, I had nothing to show to the client because client wants to see things visually. And because of that, and there is a little bit of lack of communication as well in terms of work progress, and that led to, and because we were working on a very strong deadline and aggressive deadline, the client has escalated the issue. So what I did was I didn't get defensive, and I didn't, I owned that part because what happens is the first-time client, first-time customer who has not worked with me, and they do not have the, you know, any past experience to bank on. So that is where I put myself in the issues and realized that they have paid the money and the deadline is aggressive, they cannot go to another vendor, and their anxiety is the right reactive measure which they have taken. So what I did was rather than sticking to my technical sound order of architecture, then backend and frontend, I created a 20% vertical layer where even though my backend development was not completed, but I created a frontend layer as well and integrated the frontend and backend and deployed the project as well. And then I showcased that particular part to them and told them that why, explained them why we are not starting with the frontend completely, we are working on the, focusing on the backend. And once the backend will be developed, it would be relatively far more easy to complete the frontend as well. So, and I also told them that we'll, you know, share the progress on every alternate day on the form of an email, and we will have one sync-up every week where we'll showcase the visual demo as well. So the result was that the client got the confidence back, and finally we shipped the product as well, where the earlier, the clients of MSME were generally taking 60 minutes to complete the self-assessment in the portal, and now it is taking around 10 minutes only. So the learning for me is that we cannot just think from the technically correct sequencing way, we have to see end-to-end and from the stakeholder point of view, who are one-time customer. Confidence is very important, and tangible output is extremely important. Because if you want to gain the confidence, you have to give them something tangible to bank on. So that is how I started. This is the learning, and from the next client onward, I always ship some 10 to 20% of the frontend end-to-end as well, the backend as well, and I deploy it so that customer will get the confidence that okay, things are moving as well.”

Follow-up

After the project shipped, did your manager or the client give you any direct feedback on whether the communication changes you made, the alternate-day emails and weekly demos, actually restored their confidence? What did that feedback sound like?

“Yes, so as I mentioned that the earlier feedback when the client escalated was not, was a little hard to digest that they're saying that I'm not competent enough to handle the project. But once the project is completed and I shipped, we also got a client testimonial as well that my company has the capability to ship the product end-to-end, and they are happy and satisfied with the end result. In terms of what feedback I got from my manager as well that this is a service-based company and you have to, you cannot, you know, that you have to keep your environment also in the loop. If you would have been working in a product-based company where you have that abstraction and you can process because you're working in the internal projects and if you're working in the in-house project of a product, then you can work in the way you want and you can go on more technical way of sequencing which you have adopted in terms of architecture, backend, and then the front-end integration and finally deployment. But when you are building for the client, the client is someone who does not have any prior relationship. And it becomes very important that we get that confidence because we may end up losing a client because initially they're just given the token money only. So, and you need to be very careful that having just losing a client is not just a money loss, but a reputation loss as well. So that will further hurt, you know, hurt in the future as well. So it's important to take the, put yourself in the client's shoes and give them something tangible so they can have a trust. And that is how once you build and gain that confidence, they'll not only come back, but at the same time, they bring other customers as well. So that is how the feedback changed and that is what the feedback I got after the shipment of a product.”

Follow-up

What specifically did you do to diagnose why the escalation happened in the first place? Did you have a structured conversation with your manager or the client to understand the root cause, or did you piece it together on your own?

“As I said earlier as well that these are two things. One is the communication gap from my end. I have not explained properly the pedagogy which I was following to the customer. And the customer who are non-technical do not appreciate, are not able to appreciate the way architecture is designed, back-end is designed, front-end is designed. So, basically when I talked to the customer as well, they said that the two weeks has passed, but we have not seen anything tangible. And what you are doing, I can't see, and we, because we have very less time, and we cannot go to another vendor as well, and therefore we felt that we are trapped, and we made a wrong call, and that is an anxiousness. So, and that is what I got from the customer that that's the very reason they escalated. And that is a pretty illegible reason which they have given, and I understand. Therefore, I took this measure where I proactively showing the progress to them, proactively through email and the weekly demo. And also, I realized that we cannot hold the front-end development. We have to keep the customer in loop via UI/UX team, and then basically building some layer of front-end as well to make the customer, give them the sense of peace and calm.This customer has been now working with us for the third time, and now he does not have any issue because he have that confidence now, and he can bank on it because we already worked for him for two times and we shipped the product. The third time, he has that confidence and he gives us that leeway because he is confident that he will get the end product.”

Follow-up

Did the client or your manager ever give you specific feedback on the alternate-day email updates and weekly demos themselves, not just on the final product outcome, and if so what did they say?

“So, weekly demo and alternate day of work progress is, in my company, there is no managerial role much because I used to handle client end-to-end, and I was a point of contact. So, generally, all the feedback is, it's like, I understand the client, and I change the pedagogy according to the client. So this is the mutual consensus which we gained when I talked to the client, and he said to me that, we want to be in the loop, I want to be in the loop according to, and he wanted that the upgradation and update should come as soon as possible. So he said that daily would be a little hard because there are other works as well, but I can give you meaningful progress in every alternate day, and I can show you the demo as well on a weekly basis, so you will be in the confidence. So this is, it's like mostly we decided mutually. Me and the client have decided mutually how to progress and how to take the, because some customers are more chilled side and they like, they are more flexible and generous, and some are not. So there is no one fixed rule, and I generally, when I talk to client, I understand now and take how they want to get updated, whether they want to have a daily alternate day, 10-minute call, or for the email is more than sufficient, or they want to get updated on a weekly basis. So there is no hard and fast rule. So that is what the thing is. And here, I did not get the feedback. Basically, the feedback itself given by the client. So it's like, we agreed on the same page and the client said, okay, it works for him and this time. That weekly alternate day email and one for a week visual demonstration of a whole week progress.”

Feedback

👍 Good answer. Nice work!

---

Summary

This is a solid mid-level pass. You demonstrate genuine ownership, concrete action, and a durable process change that you now apply to all clients. The main gaps are that the feedback story edges toward a process/communication miss rather than a deeper judgment gap, and your diagnosis stays at the symptom level without showing how you separated the root cause from the surface complaint. Tightening those two areas would make this a strong answer.

What went well

- Your ownership is genuinely strong. You put yourself in the client's shoes, acknowledged their anxiety as legitimate, and never deflected blame onto unclear requirements or the client's non-technical background.
    
- Your corrective actions are specific and durable. The 20% vertical slice, alternate-day emails, weekly demos, and the explicit policy of always shipping a thin end-to-end layer for future clients all show repeatable behavior change, not just good intentions.
    
- The repeat business from the same client is a credible, concrete signal that your changes actually worked, which is exactly what interviewers want to hear for closing the loop.
    
- You showed good self-awareness about the service-company context, recognizing that a technically correct sequencing approach doesn't translate when the client has no prior relationship to bank on.
    

What needs improvement

- The feedback itself (client couldn't see visible progress) is real but sits at the process/communication level. For a mid-level candidate, a stronger story would involve feedback that exposed a pattern affecting team effectiveness or delivery judgment, not just a sequencing choice.
    
- Your diagnosis stays at the symptom level. You identified two causes but didn't show a structured conversation that separated the root issue (a mindset about what 'progress' means to a non-technical stakeholder) from the surface complaint.
    
- Closing the loop relies on the final outcome (testimonial, repeat business) rather than direct validation of whether the specific communication changes, the emails and demos, actually addressed the client's anxiety during the project.
    

Suggestions to improve

- To strengthen the feedback dimension, frame the escalation as exposing a real gap in your judgment: you optimized for technical correctness over stakeholder confidence, and you didn't recognize that in a first-time client relationship, perceived progress matters as much as actual progress. Name that as a judgment gap, not just a process miss.
    
- For diagnosis, add one sentence showing you went deeper than the surface complaint. For example, you could say you asked yourself why you defaulted to the backend-first sequence without checking whether the client had any visibility into it, and realized you had assumed technical sequencing was self-evidently correct to everyone.
    
- To close the loop more strongly, mention a specific moment mid-project when the client's tone shifted, or a direct comment they made after one of the weekly demos, rather than relying only on the end-of-project testimonial and repeat business.
    

Questions Behind the Question

Interviewers are trying to gather detail which helps them feel more confident about their assessment. It's their job to ask questions to get this signal, and it's your job to provide a rich answer which helps them feel like you've performed at level.

✓ Confident

You provided enough detail for the interviewer to assess these areas.

- Was the feedback substantive and credibly difficult to hear?
    
- Did the candidate show honest ownership rather than defensiveness?
    
- Did the candidate investigate the feedback deeply enough to understand the root issue?
    
- Did the candidate take concrete, sustained action to improve?
    
- Did the candidate close the loop by measuring whether they had improved?
    

Think we got it wrong?Report bad feedback

Behavioral Practice | Hello Interview