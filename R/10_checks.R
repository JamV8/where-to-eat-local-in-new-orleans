# 10_checks.R
# Self-check (decision #14): can the results be trusted?
# Every check asks one question, says why it matters, and ends in pass, FAIL or skipped.
# Checks that need the raw Yelp files are skipped when those files are not present, so the
# script also runs for someone who only cloned the repository.
#
# Input : everything the earlier scripts produced
# Output: results/checks.csv   (the script stops with an error if any check fails)

suppressPackageStartupMessages({
  library(dplyr)
  library(sf)
})

business   <- readRDS("data/new_orleans/business_new_orleans.rds")
theme      <- readRDS("data/new_orleans/theme_restaurants.rds")
reviews    <- readRDS("data/new_orleans/theme_reviews.rds")
baselines  <- readRDS("data/new_orleans/reviewer_baselines.rds")
scores     <- read.csv("results/restaurant_scores.csv")
stability  <- read.csv("results/ranking_stability.csv")
areas      <- read.csv("results/area_scores.csv")
import_log <- read.csv("results/import_log.csv")

checks <- list()
check <- function(group, question, why, passed, detail) {
  result <- if (is.na(passed)) "skipped" else if (passed) "pass" else "FAIL"
  checks[[length(checks) + 1]] <<- data.frame(group, question, why, result, detail)
}

# ---- Import -----------------------------------------------------------------------------------

raw_reviews <- "data/raw/yelp_academic_dataset_review.json"
rows_read   <- import_log$rows_read[grepl("review", import_log$step)]
if (file.exists(raw_reviews)) {
  lines_in_file <- as.numeric(strsplit(trimws(system2("wc", c("-l", shQuote(raw_reviews)), stdout = TRUE)), " +")[[1]][1])
  check("Import", "Was every line of the 5 GB review file read?",
        "Reading in chunks must not drop the end of a chunk or the end of the file.",
        lines_in_file == rows_read,
        sprintf("%s lines in the file, %s rows read", format(lines_in_file, big.mark = ","), format(rows_read, big.mark = ",")))
} else {
  check("Import", "Was every line of the 5 GB review file read?",
        "Reading in chunks must not drop the end of a chunk or the end of the file.",
        NA, "raw file not present on this computer")
}

check("Import", "Does any review appear twice?",
      "A duplicated review would count one opinion twice.",
      !anyDuplicated(reviews$review_id),
      sprintf("%s reviews, %s distinct ids", format(nrow(reviews), big.mark = ","), format(n_distinct(reviews$review_id), big.mark = ",")))

check("Import", "Is every rating a whole number from 1 to 5?",
      "Anything else would mean the file was parsed wrongly.",
      all(reviews$stars %in% 1:5),
      paste("values found:", paste(sort(unique(reviews$stars)), collapse = ", ")))

check("Import", "Do the review dates fall inside the dataset's time span?",
      "The template code parsed dates with ymd(), which fails on timestamps; this confirms the fix.",
      !anyNA(reviews$date) && min(reviews$date) >= as.Date("2004-10-01") && max(reviews$date) <= as.Date("2022-01-31"),
      sprintf("%s to %s, no missing dates", min(reviews$date), max(reviews$date)))

# ---- Joins --------------------------------------------------------------------------------------

check("Joins", "Does every review belong to a restaurant in the theme?",
      "A wrong join key would attach reviews to the wrong restaurants or lose them.",
      nrow(anti_join(reviews, theme, by = "business_id")) == 0 && all(theme$business_id %in% reviews$business_id),
      sprintf("%d reviews without a restaurant, %d restaurants without reviews",
              nrow(anti_join(reviews, theme, by = "business_id")), sum(!theme$business_id %in% reviews$business_id)))

ours <- reviews |> group_by(business_id) |> summarise(n = n(), average = mean(stars)) |> inner_join(theme, by = "business_id")

check("Joins", "Do our review counts agree with the counts in Yelp's business file?",
      "An independent number from a different file: if the join lost reviews, these would disagree.",
      cor(ours$n, ours$review_count) > 0.999 && all(ours$n >= ours$review_count),
      sprintf("correlation %.5f; our count is never lower, and is higher by a median of %.0f reviews",
              cor(ours$n, ours$review_count), median(ours$n - ours$review_count)))

