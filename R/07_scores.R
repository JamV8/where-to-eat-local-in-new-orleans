# 07_scores.R
# Two numbers for every restaurant in the theme (decisions #6, #7, #8, #17):
#
#   ordinary average   the mean of all its star ratings, from all reviewers;
#   adjusted score     how far above or below their own usual rating the active
#                      reviewers scored it. It is NOT a new Yelp rating: +0.5 means
#                      "half a star more than these reviewers usually give".
#
# Rules
#   1. An active reviewer has written 5 or more reviews of theme restaurants.
#   2. A reviewer's usual rating (baseline) is the mean of their theme reviews.
#   3. Restaurants are ranked by the ordinary average; the adjusted score is the check.
#   4. Only open restaurants with 30+ reviews from active reviewers are ranked.
#
# Reviews of closed restaurants still count toward a reviewer's baseline (decision #4).
#
# Input : data/new_orleans/theme_restaurants.rds, theme_reviews.rds
# Output: data/new_orleans/reviewer_baselines.rds
#         results/restaurant_scores.csv        one row per theme restaurant
#         results/reviewer_thresholds.csv      what each activity threshold keeps
#         results/threshold_sensitivity.csv    how the top 10 changes with the threshold
#         results/baseline_mean_vs_median.csv  does the choice of baseline matter

suppressPackageStartupMessages(library(dplyr))

min_reviewer_activity   <- 5    # rule 1
min_active_reviews      <- 30   # rule 4
thresholds_to_compare   <- c(3, 5, 10)

theme_restaurants <- readRDS("data/new_orleans/theme_restaurants.rds")
theme_reviews     <- readRDS("data/new_orleans/theme_reviews.rds")

# ---- 1. Reviewer baselines -------------------------------------------------------------

reviewer_baselines <- theme_reviews |>
  group_by(user_id) |>
  summarise(
    reviews_in_theme = n(),
    reviewer_mean    = mean(stars),
    reviewer_median  = median(stars),
    .groups = "drop"
  )

saveRDS(reviewer_baselines, "data/new_orleans/reviewer_baselines.rds")

# What each threshold keeps (the assignment asks for retained reviewers and their share of reviews)
reviewer_thresholds <- bind_rows(lapply(thresholds_to_compare, function(threshold) {
  kept <- filter(reviewer_baselines, reviews_in_theme >= threshold)
  tibble(
    threshold          = threshold,
    reviewers_kept     = nrow(kept),
    share_of_reviewers = nrow(kept) / nrow(reviewer_baselines),
    reviews_kept       = sum(kept$reviews_in_theme),
    share_of_reviews   = sum(kept$reviews_in_theme) / nrow(theme_reviews),
    baseline_5th_pct   = quantile(kept$reviewer_mean, 0.05),
    baseline_median    = median(kept$reviewer_mean),
    baseline_95th_pct  = quantile(kept$reviewer_mean, 0.95)
  )
}))

write.csv(reviewer_thresholds, "results/reviewer_thresholds.csv", row.names = FALSE)

# ---- 2. Scores for every restaurant -------------------------------------------------------

# ordinary result: all reviewers
all_reviewer_summary <- theme_reviews |>
  group_by(business_id) |>
  summarise(
    reviews_all      = n(),
    ordinary_average = mean(stars),
    ordinary_median  = median(stars),
    .groups = "drop"
  )

# adjusted result: active reviewers only, each rating compared with that reviewer's baseline
score_with_threshold <- function(threshold) {
  theme_reviews |>
    inner_join(filter(reviewer_baselines, reviews_in_theme >= threshold), by = "user_id") |>
    mutate(
      normalized_mean_score   = stars - reviewer_mean,
      normalized_median_score = stars - reviewer_median
    ) |>
    group_by(business_id) |>
    summarise(
      reviews_active                 = n(),
      average_active                 = mean(stars),
      adjusted_score                 = mean(normalized_mean_score),
      adjusted_score_median_baseline = mean(normalized_median_score),
      .groups = "drop"
    )
}

