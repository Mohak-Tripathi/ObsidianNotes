
June 21, 2026·14 min read

I spent two days building this blog. Not because a blog is hard to build — you can put one online in an hour — but because I decided to build one that would still work in a hundred years. That single constraint changed every decision I made, and it turned a one-hour job into a two-day one.

This post is the whole map. If you're about to start a blog — maybe as the first step toward building an audience, or a body of work, or just a place that's yours — I want you to finish this and understand not only _what_ to do, but _why_, what I gave up to do it, and which small, undocumented mistakes cost me hours so they don't cost you any. I'll be honest about the parts I got wrong, because those are the useful parts.

## Why I didn't just use a normal tool

Every time I've set up a blog before, it has quietly broken within a couple of years. The pattern is always the same. A build tool stops being maintained. A framework releases a new major version and "upgrading" turns into a rewrite. A font host changes its terms or starts injecting tracking. A free hosting tier disappears. The words I wrote are still fine — but the machinery around them has rotted, and one day I go to publish a new post and discover I first need three days of repairs.

So I asked a different question. Not "what's the easiest way to start a blog," but "what would a blog look like if I built it to survive the tools I built it with?" Everything below is the answer.

## The one rule everything else comes from

> Own the permanent things. Rent the swappable ones. Never add a dependency you can't live without.

That's the whole philosophy. The trick is knowing which things are which.

You **own** three things: your _domain_ (your address on the internet), your _content_ (the actual files), and your _email list_ (the people who chose to hear from you). You **rent** everything else: the company that hosts your files, the tool that sends your emails, the platforms you share on. The rule is simply: never let anything in the "rent" column hold something from the "own" column hostage. As long as that's true, any rented piece can die or misbehave and you lose nothing permanent — you just swap it out.

## The mental model, before touching anything

It helped me to see the whole system as four layers before I built any of it.

**Creation** is the blog itself — your files, your permanent archive. **Distribution** is how people find it, and it has three channels worth naming. _RSS_ is a single file on your site that lets anyone subscribe to you in a reader app of their choice, with no platform sitting in the middle. A _newsletter_ is a list of emails you control, so you can reach people directly. _Social_ is reach you borrow from someone else's platform. **Consumption** is where people actually read — a reader app, an inbox, a feed. **Monetization**, if it ever comes, is the last layer and an optional one.

Two distinctions inside that are worth holding onto. The first is _push versus pull_: RSS is pull (the reader checks your feed when _they_ want), while a newsletter is push (you arrive in their inbox when _you_ publish). The second is _ownership_: with social and RSS you get reach but no way to contact anyone; with an email list you can export, you own the relationship. You build an audience with social, you _keep_ it with email, and the blog is the home both point back to.

## The foundation: a domain you actually own

A free host gives you an address like `yourname.github.io`. That address belongs to the host, not to you. The moment you ever move — and over a hundred years you will move — that address breaks and takes all your links, bookmarks, and search ranking with it. A domain you own is the one address that survives every move. It's the most important purchase in the whole project.

I bought `mohaktripathi.com` — my own name. I was tempted by a trendier ending like `.ai`, because it sounds cool right now. I talked myself out of it: "right now" is the problem. Trends date, that ending costs much more to renew, and it would chain my whole identity to one topic. A plain `.com` with my name on it will never feel dated, because a name doesn't go out of style — and any "coolness" is supposed to come from the writing, not the web address.

Two things matter more than which registrar you pick. First, turn on **auto-renew** immediately, because a domain you forget to renew is the one and only thing that can truly end a hundred-year plan. Second — and this is a tiny, real lesson — **check your cart before paying**. My discount code didn't apply automatically; the price only dropped once I entered it by hand and watched the total change. Registrars try to bundle in hosting and email you don't need. Buy the domain. Decline the rest.

## The site: plain HTML and one CSS file

Here is the core durability bet, stated plainly. A web browser from the 1990s can still render a plain HTML page written today. That same old browser cannot run a modern JavaScript framework, a build step, or anything that depends on a server staying alive. The `<p>` tag has worked for thirty years and will keep working, because browsers protect old pages more carefully than almost any other software protects anything.

So the rule for the site is: plain HTML and one CSS file. No framework. No build step. No _build step_ means there is no separate "compile" command between your files and the live site — what you write is literally what gets served. No packages to update, no external fonts fetched from someone else's server, nothing that needs to still be maintained in 2126.

