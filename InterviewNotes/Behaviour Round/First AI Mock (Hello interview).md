
##### What project are you most proud of?

“So what questions I am proud of? So so for the in the last year, I have been building Tenisage TeriSage is a a multitenant b to b product. Real estate product in the real estate sector that have been doing it, and I've been building it for around eight to nine months. As a solo developer. This is a product which has come to me through my family members, and I have been responsible to handle the technical side of it. So I have done the whole architecture. I have built a whole back end and up to some extent the front end as well. So this is what the whole product, and I delivered it as well, and that is in the apps and it is in iOS available And it is it has a web version as well. Technology stack, which I used is Nexia's in front end React Native and the Wilder development side. And Node. Js Express. That is what I've used.”

###### Follow-up

###### What was the hardest technical or product decision you had to make while building TeniSage, and how did you work through it?

“Yes. So hardest and technical part So according to me, If if I talk about the architecture side, so the multi tenant architecture and so we we I have to take a call. Should I go with the multi currency in the from the day one, or should I wait for it? But I did have the experience of multi tenancy architecture b to b SaaS based application earlier. So I went ahead with the multi tenant architecture on the day one, and I chosen low level multitenancy to avoid the complexity in the in the run and separated every tenant data on the basis of the tenant ID itself. The other architectural things like implementation side, I had a problem is the integrations. The third party integration. So this particular real estate application, what happens is the agent do run ads in the Facebook meta and all. And, therefore, my app has give the permission to link their website to tenant to link their website link their Facebook ad and all, and those lead will converge and come to the my in my TeriSys server. And here, I have to take care of the privacy as well because the meta has their own rules and regulations. And so that was a challenging part also there is a little bit of hesitancy on the terms of the clients who are saying about the their their data protection and leakage issue. So I had to tighten the security as well. Apart from that, the one more issue which was coming is the AI side because we have added some AI features in the application like voice to text-ray transformation and if somebody is giving any kind of a property description, because property is an integral entity in this application. In that scenario, if the wrong dump will come, that should be able to auto fill in the property form. And that was working in some scenarios. Sometimes it's not working. And the building, the reliable data extraction pipeline was an issue. And then I learned the importance of eval system prompting tweaking, and so that is how we are able to achieve the accuracy up to a great extent. And and the the overall the building things on the uncertainty because you do not know the fixed scenario and the customers are changing the requirement you are taking the feedback, So you are building with uncertainty. So you have to be very cautious in that. Scenario as well. So that was, you know, overall hardest technical side. Apart from that, couple of other technical issue which has happened is the the bug fixing. Whenever the testing is happening, it will always keeping bugs alive. Even the the modules which are tested thoroughly. When you are adding new feature, you are touching the older modules as well. And then older modules also getting the bugs. So was, like, a circular labyrinth, which is not getting finished at any point of time. So, therefore, I started writing integration test I have integrated the tools I started integrating tools like Uptime Robot and the the error tracking tool like Sentry. So I integrated Sentry as well, picked up the issues which is getting logged. So that is how I reduced the overall and then improve the accuracy of our product as well.”

###### Follow-up

###### How did the product perform once it launched, and what changed for the clients or users who were actually using it?

“So to be very honest, right now, we have trial customers. We do we are trying because we are trying to find initial and we do have five to seven trial customers, and the trial period is for a month now. Because that is where we are finding the bugs and trying to understand expectation. Of customers up to a great extent when when they are using it and all. I also got to know about Hotjar and also to understand the user experience and the user analytics, which is easier way to for me to understand the user behavior and how the user is performing. So the product is not completely full fledged to launch. It is in their trial phases. It is in the hands of a customer, but we do we are till trying to find the you know, the paid customers. So this is the I want to be very, very clear here. So when when we are using and the clients are requesting a couple of features in there, and that is so for one of the instances, the client are the big clients. They are saying that how can I be ensure that you are not going to tell give the leads to my competitor? Right? And that is a very technical the on the tech side, it's very hard to solve because the data is in our hands. And I also thought of to you know, hash the data as well. But if if I hash the table, altogether, the problem will start coming is that, the efficient query right, how to retrieve the data. That that data will become, like, a full table scan where every row you have to you know, unhash, dehash it, and then you have to read it. And then hash it again. So those are the challenges which has started and which is still I'm trying to resolve because customer are coming with their own prejudice and sometimes their own insecurity, but their insecurities are real. And in the real world scenario, these things are happening. So they are concerned with the privacy side, the data leakage side, and the computer should not get ahead and all. And therefore, we, as a middle layer, has to be very, very responsible to it. So it's not a technical one. More working on the security side of our data.”

