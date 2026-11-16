# 08_top10.R
# The top 10 and how far it can be trusted (decision #13).
#
#   Interval   ordinary average +/- 1.96 standard errors: the fewer reviews a restaurant
#              has, the wider the interval. Overlapping intervals mean the two places
#              cannot be told apart with confidence.
#   Bootstrap  "what if the reviews had been a little different?" For every restaurant,
#              draw its own reviews again with replacement (same number of reviews),
#              recompute the average, rank all restaurants again. Repeat 2,000 times and
#              count how often each restaurant lands in the top 10.
#
# The bootstrap is run twice: on the ordinary average (the ranking) and on the
# reviewer-adjusted score (the check). Reviewer baselines are treated as known.
#
# Input : results/restaurant_scores.csv, data/new_orleans/theme_reviews.rds,
#         data/new_orleans/reviewer_baselines.rds, data/boundaries/*.rds
# Output: results/top10.csv, results/ranking_stability.csv, results/stability_summary.csv
#         figures/top10_intervals.png, figures/ordinary_vs_adjusted.png, figures/top10_map.png

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(ggrepel)
  library(sf)
})

set.seed(9426)
n_resamples           <- 2000
min_reviewer_activity <- 5

restaurant_scores  <- read.csv("results/restaurant_scores.csv")
theme_reviews      <- readRDS("data/new_orleans/theme_reviews.rds")
reviewer_baselines <- readRDS("data/new_orleans/reviewer_baselines.rds")

ranked <- restaurant_scores |> filter(ranked) |> arrange(rank_ordinary)

# every rating of a ranked restaurant, and the same rating compared with the reviewer's baseline
ordinary_values <- theme_reviews |>
  semi_join(ranked, by = "business_id") |>
  transmute(business_id, value = stars)

adjusted_values <- theme_reviews |>
  semi_join(ranked, by = "business_id") |>
  inner_join(filter(reviewer_baselines, reviews_in_theme >= min_reviewer_activity), by = "user_id") |>
  transmute(business_id, value = stars - reviewer_mean)

# ---- 1. Intervals -------------------------------------------------------------------------

interval_table <- function(values, prefix) {
  values |>
    group_by(business_id) |>
    summarise(mean = mean(value), se = sd(value) / sqrt(n()), .groups = "drop") |>
    transmute(business_id,
              "{prefix}_low"  := mean - 1.96 * se,
              "{prefix}_high" := mean + 1.96 * se)
}

# ---- 2. Bootstrap -------------------------------------------------------------------------

# one restaurant: redraw its reviews n_resamples times and return the n_resamples averages
bootstrap_means <- function(values) {
  n <- length(values)
  redrawn <- matrix(sample(values, n * n_resamples, replace = TRUE), nrow = n)  # one column = one redraw
  colMeans(redrawn)
}

# all restaurants: a table of ranks, one row per resample, one column per restaurant
bootstrap_ranks <- function(values) {
  by_restaurant <- split(values$value, values$business_id)[ranked$business_id]
  means <- sapply(by_restaurant, bootstrap_means)
  t(apply(-means, 1, rank, ties.method = "first"))
}

summarise_ranks <- function(ranks, observed_rank, prefix) {
  observed_top10 <- which(observed_rank <= 10)
  list(
    per_restaurant = tibble(
      business_id = colnames(ranks),
      "{prefix}_chance_top10" := colMeans(ranks <= 10),
      "{prefix}_rank_low"     := apply(ranks, 2, quantile, 0.05),
      "{prefix}_rank_high"    := apply(ranks, 2, quantile, 0.95)
    ),
    summary = tibble(
      ranking                        = prefix,
      resamples                      = nrow(ranks),
      share_with_identical_top10     = mean(apply(ranks[, observed_top10] <= 10, 1, all)),
      average_top10_members_kept     = mean(rowSums(ranks[, observed_top10] <= 10)),
      restaurants_with_5pct_chance   = sum(colMeans(ranks <= 10) >= 0.05),
      restaurants_with_90pct_chance  = sum(colMeans(ranks <= 10) >= 0.90)
    )
  )
}

ordinary_boot <- summarise_ranks(bootstrap_ranks(ordinary_values), ranked$rank_ordinary, "ordinary")
adjusted_boot <- summarise_ranks(bootstrap_ranks(adjusted_values), ranked$rank_adjusted, "adjusted")

stability_summary <- bind_rows(ordinary_boot$summary, adjusted_boot$summary)
write.csv(stability_summary, "results/stability_summary.csv", row.names = FALSE)

# ---- 3. One table for all ranked restaurants, and the top 10 -------------------------------

