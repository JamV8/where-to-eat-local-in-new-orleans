---
title: "AI log"
subtitle: "Key prompts, what I pushed back on, and how the answers were checked"
---

I used an AI assistant (Claude) throughout this project. My prompts were written in Russian; below they
are translated and shortened. This is not the whole conversation. It is the set of exchanges that changed
the project or my understanding of it, which is what the assignment asks for.

## Who did what

| I decided | The AI did |
|---|---|
| The theme: local food, after testing my own idea of fast food on the data | Wrote the R code, the report text and the site |
| To keep seafood in the theme, against the AI's first recommendation | Ran a test on the real data whenever I questioned a choice |
| To divide the city the way people talk about it, not only the way the data does | Looked up how New Orleans is divided, and found the planning districts |
| The four scoring rules, after having them explained twice | Checked its own work, and reported the mistakes it found (listed at the end) |
| To name one best part of town, with the uncertainty stated | Tried 24 ways of scoring areas to see whether one winner was real |
| What goes public and what stays private | Kept a log of every decision and who made it |

## Iteration 1: "Is the bootstrap required, or is it your idea?"

The AI proposed showing how stable the top ten is with a bootstrap. I liked it, then stopped.

**My prompt:** "The bootstrap you are proposing: is that something the assignment expects, or is it purely your idea?"

**Answer:** its idea. It searched the assignment text: the word never appears. The assignment asks to
define "best" using "the reliability of the comparison" and names no method.

**My next prompt:** "Is what you proposed the best there is? Keep in mind the complexity has to be
reasonable. This is Math 167R."

**Answer:** it backed off to a simpler tool, a plus-or-minus interval around each average, and computed it.

**My next prompt:** "The level of the class is something to keep in mind, but this is a university
statistics project. If there is a better option in that sense, we should probably stick with it."

**Answer:** it agreed that I was right and it had over-read my earlier message. An interval says how
well one average is known. It does not say how far a *rank* can move, and star ratings are skewed and
capped at five. Final design: intervals for the picture, the bootstrap for the number.

**My last prompt in the chain:** "Explain in simple words, as if I were ten, what the bootstrap is and how exactly it helps."

**What I took from it:** put every review of a restaurant in a hat, draw the same number back out with
repeats allowed, recompute the average, rank everyone again, and do that 2,000 times. I accepted the
method only once I could explain it this way myself.

## Iteration 2: "Maybe we should just do fast food?"

The AI found that Yelp's "Seafood" label pulls Peruvian and Ethiopian restaurants into a local-food theme.
I thought the theme was getting complicated.

**My prompt:** "If this local-food category is going to be this complicated, maybe we shouldn't take it
and should take something like fast food instead?"

**Answer, tested on the data:** fast food has the same label problem (its trial top ten held an Italian
deli, a grocery store and a gelato cafe), a quarter of its restaurants are chain locations, and the
"Fast Food" label alone has 80 active reviewers.

**Decision (mine):** local food. "It is New Orleans, so that is the food people want to know about."

## Iteration 3: "I don't want to just get rid of seafood"

The AI recommended dropping the Seafood category to keep the theme clean.

**My prompt:** "Seafood is something a lot of people love, and I don't want to drop it just because it
has problems. Maybe there is a way to handle seafood specially? Think about it, and if you still think
it is better without, then fine."

**What happened:** the AI read all 106 open restaurants that would enter only through that label. Most
were plainly local: Drago's, GW Fins, Pêche, Parkway Bakery. It said my instinct was better than its
recommendation, and wrote a rule: Seafood counts, unless the restaurant got in only through that label
and Yelp also gives it another country's cuisine.

**Result:** 608 restaurants instead of 508, with the well-known seafood houses in and the sushi bars out.

## Iteration 4: "How do people usually divide New Orleans?"

The AI recommended the 72 official neighborhoods.

**My prompt:** "I want the way we divide the city to match how other people usually divide it, so it is
obvious at once which area we mean. Could you search the web for how this is done in New Orleans? And is
my idea a good one or not?"

**What it found:** the 72 neighborhoods are statistical units, and the organization that publishes them
warns that residents picture their neighborhoods differently. The city's tourism site and its planning
commission both use about a dozen larger areas: Uptown, Mid-City, Marigny and Bywater.