check("Joins", "Do our averages agree with the star rating Yelp shows for each restaurant?",
      "Yelp rounds its rating to half stars, so the two should differ by 0.25 at most, apart from the few extra reviews above.",
      mean(abs(ours$average - ours$stars) <= 0.25) > 0.95 && max(abs(ours$average - ours$stars)) < 0.5,
      sprintf("%.1f%% of restaurants within 0.25 stars, largest difference %.2f",
              100 * mean(abs(ours$average - ours$stars) <= 0.25), max(abs(ours$average - ours$stars))))

# ---- Geography ----------------------------------------------------------------------------------

boundary <- readRDS("data/boundaries/new_orleans_boundary.rds")
points   <- st_as_sf(business, coords = c("longitude", "latitude"), crs = 4326)
inside   <- lengths(st_within(points, boundary)) == 1

check("Geography", "Is every restaurant inside the official city boundary?",
      "This is the project's definition of a New Orleans restaurant.",
      all(inside), sprintf("%d of %d restaurants inside", sum(inside), nrow(business)))

check("Geography", "Does every theme restaurant have a part of town and a neighborhood?",
      "A restaurant without an area would silently drop out of the area comparison.",
      !anyNA(theme$part_of_town) && !anyNA(theme$neighborhood),
      sprintf("%d without a part of town, %d without a neighborhood", sum(is.na(theme$part_of_town)), sum(is.na(theme$neighborhood))))

landmarks <- c("Commander's Palace"        = "Garden District",
               "Galatoire's Restaurant"    = "French Quarter",
               "Antoine's Restaurant"      = "French Quarter",
               "Willie Mae's Scotch House" = "Treme - Lafitte",
               "Dooky Chase's Restaurant"  = "Treme - Lafitte",
               "Mother's Restaurant"       = "Central Business District",
               "Parkway Bakery & Tavern"   = "Bayou St. John",
               "Jacques-Imo's Cafe"        = "Leonidas")
found <- theme$neighborhood[match(names(landmarks), theme$business_name)]

check("Geography", "Do well-known restaurants land in the neighborhoods they are known to be in?",
      "A spatial join can be wrong in ways that counts cannot show, for example swapped latitude and longitude.",
      all(!is.na(found)) && all(found == landmarks),
      sprintf("%d of %d landmarks in the expected neighborhood", sum(found == landmarks, na.rm = TRUE), length(landmarks)))

# ---- Theme --------------------------------------------------------------------------------------

excluded <- read.csv("results/theme_excluded.csv")
check("Theme", "Does the inclusion rule hold for every restaurant?",
      "Each theme restaurant must carry one of the four labels, and none of the excluded ones may be inside.",
      all(theme$theme_labels >= 1) && !any(theme$business_id %in% excluded$business_id),
      sprintf("%d restaurants in the theme, %d left out by the seafood exception, overlap %d",
              nrow(theme), nrow(excluded), sum(theme$business_id %in% excluded$business_id)))

# ---- Scores -------------------------------------------------------------------------------------

second_way <- tapply(reviews$stars, reviews$business_id, mean)
check("Scores", "Do restaurant averages computed a second way give the same numbers?",
      "The stored averages come from dplyr; this recomputes them with base R.",
      max(abs(second_way[scores$business_id] - scores$ordinary_average)) < 1e-9,
      sprintf("largest difference %.1e", max(abs(second_way[scores$business_id] - scores$ordinary_average))))

active   <- filter(baselines, reviews_in_theme >= 5)
adjusted <- reviews |> inner_join(active, by = "user_id") |> mutate(normalized = stars - reviewer_mean)
per_reviewer <- adjusted |> group_by(user_id) |> summarise(mean_normalized = mean(normalized))

check("Scores", "Do each reviewer's adjusted ratings average to zero?",
      "By definition a reviewer rates exactly at their own usual level on average; anything else is a bug.",
      max(abs(per_reviewer$mean_normalized)) < 1e-9,
      sprintf("%s active reviewers, largest average %.1e", format(nrow(active), big.mark = ","), max(abs(per_reviewer$mean_normalized))))