ranking_stability <- ranked |>
  left_join(interval_table(ordinary_values, "ordinary"), by = "business_id") |>
  left_join(interval_table(adjusted_values, "adjusted"), by = "business_id") |>
  left_join(ordinary_boot$per_restaurant, by = "business_id") |>
  left_join(adjusted_boot$per_restaurant, by = "business_id") |>
  mutate(also_top10_after_adjustment = rank_adjusted <= 10)

write.csv(ranking_stability, "results/ranking_stability.csv", row.names = FALSE)

top10 <- ranking_stability |>
  filter(rank_ordinary <= 10) |>
  select(rank = rank_ordinary, business_name, part_of_town, neighborhood,
         reviews_all, ordinary_average, ordinary_low, ordinary_high,
         ordinary_chance_top10, ordinary_rank_low, ordinary_rank_high,
         reviews_active, adjusted_score, rank_adjusted, also_top10_after_adjustment,
         adjusted_chance_top10, latitude, longitude)

write.csv(top10, "results/top10.csv", row.names = FALSE)

# ---- 4. Figures ----------------------------------------------------------------------------

accent <- "#c0392b"
muted  <- "#8a8577"

# Figure: the 20 highest ordinary averages with their intervals
race <- ranking_stability |>
  filter(rank_ordinary <= 20) |>
  mutate(label = factor(business_name, levels = rev(business_name)),
         group = if_else(rank_ordinary <= 10, "In the top 10", "Just outside"),
         chance = sprintf("%.0f%%", 100 * ordinary_chance_top10))

figure_intervals <- ggplot(race, aes(y = label, colour = group)) +
  geom_linerange(aes(xmin = ordinary_low, xmax = ordinary_high), linewidth = 1.4, alpha = 0.55) +
  geom_point(aes(x = ordinary_average), size = 2.8) +
  geom_text(aes(x = max(ordinary_high) + 0.05, label = chance), hjust = 0, size = 3.4, colour = "grey25") +
  annotate("text", x = max(race$ordinary_high) + 0.05, y = 20.9, label = "Chance of\nbeing top 10",
           hjust = 0, vjust = 0, size = 3, colour = "grey40", lineheight = 0.9) +
  scale_colour_manual(values = c("In the top 10" = accent, "Just outside" = muted), name = NULL) +
  scale_x_continuous(expand = expansion(mult = c(0.02, 0.16))) +
  coord_cartesian(clip = "off") +
  labs(title = "The top of the ranking is a close race",
       subtitle = "Average rating of each restaurant (dot) and the range it could plausibly have (bar).\nFewer reviews give a wider bar. Bars that overlap cannot be ranked with confidence.",
       x = "Average star rating, all reviewers", y = NULL) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold"), plot.title.position = "plot",
        legend.position = "bottom", panel.grid.major.y = element_blank(),
        panel.grid.minor = element_blank(), plot.margin = margin(18, 30, 8, 8))

ggsave("figures/top10_intervals.png", figure_intervals, width = 9, height = 7, dpi = 150, bg = "white")

# Figure: ordinary average against the reviewer-adjusted score.
# Only the restaurants on which the two rankings disagree are named.
both_ways <- "Top 10 both ways"
only_ordinary <- "Top 10 by ordinary average only"
only_adjusted <- "Top 10 after adjustment only"

highlighted <- ranking_stability |>
  filter(rank_ordinary <= 10 | rank_adjusted <= 10) |>
  mutate(group = case_when(rank_ordinary <= 10 & rank_adjusted <= 10 ~ both_ways,
                           rank_ordinary <= 10                       ~ only_ordinary,
                           TRUE                                      ~ only_adjusted),
         group = factor(group, levels = c(both_ways, only_ordinary, only_adjusted)))

figure_scatter <- ggplot(ranking_stability, aes(x = ordinary_average, y = adjusted_score)) +
  geom_hline(yintercept = 0, colour = "grey70") +
  geom_point(aes(size = reviews_all), colour = muted, alpha = 0.4) +
  geom_point(data = highlighted, aes(size = reviews_all, colour = group), alpha = 0.95) +
  geom_label_repel(data = filter(highlighted, group != both_ways),
                   aes(label = business_name, colour = group), size = 3.3, fill = "white",
                   label.size = 0.15, min.segment.length = 0, box.padding = 0.5,
                   # the labels go to the empty upper-left corner, stacked vertically
                   xlim = c(NA, 3.75), ylim = c(0.25, NA), direction = "y", hjust = 1,
                   show.legend = FALSE, seed = 9426) +
  scale_colour_manual(values = setNames(c(accent, "#d98a1f", "#2c5f7c"),
                                        c(both_ways, only_ordinary, only_adjusted)), name = NULL) +
  scale_size_area(max_size = 9, name = "Reviews", breaks = c(100, 1000, 4000)) +
  guides(colour = guide_legend(order = 1, override.aes = list(size = 4)), size = guide_legend(order = 2)) +
  labs(title = "Adjusting for reviewer habits mostly confirms the ordinary ranking",
       subtitle = "Each dot is a restaurant. Higher means active reviewers rated it above what they usually give.\nEight restaurants are in the top 10 both ways; the four named ones are in only one of the two lists.",
       x = "Average star rating, all reviewers",
       y = "Reviewer-adjusted score\n(stars above the reviewers' own usual rating)") +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold"), plot.title.position = "plot",
        legend.position = "bottom", legend.box = "vertical", panel.grid.minor = element_blank())