###### Follow-up

###### When trial customers pushed back on your data privacy guarantees, how did you decide what to build versus what to defer, and who was involved in that call?

“So right now, the team size is just one CEO, one tech. One like, two team members, like, a tech team members. So call is generally taken by me and the CEO only. And differing what to build and what to defer is always depend upon the the time we have and how fast we can ship and what is the low hanging fruit and what is the, you know, high ending fruits. So so it it's never be, like, very one fits for all, like, scenario. For example, privacy is the concern of a very, very large clients who have, you know, millions dollar of a revenue. And for them, it's very important. But the privacy is not a concern for most of the clients who are not so big. And for them, secure rather than security lead generation is far bigger issue. So these are the the things, and therefore, we are not focusing on the privacy concern right now. But, obviously, that is in the list and that is also how we decided depends upon the first side because I am the sole developer in this product. One is our front end side, but deployment, development, and the back end ensure resilience, ensuring reliability is all my job right now. So that is what I've been focusing on.”

###### Follow-up

###### Given that you built TeniSage largely on your own, were there moments where you brought in outside expertise, sought structured feedback, or created documentation or processes that helped someone else contribute to or understand the system?

“But I am open for outside expertise as well when I will reach scale, then I will need outside expertise as well.”

You're on the right track.

---

Summary