**Result:** two levels. Planning districts for "which part of town", neighborhoods for the detail inside.
With districts, 99% of restaurants sit in an area large enough to compare, against 78% with neighborhoods.

## Iteration 5: "How do these rules work with the bootstrap?"

The AI proposed ranking restaurants by a reviewer-adjusted score.

**My prompts:** "Explain the problem again, and why you want exactly these four rules." Then: "Before I
accept them: how will they work with the method we used for the top ten?"

**What happened:** to answer, the AI ran the bootstrap on top of its own proposal, and the result changed
its recommendation. The adjusted score uses only 23% of the reviews, so its top ten is noisy: 7.4 of
the ten survive a reshuffle on average, against 8.7 for the plain average.

**Result:** rank by the plain average, and use the adjusted score as a check. Eight of the ten pass it.

## Iteration 6: "Is it really a tie? Recheck everything."

The first area results showed four parts of town within 0.01 stars of each other.

**My prompt:** "Did it really come out that several parts are best? Recheck everything. Maybe there is a
better way to compute the scores. I would like to name one best part, even if it is a stretch."

**What happened:** the AI recomputed everything from the raw reviews (identical numbers), then tried 24
ways of scoring an area. The winner changed with the method, which is what a real tie looks like. It
told me that choosing a formula because it produces a winner is exactly what the assignment warns against.

**What it offered instead:** the question asks where to find *the best* restaurants, so the right measure
is the share of an area's restaurants in the city's top quarter. On that measure one district leads, with
10 of 27, and comes first in half of the reshuffles.

**My follow-up:** "Explain again: what is the 10% threshold about?" With a stricter cut-off another
district leads, on a count of 3 restaurants out of 16 against 3 out of 27. I chose 25% once I understood why.

## Iteration 7: "Was the benchmark in the assignment?"

The AI measured three ways of reading the 5 GB file without asking me.

**My prompt:** "What is this whole benchmark for? Was all of this in the assignment or what?"

**Answer:** no. The assignment asks for a section on handling large data; the measurement was the AI's
addition, and it said it should have asked first. I kept it as one table: reading the whole file takes
18 GB of memory, reading in chunks takes 2 GB.

## Iteration 8: the site

**My prompts, in order:** "I don't like any of these" (three homepage sketches). "Let's brainstorm: what
could we make that is actually good?" "When someone scrolls, something should always be happening."
"Better fonts, and make the text sound like a person wrote it." "I want to rework the art direction. Look at how
the last project was made. Don't copy its style, just look at how professional and minimal it was."

**What changed:** the three sketches were one layout in three color schemes, and the AI agreed that was
why they felt generic. The concept I chose makes the finding visible without a number: every restaurant
is a light, brightness is the number of reviews, color is the rating, flicker is uncertainty.

The first build had glowing halos, film grain, gradients and a blurred glass card. After my last prompt the AI
compared it with Project 1 and stripped all of that: one flat background, hairlines, flat dots sized by the
number of reviews, and one accent color that only ever marks the best quarter.

## What the AI got wrong, and how it was caught

- **Block group names were not unique.** "Block Group 2" exists in every census tract, so 440 areas
  collapsed into 6. Caught by the AI when a table came out wrong; fixed and guarded with a check.
- **It recommended dropping Seafood** because it was simpler, not because it was better. Caught by me.
- **It read "keep it at the level of the class" as "use the simplest method".** Caught by me.
- **It claimed a result held "in 100% of reshuffles"** on a measure where that was not true. Caught by
  the AI when it computed the number, and corrected in the same message.
- **It added a benchmark without asking.** Caught by me.
- **The site and the report rounded two numbers differently** (4.46 against 4.47, 95% against 94%).
  Caught by the AI when it compared every figure on the site with the report.
- **The template code** it started from had three bugs of its own: review dates parsed with the wrong
  function, a filter on a column that did not exist yet, and a table that was never created.

## What I would tell someone doing this

Ask "is this required or is it your idea?" early. Ask for the explanation again until you could give
it yourself. And when the AI agrees with you quickly, ask it to test the idea on the data first.