ggsave("figures/ordinary_vs_adjusted.png", figure_scatter, width = 9, height = 7.5, dpi = 150, bg = "white")

# Figure: the final map. Parts of town as the first level, neighborhoods as thin lines inside.
parts_of_town <- readRDS("data/boundaries/planning_districts.rds")
neighborhoods <- readRDS("data/boundaries/neighborhoods.rds")

top10_points <- st_as_sf(top10, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) |>
  mutate(label = paste0(rank, ". ", business_name))
other_points <- ranking_stability |>
  filter(rank_ordinary > 10) |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326)

box  <- st_bbox(top10_points)
xlim <- c(box["xmin"] - 0.035, box["xmax"] + 0.02)
ylim <- c(box["ymin"] - 0.02,  box["ymax"] + 0.02)

view <- st_as_sfc(st_bbox(c(xmin = xlim[[1]], xmax = xlim[[2]], ymin = ylim[[1]], ymax = ylim[[2]]), crs = 4326))
sf_use_s2(FALSE)   # simple planar geometry is enough for labels at city scale
part_labels <- suppressWarnings(suppressMessages(
  parts_of_town |> st_intersection(view) |> st_point_on_surface()
))
part_labels <- cbind(st_drop_geometry(part_labels), st_coordinates(part_labels)) |>
  # a name too close to the edge of the picture would be cut off
  filter(X > xlim[1] + 0.02, X < xlim[2] - 0.02, Y > ylim[1] + 0.012, Y < ylim[2] - 0.012)

# restaurant labels must avoid the part-of-town names: the names enter the label layout
# as invisible obstacles (rows with an empty label)
label_layout <- bind_rows(
  transmute(st_drop_geometry(top10_points), X = longitude, Y = latitude, label),
  transmute(part_labels, X, Y, label = "")
)

figure_map <- ggplot() +
  geom_sf(data = parts_of_town, fill = "#f4f1ea", colour = NA) +
  geom_sf(data = neighborhoods, fill = NA, colour = "#d8d2c2", linewidth = 0.2) +
  geom_sf(data = parts_of_town, fill = NA, colour = "#6f6a5d", linewidth = 0.55) +
  geom_text(data = part_labels, aes(X, Y, label = toupper(part_of_town)),
            size = 2.5, colour = "#9a9484", fontface = "bold", lineheight = 0.9) +
  geom_sf(data = other_points, colour = muted, size = 0.6, alpha = 0.5) +
  geom_sf(data = top10_points, colour = "white", fill = accent, shape = 21, size = 4.5, stroke = 0.8) +
  geom_label_repel(data = label_layout, aes(X, Y, label = label),
                   size = 3.1, colour = "grey10", fill = "white", label.size = 0.15,
                   box.padding = 0.7, point.padding = 1.6, min.segment.length = 0, force = 3,
                   segment.colour = "grey40", max.overlaps = Inf, max.iter = 50000, seed = 9426) +
  coord_sf(xlim = xlim, ylim = ylim, expand = FALSE) +
  labs(title = "Where the ten best local-food restaurants are",
       subtitle = sprintf("Red: the top 10 by average rating. Grey: the other %d ranked restaurants.\nThick lines: parts of town. Thin lines: neighborhoods.",
                          nrow(other_points)),
       caption = "Yelp Open Dataset, reviews through January 2022. Boundaries: City of New Orleans.") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(face = "bold", size = 15), plot.subtitle = element_text(colour = "grey30"),
        plot.caption = element_text(colour = "grey45", size = 8), plot.margin = margin(10, 10, 10, 10))

ggsave("figures/top10_map.png", figure_map, width = 11, height = 7.5, dpi = 150, bg = "white")

# ---- Report --------------------------------------------------------------------------------

show <- function(title, x) {
  cat("\n", title, "\n", sep = "")
  print(as.data.frame(mutate(x, across(where(is.double), \(v) round(v, 2)))), row.names = FALSE)
}
show("Top 10", select(top10, -latitude, -longitude, -neighborhood))
show("Next 8", ranking_stability |> filter(rank_ordinary %in% 11:18) |>
       select(rank_ordinary, business_name, reviews_all, ordinary_average, ordinary_chance_top10, adjusted_score, rank_adjusted))
show("How stable is the top 10", stability_summary)