You chose a genuinely impressive project for a mid-level candidate, and your ownership and technical depth come through clearly. The main gaps pulling this down are the absence of concrete outcomes (the product is pre-revenue with only trial users, and you don't quantify any improvement) and almost no team uplift signal. Sharpening the outcomes framing and adding even one example of creating leverage or process for others would move this to a solid pass.

What went well

- The project scope is strong for mid-level: you owned architecture, backend, deployment, and reliability end-to-end for a real B2B SaaS product with paying-intent customers.
    
- Your ownership is admirably clear and honest. You distinguish your role from the CEO's, acknowledge the product is still in trial, and never inflate your contributions.
    
- You surface real technical constraints: multi-tenancy design decision, Meta integration privacy rules, AI extraction pipeline reliability, and regression management with Sentry and Uptime Robot.
    
- The hashing tradeoff analysis (privacy vs. query efficiency) is a good example of reasoning through competing concerns rather than just picking an option.
    

What needs improvement

- Outcomes are the weakest part. You honestly disclose 5-7 trial customers and no paid revenue, but you don't name any measurable improvement, such as bug reduction rate after Sentry, latency numbers, or user retention in the trial cohort.
    
- The tradeoff reasoning is present but underdeveloped. You explain what you chose but rarely walk through what you explicitly ruled out and why, which is what interviewers at mid-level want to hear.
    
- There is almost no team uplift signal. The final follow-up answer was essentially a one-liner deferral about future plans, with no mention of documentation, runbooks, onboarding materials, or any process you created that someone else could use.
    

Suggestions to improve

- Even without paid customers, anchor your outcomes to something measurable. For example, talk about bug escape rate before and after Sentry, the number of AI extraction failures you reduced, or how trial customer feedback shaped a specific product decision.
    
- When describing tradeoffs, explicitly name the option you rejected and the reason. Instead of 'I chose low-level multitenancy,' say 'I considered schema-per-tenant but ruled it out because migration complexity would have blocked us from iterating quickly at this stage.'
    
- Add at least one team uplift moment, even in a solo context. Did you write an architecture decision record, a deployment runbook, or a setup guide so the CEO or a future hire could understand the system? That counts as leverage at mid-level.
    
- Tighten the narrative structure before you tell this story. Lead with the business context and the outcome, then go into technical decisions. Right now the story meanders across topics, which makes it harder for the interviewer to follow your reasoning.
    

Questions Behind the Question

Interviewers are trying to gather detail which helps them feel more confident about their assessment. It's their job to ask questions to get this signal, and it's your job to provide a rich answer which helps them feel like you've performed at level.

✓ Confident

You provided enough detail for the interviewer to assess these areas.

- Was the chosen project meaningfully scoped for the candidate's level?
    
- Did the candidate make their personal ownership clear without overstating solo heroics?
    
- Did the candidate explain what made the project genuinely difficult and how they navigated it?
    
- Did the candidate connect the project to concrete outcomes and why it mattered?
    
- Did the candidate show judgment in tradeoffs and decision-making, not just execution?
    

? Unsure

The interviewer got some signal but may want to probe deeper in these areas.

- Did the project reveal leadership or team uplift appropriate to the candidate's level?



##### Tell me about your most difficult working relationship

“So, recently what happened is we have been building JagoAI product, which is a flagship product of VLine. And so, we have been building it for a long period of time, around two years. And what happened is that we get feedback and all, and we make so many changes. So, the UX has fallout very badly, and therefore it is a little bit hard to understand the product for the new people. So, therefore, the CEO has instructed the UI/UX team to revamp the UI and make it a better UX flow of the entire product. The UI/UX team has taken time and came up with the revamping. And because I have been handling the full stack side of it, being a four-year experience, we do have a four-people team, two front-end developers, two full-stack developers, along with me. So, generally I do take care of customer interaction and the CEO interaction as well for the full stack related work. So, when this thing, revamping came, CEO called me, and he wanted this revamping to be done in two days. According to him, the AI advancement has been taken place. And through AI assistant coding, IDs like Cursor and all, this revamping could be done in a much faster pace. So, that is the context. And therefore, I took my time and I created a risk mitigation plan because I knew that in two days it would be very difficult to complete the whole revamping of a product which has been going on for a long period of time. So, therefore, I created a risk mitigation plan where I told him that even the UI revamping is not just a, you know, UI, like just a HTML changes, it's like a data layer along with it, API contract. Everything is there which can hamper and can have a catastrophic effect as well if we do not take care of everything properly. So, he understood and appreciated. And therefore, he said that, okay, go ahead with your plan and take some time, but get the job done as soon as possible. So, therefore, I divided the work. And how I divided the work is that the modules which the team has taken, the person who has taken the earlier modules, I gave the same modules to them again so that they will have the complete understanding of those modules. And we completed the task in around seven to eight days. And in that process, every two days I showed the progress as well, and broadly he was satisfied with it. So, the learning side what happened was, the AI coding has improved a lot, and this would not be possible to do even seven to eight days. And we are able to complete this work of at least a one-month work in seven to eight days. So, that is a drastic improvement. And generally, the conflict between me and CEO happens regarding the shipping ability and all. And I always, the tussle is that if you are building any greenfield project, which where the AI have the complete liberty, then you can ship far, much more faster. But when you have the code base which is already there, and when you have to tweak and revamp, then you have to be very careful and take care of other scenarios. Sometimes this become a point of contention between me and CEO, but we do resolve the issue in more fact-based way.”

###### Follow-up

###### What did this experience change about how you and the CEO work together on timeline discussions now, and did it shift anything about how you personally approach those conversations?

“So, generally, what I realized with him is that, like, you cannot expect a non- like, you have to be a little bit different when you're talking with a technical founder people or non-technical person. Both have a different way of understanding. So, whenever you are talking to a non-technical person, they do not understand the complexity. And that is fine with it. The only way is that you have to express the concern and pitfalls in their own language, so that once they understand and appreciate the depth of our work, then they also appreciate. So, you cannot expect without clear communication in their tonality, in their understanding, in their own vocabulary. And if you think that without being vocal about it, that not gonna happen. So, the first and foremost thing is talking their language, number one. Number two is that, do not react whenever any hard deadline comes in and very aggressive deadline. That generally also matters on whether it's internal projects or external projects. So, and you also need to understand the CEOs generally give you the aggressive deadline because they want to get the job done as soon as possible. And they want to create a healthy sense of urgency. And that's their intent. And that is also good enough because that is how everybody push. So, once you put yourself in their shoes, you will be able to appreciate why they put that kind of aggressive deadlines. So, for me, what I need to do is that, I obviously need to maintain the pace. But at the same time, we cannot compromise on the quality. Okay? So, and the biggest thing is that what I realized with working with my CEO is that, you just show up and show your progress, even, and there should not be a lack of communication. So, even if you are not completing the work because of the aggressive deadline, but if you show that you have put in complete effort and you have made good progress, even though the project is not completely completed, but he appreciate and give you the time as well. So, what matters to the CEO is the intent, right? Intent and the personal effort. If these two things are there, then there will be a mutual harmony and we able to work together properly. So, that is what my learning with him.”

###### Follow-up

###### Were there any moments during the revamp where things got tense or went sideways, and how did you handle it in the moment with the CEO or your team?

“I will not say in that scenario things went really bad or very sideways. There is also one of the other scenarios which I will say is that generally, I also have one of the team members who is hard to work with. And so he is in, for example, the Chatbot AI product is the product of a full stack and the AI component is also involved. So there is an AI team which also works. And there is one person who is extremely good at it, but in his work. But what happens is that he do not like to, you know, work in a collective environment. So he has their own way of doing work, and he is like a lone wolf. The problem sometimes happens is that, for example, API integration. And so what happens is that sometimes he changes the response, he changes the request cycle, and that creates a big problem because things break. And according to him, things are working in his own space, and he do not care too much on those whether the product in itself is working or not. So because he generally works as an independent team member on other projects as well. So generally, what, he and he is a little bit hard to work with. So what I did is that I tried to understand his ground, I tried to understand how he has been working. And when I'm able to understand empathetically, I realize that, okay, this is why it is and how he is working as it is. So what I like, we had so many contentions, but one of the things which we realized is that he do not like to interact too much with the team members. So I told him, whenever you are making any changes, it's very important, just shoot one email, even if you are changing, at least I will know this is a change and that's a, you know, breaking change. So keeping that in mind, if you will just document, if you just send one email, that is more than enough to be a little bit aware of and do the changes accordingly. So that is one of the way where in that scenario, what happens is things got escalated because just imagine the product is working and then it is not working. And you realize that there is no mistake from your end. But the only thing is that the way you are sending the request to the AI/ML team, and that AI/ML team is now accepting the response in a different way, and they are not flexible enough, and they are rejecting the request response which is coming from the full stack side because of the schema which they have changed in the first place. So that is frustrating and sometimes the demo team do not understand, they just, they do not know where the problem is. But because we are the full stack side, we are the client-facing interface, so we sometimes have to handle that problem. So these are one of the other instances of conflict scenarios. But at the same time, we have been working together with that particular person, and now we are in that scenario where the clear communication through email is happening, and we have reached some consensus level.”

###### Follow-up

###### How did the AI engineer react when you first proposed the email notification agreement, and what did you do if he didn't follow through on it?

“Yeah, so, basically, see, everybody has some accountability and up to some extent. The only thing which I did was making his work easy. He do not like to take initiative in that sense, and he do not want to proactively, you know, check things and the whole product is working fine. So, that burden of proof I took it on my end, and the bare minimum information which I need from him that what is the schema change, what is the request response cycle, is now currently. So that is what the expectation I had, and that was a very bare minimum which you require to get it. So therefore, he agreed on that part. And so, the one thing. If we just imagine the scenario where he would not even work and do not notify when he's changing that through email itself, which is the very least. Then one thing which I could do is that I would have to proactively checking whether the product is working or not, whether that API endpoint is working where I'm sending the response to the AI side. If not, then maybe something has changed. So I will have to ask him directly what has changed. And just imagine if that is also not working, then I would have to escalate the issue up to maybe just my manager, not the very high level, but just a manager, so that he will also understand and maybe he can help me out because I exhausted all my way of resolving this issue.”

You're on the right track.

---

Summary

You show genuine empathy and self-awareness, which are real strengths here. The two stories you chose are relevant and grounded in real consequences, but the ownership actions and resolutions stay at a surface level for mid-level expectations. Sharpening how you describe what structurally changed in the working relationship would move this to a solid pass.

What went well

- Your empathy is genuinely strong in both stories. You articulate why the CEO sets aggressive deadlines (healthy urgency, intent) and why the AI engineer works the way he does, treating both as rational actors rather than difficult personalities.
    
- Your self-awareness in the follow-up is specific and behavioral. Insights like 'speak their language,' 'don't react to aggressive deadlines,' and 'show progress even if incomplete' reflect real learning that changed how you operate.
    
- You proactively created a risk mitigation plan with the CEO rather than just complaining or complying, which shows mid-level judgment about how to handle authority-driven pressure.
    
- The AI engineer story is well-chosen because the impact was concrete: the product broke in ways that were invisible to the demo team, creating real delivery risk.
    

What needs improvement

- The resolution for the AI engineer story is vague. 'We have reached some consensus level' does not tell the interviewer what actually changed in the working pattern or whether the integration breaks stopped happening.
    
- The ownership actions in both stories are relatively minimal. A risk mitigation plan and an email agreement are good starts, but a mid-level answer would ideally show a more deliberate effort to reshape the collaboration structure, such as a recurring sync, a shared schema contract, or a documented handoff protocol.
    
- The CEO story drifts toward a timeline negotiation rather than a true relationship difficulty. The rubric expects a relationship where friction had real impact on delivery or trust, and the CEO story resolves fairly quickly without much sustained tension.
    
- The answer is long and covers two separate stories, which dilutes focus. A tighter single story with more depth on resolution and outcome would be more effective than two stories with thin endings.
    

Suggestions to improve

- For the AI engineer story, close the loop explicitly. Describe what changed after the email agreement: did the integration breaks stop? Did the demo failures go away? A concrete outcome like 'over the next sprint we had zero unannounced schema changes and the demo went cleanly' would make the resolution land much stronger.
    
- Elevate the ownership action in the AI engineer story. Instead of just proposing an email, talk about whether you proposed a shared API contract document, a lightweight schema versioning convention, or a brief weekly sync. These show you reshaped the collaboration structure, not just asked for a courtesy notification.
    
- Choose one story and go deep rather than covering two. The AI engineer story has more of the relationship difficulty texture the question is looking for. Lead with that, and use the CEO story only if asked about a second example.
    
- When describing resolution, explicitly contrast before and after. A phrase like 'before this, we were discovering breaks during demos; after the agreement, I had advance notice and could test proactively' makes the improvement in working effectiveness concrete and memorable.
    

Questions Behind the Question

Interviewers are trying to gather detail which helps them feel more confident about their assessment. It's their job to ask questions to get this signal, and it's your job to provide a rich answer which helps them feel like you've performed at level.

✓ Confident

You provided enough detail for the interviewer to assess these areas.

- Was the relationship difficulty meaningful and professionally consequential?
    
- Did the candidate show empathy toward the other person's perspective and constraints?
    
- Did the candidate take ownership for improving the relationship rather than just enduring or escalating it?
    
- Did the candidate show self-awareness and learning from the experience?
    

? Unsure

The interviewer got some signal but may want to probe deeper in these areas.

- Did the candidate resolve the issue in a way that improved working effectiveness, not just win the disagreement?