Two choices inside that surprised me with how much they mattered. The first is **system fonts** — the fonts already installed on the reader's device. The usual fear is that they look cheap. They don't. They are fonts that Apple, Microsoft, and Google each spent years tuning for their own screens, and they load in zero time because they're already there. Using them means no external request, no flicker while a font downloads, and nothing to break. The second is **absolute paths**: every page links to `/style.css`, with a leading slash, never `../style.css`. The leading slash means "start from the root of the site," so the link works no matter how deep the page is buried. A relative path depends on where the page sits, which breaks the moment you reorganize.

I won't pretend this is free. The honest tradeoff: I gave up the convenience of a framework and the big ecosystem of ready-made components. What I got back is a site with almost no moving parts — which means almost nothing that can break.

## Freeze your URLs — the one decision you can't undo

You can change almost anything later: the design, the words, the host. The one thing you can't change without breaking the world is your **URL structure** — the shape of your web addresses. Once a post's address has been linked, bookmarked, indexed by Google, or shared in someone's newsletter, changing it turns all of those into dead links. There's a name for that decay: **link rot**. The fix is to decide the structure once, before writing anything, and never touch it.

Mine, frozen:

- `/` — home and about
- `/blog/` — the list of writing
- `/blog/<name-of-post>/` — one folder per post
- `/principles/` — my living list of principles

Each post lives in its own folder with a file called `index.html` inside, rather than as a single `post.html` file. The payoff is a clean address with no file extension — `/blog/this-post/` — that every web host on earth understands the same way, so moving hosts never changes a single link.

## The invisible files that do the real work

Most people who build a blog stop once the page looks right. But the difference between a private file and a publication people can find, share, and follow is a handful of files you never actually see on the page. Here's each one, in plain terms.

**An RSS feed** (`feed.xml`) is a machine-readable list of your posts. Reader apps check it and show subscribers your new posts automatically — no algorithm deciding who sees what, no platform in between. It's the purest form of an audience you don't have to rent.

**A sitemap** (`sitemap.xml`) is a plain list of every page on your site, written for search engines. Crawlers can miss pages on their own; the sitemap simply says "here is everything that exists," which helps a brand-new site get found faster.

**A robots file** (`robots.txt`) tells crawlers they're welcome and points them at the sitemap. **Open Graph tags** are a few hidden lines in the page's head that decide how your link looks when someone pastes it into LinkedIn, WhatsApp, or a chat — with them, the link unfurls into a tidy card with a title and image; without them, it's a bare, ugly URL. A **canonical tag** tells Google which version of an address is the official one, so the `www` and non-`www` versions don't compete with each other and split your ranking. And a **404 page** is just a friendly page for when someone hits a broken link, instead of a blank error.

None of these are visible. All of them are what turn a folder of files into something discoverable, shareable, and followable.

## Putting it online

The content lives in **Git** — a system that tracks every version of every file — and I push it to _two_ separate places, so no single company losing my account can lose my writing. From there, a free host called GitHub Pages turns the files in my repository directly into the live website. There's no server to run; the files _are_ the site.

The last connection is **DNS** — the internet's address book. It's what points `mohaktripathi.com` at wherever my files actually live. Set it once, and if I ever move hosts, I change this one pointer and every link keeps working.

This is where I made my first real mistakes, so let me hand them to you directly:

- **Two different things are both called "CNAME."** One is a small file named `CNAME` inside your repository that holds your domain; the other is a type of DNS record at your registrar. I conflated them and chased the wrong one for a while. They're separate jobs — you may need both.
- **The first preview looked completely broken, and I panicked.** Before the domain was attached, my site loaded with no styling at all and I was sure I'd wrecked something. I hadn't — the absolute paths just don't resolve correctly on the temporary host address, and attaching the real domain fixed it instantly. If your first preview looks unstyled, don't touch anything; finish connecting the domain.
- **"DNS check unsuccessful" is usually not a thing you fix.** It's a thing you wait out. DNS changes take time to spread across the internet — minutes, sometimes hours. I almost redid correct work because I read a propagation delay as an error. Make the change once, then be patient and re-check.

## Telling Google you exist

Once the site was live, I added it to Google Search Console. Two things happen there. First you prove you own the domain — Google gives you a code, you add it as a DNS record, it checks for it. Then you submit your sitemap, and Google starts crawling your pages faster than it would on its own.

