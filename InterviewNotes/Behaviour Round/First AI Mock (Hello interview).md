
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