rank_restaurants <- function(threshold) {
  theme_restaurants |>
    select(business_id, business_name, is_open, part_of_town, neighborhood,
           latitude, longitude, entered_by) |>
    left_join(all_reviewer_summary, by = "business_id") |>
    left_join(score_with_threshold(threshold), by = "business_id") |>
    mutate(
      reviews_active = coalesce(reviews_active, 0L),
      ranked         = is_open == 1 & reviews_active >= min_active_reviews,
      # ranks exist only for ranked restaurants; rank 1 is the best
      rank_ordinary  = if_else(ranked, rank(-if_else(ranked, ordinary_average, -Inf), ties.method = "first"), NA_integer_),
      rank_adjusted  = if_else(ranked, rank(-if_else(ranked, adjusted_score, -Inf), ties.method = "first"), NA_integer_),
      rank_adjusted_median_baseline =
        if_else(ranked, rank(-if_else(ranked, adjusted_score_median_baseline, -Inf), ties.method = "first"), NA_integer_)
    ) |>
    arrange(rank_ordinary, desc(reviews_all))
}

restaurant_scores <- rank_restaurants(min_reviewer_activity)

write.csv(restaurant_scores, "results/restaurant_scores.csv", row.names = FALSE)

# ---- 3. Does the activity threshold change the answer? ------------------------------------

top10_names <- function(scores, rank_column) {
  scores |> filter(.data[[rank_column]] <= 10) |> pull(business_name)
}
main_top10          <- top10_names(restaurant_scores, "rank_ordinary")
main_top10_adjusted <- top10_names(restaurant_scores, "rank_adjusted")

threshold_sensitivity <- bind_rows(lapply(thresholds_to_compare, function(threshold) {
  scores <- rank_restaurants(threshold)
  tibble(
    threshold                         = threshold,
    restaurants_ranked                = sum(scores$ranked),
    main_top10_still_in_ordinary_top10 = length(intersect(main_top10, top10_names(scores, "rank_ordinary"))),
    adjusted_top10_shared_with_main    = length(intersect(main_top10_adjusted, top10_names(scores, "rank_adjusted"))),
    ordinary_top10_also_adjusted_top10 = length(intersect(top10_names(scores, "rank_ordinary"),
                                                           top10_names(scores, "rank_adjusted")))
  )
}))

write.csv(threshold_sensitivity, "results/threshold_sensitivity.csv", row.names = FALSE)

# ---- 4. Does mean or median baseline change the answer? -----------------------------------

ranked <- filter(restaurant_scores, ranked)

baseline_mean_vs_median <- tibble(
  restaurants_ranked          = nrow(ranked),
  correlation_of_scores       = cor(ranked$adjusted_score, ranked$adjusted_score_median_baseline),
  rank_correlation            = cor(ranked$rank_adjusted, ranked$rank_adjusted_median_baseline, method = "spearman"),
  adjusted_top10_in_common    = length(intersect(main_top10_adjusted,
                                                 top10_names(restaurant_scores, "rank_adjusted_median_baseline"))),
  share_of_active_reviewers_with_median_4_or_5 =
    mean(filter(reviewer_baselines, reviews_in_theme >= min_reviewer_activity)$reviewer_median %in% c(4, 5))
)

write.csv(baseline_mean_vs_median, "results/baseline_mean_vs_median.csv", row.names = FALSE)

# ---- Report -------------------------------------------------------------------------------

show <- function(title, x) {
  cat("\n", title, "\n", sep = "")
  print(as.data.frame(mutate(x, across(where(is.double), \(v) round(v, 3)))), row.names = FALSE)
}

show("Activity thresholds", reviewer_thresholds)
cat(sprintf("\nOpen restaurants: %d, of which ranked (30+ reviews from active reviewers): %d\n",
            sum(restaurant_scores$is_open == 1), sum(restaurant_scores$ranked)))
show("Top 15 by ordinary average",
     restaurant_scores |> filter(rank_ordinary <= 15) |>
       select(rank_ordinary, business_name, reviews_all, ordinary_average, reviews_active,
              adjusted_score, rank_adjusted, part_of_town))
show("Top 10 by adjusted score",
     restaurant_scores |> filter(rank_adjusted <= 10) |> arrange(rank_adjusted) |>
       select(rank_adjusted, business_name, reviews_active, adjusted_score, ordinary_average,
              rank_ordinary, part_of_town))
show("Sensitivity to the activity threshold", threshold_sensitivity)
show("Mean or median baseline", baseline_mean_vs_median)