# stricter baseline: the reviewer's usual rating at OTHER restaurants (this review left out)
leave_one_out <- adjusted |>
  mutate(other_mean = (reviewer_mean * reviews_in_theme - stars) / (reviews_in_theme - 1)) |>
  group_by(business_id) |>
  summarise(strict = mean(stars - other_mean), simple = mean(normalized)) |>
  semi_join(filter(scores, ranked), by = "business_id")
top10_simple <- head(arrange(leave_one_out, desc(simple)), 10)$business_id
top10_strict <- head(arrange(leave_one_out, desc(strict)), 10)$business_id

check("Scores", "Does a stricter reviewer baseline change the adjusted ranking?",
      "The simple baseline includes the review being judged. Leaving it out is cleaner in theory; this shows it makes no practical difference.",
      cor(leave_one_out$simple, leave_one_out$strict) > 0.99,
      sprintf("correlation %.4f, %d of the adjusted top 10 in common", cor(leave_one_out$simple, leave_one_out$strict),
              length(intersect(top10_simple, top10_strict))))

ranked <- filter(scores, ranked)
check("Scores", "Are the ranks complete, from 1 to the number of ranked restaurants?",
      "Gaps or ties in the ranks would shift the top 10.",
      setequal(ranked$rank_ordinary, seq_len(nrow(ranked))) && setequal(ranked$rank_adjusted, seq_len(nrow(ranked))),
      sprintf("%d ranked restaurants, ranks 1 to %d", nrow(ranked), max(ranked$rank_ordinary)))

# ---- Stability ------------------------------------------------------------------------------------

set.seed(1)   # a different seed from the one used in 08_top10.R
values <- reviews |> semi_join(ranked, by = "business_id")
by_restaurant <- split(values$stars, values$business_id)[stability$business_id]
redraws <- sapply(by_restaurant, function(x) colMeans(matrix(sample(x, length(x) * 2000, replace = TRUE), nrow = length(x))))
chance_again <- colMeans(t(apply(-redraws, 1, rank, ties.method = "first")) <= 10)

check("Stability", "Does the bootstrap give the same chances with a different random seed?",
      "The chance of being in the top 10 should not depend on the random numbers used.",
      max(abs(chance_again - stability$ordinary_chance_top10)) < 0.04,
      sprintf("largest change in any restaurant's chance: %.3f", max(abs(chance_again - stability$ordinary_chance_top10))))

sensitivity <- read.csv("results/threshold_sensitivity.csv")
check("Stability", "Does the top 10 survive a different definition of an active reviewer?",
      "The assignment asks how the threshold changes the results.",
      all(sensitivity$main_top10_still_in_ordinary_top10 >= 9),
      paste(sprintf("threshold %d: %d of 10 remain", sensitivity$threshold, sensitivity$main_top10_still_in_ordinary_top10), collapse = "; "))

# ---- Areas ------------------------------------------------------------------------------------------

check("Areas", "Do the parts of town add up to all ranked restaurants?",
      "Every ranked restaurant must be counted in exactly one part of town.",
      sum(areas$restaurants) == nrow(ranked) && sum(areas$great_restaurants) == sum(ranked$ordinary_average >= quantile(ranked$ordinary_average, 0.75)),
      sprintf("%d restaurants in %d parts of town, %d of them great", sum(areas$restaurants), nrow(areas), sum(areas$great_restaurants)))

cutoffs <- read.csv("results/area_cutoff_sensitivity.csv")
check("Areas", "Does the leading part of town stay first when 'great' is defined differently?",
      "The answer should not hinge on the 25% cut-off.",
      all(cutoffs$leader_place[cutoffs$great_means_best %in% c("20%", "25%", "33%")] == 1),
      paste(sprintf("best %s: place %d", cutoffs$great_means_best, cutoffs$leader_place), collapse = "; "))

# ---- Result ---------------------------------------------------------------------------------------

checks <- bind_rows(checks)
write.csv(checks, "results/checks.csv", row.names = FALSE)

print(checks[, c("group", "question", "result", "detail")], row.names = FALSE, right = FALSE)
cat(sprintf("\n%d checks: %d pass, %d skipped, %d FAIL\n", nrow(checks), sum(checks$result == "pass"),
            sum(checks$result == "skipped"), sum(checks$result == "FAIL")))
if (any(checks$result == "FAIL")) stop("At least one self-check failed.")
