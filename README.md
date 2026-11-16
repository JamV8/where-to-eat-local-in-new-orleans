# Where to eat local in New Orleans

**Work in progress.** The analysis is done; the full report is being written.

## The question

Where in New Orleans can someone find the best local food (Cajun/Creole, Southern, soul food and
seafood), and which part of town is best for finding it?

This is Project 2 for Math 167R. It uses the Yelp Open Dataset: 6,990,280 reviews, of which
238,474 are reviews of the 608 local-food restaurants inside the New Orleans city boundary.

## What is in this repository

| Folder | Contents |
|---|---|
| `R/` | The analysis, one numbered script per step, run in order from `01_import.R` to `09_areas.R` |
| `results/` | Every table the scripts produce, as CSV |
| `figures/` | Every chart and map the scripts produce |
| `data/new_orleans/` | The filtered data the analysis runs on |
| `data/boundaries/` | Boundaries of the city, its parts of town, neighborhoods, wards, ZIP code areas and census areas |

The raw Yelp files (several GB) are not in the repository. To rebuild everything from scratch,
download the Yelp Open Dataset, put the two JSON files in `data/raw/`, and run the scripts in order.

## Data

Yelp Open Dataset, reviews from March 2005 through January 2022. Boundaries come from the
U.S. Census Bureau and the City of New Orleans open data portal.