One clarification, because I had it slightly wrong: submitting the sitemap is a _one-time_ action. You don't resubmit it for every new post. What you do per post is keep the `sitemap.xml` _file_ updated with the new address; Google re-reads the same file on its own schedule and picks up whatever you've added.

## The audience layer: a newsletter you own

Followers on a platform are rented — the platform decides who sees you and can change the rules any day. Email subscribers are owned, as long as the tool lets you export the list. That export is the whole test: if you can download your subscribers and carry them to another tool, the tool is just a swappable utility, like the host. I picked one that passes that test and wired its signup form into my pages.

More honesty, because this part had two confusing moments. During setup the form quietly had "Substack" pre-selected as my previous platform, which I'd never used — a reminder to actually read the defaults. And when I tested my own signup, the confirmation page said "Not found," which looked like a bug in my site. It wasn't: the subscriber had been captured correctly, the page I landed on was just a stale link mid-flow, and the account was still under the provider's review. Good email tools manually review new senders before letting them send, to protect everyone's deliverability — so a fresh account being "under review" for a day or two is a feature, not a fault. The form worked; I just had to wait.

## The mistakes that ate the most time

If I'm honest, very little of my two days was "building." Most of it was small, undramatic friction that no documentation page warns you about. These three cost me the most, and they're the real reason I'm writing this down:

**The feed wouldn't validate because of a day of the week.** An RSS feed stamps each post with a date, and the date includes the weekday name. Mine said "Sat" when June 21 was actually a Sunday. RSS is strict: that one mismatched word made a validator reject the entire feed. It was a typo, not a real problem — but the machine doesn't care.

**I ran the wrong validator.** To check my feed, I pasted it into an [HTML checker](https://validator.w3.org/nu/) and got a frightening error about a missing schema. An HTML checker doesn't understand feed files — there's a [separate feed validator](https://validator.w3.org/feed/) for that. Half of debugging is making sure you're even using the right tool to look at the thing.

**Caching fooled me into thinking my fix didn't work.** After I corrected the feed, the validator kept showing the old, broken version. It had remembered (cached) the earlier copy to save time. Adding a meaningless `?v=2` to the end of the address forced it to fetch a fresh copy, and the fix appeared. If a tool insists your change isn't there after you're sure it is, suspect a cache.

## What I deliberately did not do

Restraint was the hardest part, so it's worth listing what I cut and why. No framework — it rots. No content management system — for a single writer, a text editor and Git already do the job. No Substack or Medium as my _home_ — those are rented land that can outrank me for my own words; fine to repost to, never to live on. No comments — they'd need a database; I'll point people to discuss elsewhere instead. No fancy file storage for images — they just live in the repository. No trendy domain ending. The pattern under every one of these: anything that needs a server, a database, a build step, or a platform's continued goodwill got cut. What's left can't rot.

## What it cost, and what it bought

The cost was real: two days, the convenience of a framework, and a flashier look I could have had off the shelf. What I bought is a site with nothing to maintain, nothing to patch, and nothing that can break on its own; that I fully own; that I can move to a new host in an afternoon without anyone noticing; and that I'll be able to publish to in a century with the same five steps I use today. For me that trade is not close.

## If you're building your own

Here's the shortest honest path, now that you understand why each step is here: buy a domain with your name on it and turn on auto-renew; write plain HTML and one CSS file; freeze your URL structure before you write a word; add the invisible files — feed, sitemap, robots, Open Graph tags, a 404; put it in Git and push it to a free static host; point your domain at that host; wire in one newsletter form you can export from. That's it. None of it is exotic. The hard part is the restraint.

I didn't do all this to have a blog. I did it so the writing would outlive the tools. A medium is fragile or it isn't, and I chose the one that isn't. This is the first post. If you're reading it years from now and it still loads exactly as it does today — that was the entire point.

[← All writing](https://mohaktripathi.com/blog/)

### Get the next one by email

One email when I publish. No cadence, no marketing, no list-sharing. Unsubscribe in one click.

Email addressSubscribe

Or follow along by [RSS](https://mohaktripathi.com/feed.xml).

© 2026 Mohak TripathiPlain HTML & CSS · no tracking · [RSS](https://mohaktripathi.com/feed.xml)