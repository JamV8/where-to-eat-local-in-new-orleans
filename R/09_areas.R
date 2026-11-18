# 09_areas.R
# Which part of town is best for finding the best local food? (decision #18)
#
# A "great" restaurant is one in the best quarter of the 231 ranked restaurants.
# A part of town is scored by the share of its ranked restaurants that are great:
# "if I pick a restaurant here, what is the chance it is one of the city's best?"
# Only parts of town with 5 or more ranked restaurants are compared (decision #16).
#
# Checks included, because the leading areas are close:
#   - bootstrap: redraw the restaurants of each part of town and see who comes first;
#   - other cut-offs for "great" (best 10%, 20%, 33%);
#   - 24 other ways of scoring (3 sets of restaurants x 8 measures);
#   - the same table for every geographic system, with the reviewer-adjusted score.
#
# Input : results/restaurant_scores.csv, data/new_orleans/theme_restaurants.rds,
#         data/boundaries/planning_districts.rds
# Output: results/area_scores.csv, results/area_cutoff_sensitivity.csv,
#         results/area_method_robustness.csv, results/neighborhood_scores.csv,
#         results/geography_area_scores.csv, results/center_vs_rest.csv,
#         results/beats_french_quarter.csv,
#         figures/areas_share_great.png, figures/areas_map.png

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(sf)
})

set.seed(9426)
n_resamples     <- 5000
great_share     <- 0.25   # "great" = best quarter of the ranked restaurants
min_restaurants <- 5      # a part of town needs this many ranked restaurants to be compared

scores <- read.csv("results/restaurant_scores.csv")
ranked <- filter(scores, ranked)

great_cut <- unname(quantile(ranked$ordinary_average, 1 - great_share))
ranked <- mutate(ranked, great = ordinary_average >= great_cut)

# ---- 1. Score every part of town -------------------------------------------------------

score_areas <- function(data, column) {
  data |>
    group_by(area = .data[[column]]) |>
    summarise(
      restaurants          = n(),
      great_restaurants    = sum(great),
      share_great          = mean(great),
      average_rating       = mean(ordinary_average),             # each restaurant counts once
      average_over_reviews = sum(ordinary_average * reviews_all) / sum(reviews_all),
      adjusted_score       = mean(adjusted_score),               # the reviewer-adjusted check
      top10_restaurants    = sum(rank_ordinary <= 10),
      reviews              = sum(reviews_all),
      .groups = "drop"
    ) |>
    mutate(compared = restaurants >= min_restaurants)
}

area_scores <- score_areas(ranked, "part_of_town") |> rename(part_of_town = area)
compared    <- filter(ranked, part_of_town %in% area_scores$part_of_town[area_scores$compared])

# ---- 2. Bootstrap: redraw the restaurants of each part of town --------------------------

# for one part of town: n_resamples redraws of its restaurants, one statistic per redraw
redraw <- function(rows, statistic) {
  replicate(n_resamples, statistic(rows[sample(nrow(rows), replace = TRUE), ]))
}
# chance that each part of town comes first, and comes in the first three
chances <- function(data, statistic) {
  draws <- sapply(split(data, data$part_of_town), redraw, statistic = statistic)
  ranks <- t(apply(-draws, 1, rank, ties.method = "random"))
  tibble(part_of_town = colnames(draws),
         chance_first = colMeans(ranks == 1),
         chance_top3  = colMeans(ranks <= 3),
         low          = apply(draws, 2, quantile, 0.025),
         high         = apply(draws, 2, quantile, 0.975))
}

share_chances <- chances(compared, function(x) mean(x$great)) |>
  rename(share_great_low = low, share_great_high = high)

area_scores <- area_scores |>
  left_join(share_chances, by = "part_of_town") |>
  arrange(desc(compared), desc(share_great))

write.csv(area_scores, "results/area_scores.csv", row.names = FALSE)

# the part of town that comes first on the main measure; the checks below follow it
leader <- area_scores$part_of_town[1]

# ---- 3. Does the cut-off for "great" matter? --------------------------------------------

area_cutoff_sensitivity <- bind_rows(lapply(c(0.10, 0.20, 0.25, 0.33), function(share) {
  cut <- unname(quantile(ranked$ordinary_average, 1 - share))
  by_area <- compared |>
    group_by(part_of_town) |>
    summarise(great = sum(ordinary_average >= cut), share_great = mean(ordinary_average >= cut), .groups = "drop") |>
    arrange(desc(share_great))
  tibble(
    great_means_best    = sprintf("%.0f%%", 100 * share),
    rating_cut          = cut,
    great_in_city       = sum(ranked$ordinary_average >= cut),
    first               = by_area$part_of_town[1],
    first_share         = by_area$share_great[1],
    second              = by_area$part_of_town[2],
    second_share        = by_area$share_great[2],
    leader_place        = match(leader, by_area$part_of_town),
    leader_great        = by_area$great[by_area$part_of_town == leader],
    french_quarter_place = match("French Quarter", by_area$part_of_town)
  )
}))

write.csv(area_cutoff_sensitivity, "results/area_cutoff_sensitivity.csv", row.names = FALSE)

# ---- 4. 24 other ways of scoring: does one part of town always win? ----------------------
# If one area were clearly best it would win almost every time. It does not, which is why
# the report names the leader as the most likely best, not as a proven winner.

open_restaurants <- filter(scores, is_open == 1, !is.na(reviews_all))
restaurant_sets <- list(
  "ranked: 30+ reviews from active reviewers" = ranked,
  "open, 10+ reviews"                         = filter(open_restaurants, reviews_all >= 10),
  "all open"                                  = open_restaurants
)

area_method_robustness <- bind_rows(lapply(names(restaurant_sets), function(set_name) {
  data <- restaurant_sets[[set_name]]
  data <- filter(data, part_of_town %in% names(which(table(data$part_of_town) >= min_restaurants)))
  cuts <- quantile(data$ordinary_average, c(0.90, 0.80, 0.75, 0.67))
  measures <- list(
    "average rating of restaurants" = function(x) mean(x$ordinary_average),
    "average over all reviews"      = function(x) sum(x$ordinary_average * x$reviews_all) / sum(x$reviews_all),
    "median restaurant rating"      = function(x) median(x$ordinary_average),
    "share in the city's best 10%"  = function(x) mean(x$ordinary_average >= cuts[1]),
    "share in the city's best 20%"  = function(x) mean(x$ordinary_average >= cuts[2]),
    "share in the city's best 25%"  = function(x) mean(x$ordinary_average >= cuts[3]),
    "share in the city's best 33%"  = function(x) mean(x$ordinary_average >= cuts[4]),
    "reviewer-adjusted score"       = function(x) mean(x$adjusted_score, na.rm = TRUE)
  )
  bind_rows(lapply(names(measures), function(measure_name) {
    statistic <- measures[[measure_name]]
    observed  <- sort(sapply(split(data, data$part_of_town), statistic), decreasing = TRUE)
    ch        <- chances(data, statistic)
    tibble(
      restaurants_used        = set_name,
      measure                 = measure_name,
      parts_compared          = length(observed),
      first                   = names(observed)[1],
      second                  = names(observed)[2],
      leader_place            = match(leader, names(observed)),
      leader_chance_first     = ch$chance_first[ch$part_of_town == leader],
      french_quarter_place    = match("French Quarter", names(observed)),
      french_quarter_chance_top3 = ch$chance_top3[ch$part_of_town == "French Quarter"]
    )
  }))
}))

write.csv(area_method_robustness, "results/area_method_robustness.csv", row.names = FALSE)

# ---- 4b. The tourist center against the rest of the city ---------------------------------
# Planning District 1 (French Quarter + CBD / Warehouse District) is where visitors stay.
# This comparison uses every ranked restaurant, so it does not depend on which single part
# of town comes first.

center_parts <- c("French Quarter", "CBD / Warehouse District")
ranked <- mutate(ranked, where = if_else(part_of_town %in% center_parts, "Tourist center", "Rest of the city"))
center <- filter(ranked, where == "Tourist center")
rest   <- filter(ranked, where == "Rest of the city")

rating_test <- t.test(rest$ordinary_average, center$ordinary_average)
share_test  <- prop.test(c(sum(rest$great), sum(center$great)), c(nrow(rest), nrow(center)))

center_vs_rest <- tibble(
  where             = c("Tourist center", "Rest of the city"),
  restaurants       = c(nrow(center), nrow(rest)),
  great_restaurants = c(sum(center$great), sum(rest$great)),
  share_great       = c(mean(center$great), mean(rest$great)),
  average_rating    = c(mean(center$ordinary_average), mean(rest$ordinary_average)),
  adjusted_score    = c(mean(center$adjusted_score), mean(rest$adjusted_score)),
  rating_difference = c(NA, unname(diff(rev(rating_test$estimate)))),
  rating_difference_low  = c(NA, rating_test$conf.int[1]),
  rating_difference_high = c(NA, rating_test$conf.int[2]),
  rating_p_value    = c(NA, rating_test$p.value),
  share_p_value     = c(NA, share_test$p.value)
)

write.csv(center_vs_rest, "results/center_vs_rest.csv", row.names = FALSE)

# how often each compared part of town beats the French Quarter when restaurants are redrawn
beats_french_quarter <- bind_rows(lapply(setdiff(unique(compared$part_of_town), "French Quarter"), function(part) {
  mine   <- filter(compared, part_of_town == part)
  theirs <- filter(compared, part_of_town == "French Quarter")
  tibble(part_of_town = part,
         beats_on_share_great    = mean(redraw(mine, \(x) mean(x$great)) > redraw(theirs, \(x) mean(x$great))),
         beats_on_average_rating = mean(redraw(mine, \(x) mean(x$ordinary_average)) > redraw(theirs, \(x) mean(x$ordinary_average))))
}))

write.csv(beats_french_quarter, "results/beats_french_quarter.csv", row.names = FALSE)

# ---- 5. Second level: neighborhoods inside the parts of town -----------------------------

neighborhood_scores <- ranked |>
  group_by(part_of_town, neighborhood) |>
  summarise(
    restaurants       = n(),
    great_restaurants = sum(great),
    share_great       = mean(great),
    average_rating    = mean(ordinary_average),
    adjusted_score    = mean(adjusted_score),
    top10_restaurants = sum(rank_ordinary <= 10),
    .groups = "drop"
  ) |>
  mutate(compared = restaurants >= min_restaurants) |>
  arrange(part_of_town, desc(restaurants))

write.csv(neighborhood_scores, "results/neighborhood_scores.csv", row.names = FALSE)

# ---- 6. The same scores under every geographic system -------------------------------------
# The assignment asks for the average rating and the reviewer-adjusted rating per area in
# each system that was tested.

area_labels <- readRDS("data/new_orleans/theme_restaurants.rds") |>
  select(business_id, zcta, tract_name, block_group_name, ward_name)

systems <- c("Parts of town" = "part_of_town", "Neighborhoods" = "neighborhood", "Wards" = "ward_name",
             "ZIP code areas" = "zcta", "Census tracts" = "tract_name", "Census block groups" = "block_group_name")

ranked_with_labels <- left_join(ranked, area_labels, by = "business_id")

geography_area_scores <- bind_rows(lapply(names(systems), function(system) {
  ranked_with_labels |>
    filter(!is.na(.data[[systems[[system]]]])) |>
    score_areas(systems[[system]]) |>
    mutate(system = system, area = as.character(area), .before = 1)
}))

write.csv(geography_area_scores, "results/geography_area_scores.csv", row.names = FALSE)

# ---- 7. Figures -------------------------------------------------------------------------------

accent <- "#c0392b"
muted  <- "#8a8577"

bars <- area_scores |>
  filter(compared) |>
  mutate(part_of_town = factor(part_of_town, levels = rev(part_of_town)),
         leader = share_great == max(share_great),
         label  = sprintf("%d of %d", great_restaurants, restaurants))

figure_share <- ggplot(bars, aes(y = part_of_town)) +
  geom_col(aes(x = share_great, fill = leader), width = 0.62) +
  geom_linerange(aes(xmin = share_great_low, xmax = share_great_high), colour = "grey20", linewidth = 0.5) +
  geom_text(aes(x = share_great_high + 0.015, label = label), hjust = 0, size = 3.5, colour = "grey20") +
  geom_vline(xintercept = great_share, linetype = "dashed", colour = "grey45") +
  annotate("text", x = great_share, y = 0.45, label = "whole city: 25%", hjust = -0.05, vjust = 0,
           size = 3.1, colour = "grey35") +
  scale_fill_manual(values = c("TRUE" = accent, "FALSE" = "#cfc9b9"), guide = "none") +
  scale_x_continuous(labels = scales::percent, expand = expansion(mult = c(0, 0.14))) +
  labs(title = sprintf("%s leads: %d of its %d local-food restaurants are among the city's best",
                       leader, bars$great_restaurants[1], bars$restaurants[1]),
       subtitle = sprintf("Share of each area's restaurants that are in the best quarter of the city (average rating of %.2f or more).\nThin line: the range the share could plausibly have. The ranges of the leading areas overlap, so their order is not certain.", great_cut),
       x = "Share of restaurants in the city's best quarter", y = NULL) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold"), plot.title.position = "plot",
        panel.grid.major.y = element_blank(), panel.grid.minor = element_blank())

ggsave("figures/areas_share_great.png", figure_share, width = 10, height = 5.2, dpi = 150, bg = "white")

# Map of the parts of town, shaded by the share of great restaurants
parts_of_town <- readRDS("data/boundaries/planning_districts.rds") |>
  left_join(area_scores, by = "part_of_town") |>
  mutate(shade = if_else(coalesce(compared, FALSE), share_great, NA_real_))

sf_use_s2(FALSE)
restaurant_points <- st_as_sf(ranked, coords = c("longitude", "latitude"), crs = 4326)
box  <- st_bbox(restaurant_points)
xlim <- c(box["xmin"] - 0.02, box["xmax"] + 0.02)
ylim <- c(box["ymin"] - 0.02, box["ymax"] + 0.02)
view <- st_as_sfc(st_bbox(c(xmin = xlim[[1]], xmax = xlim[[2]], ymin = ylim[[1]], ymax = ylim[[2]]), crs = 4326))

map_labels <- suppressWarnings(suppressMessages(
  parts_of_town |> filter(!is.na(shade)) |> st_intersection(view) |> st_point_on_surface()
))
map_labels <- cbind(st_drop_geometry(map_labels), st_coordinates(map_labels)) |>
  mutate(label = sprintf("%s\n%.0f%%", part_of_town, 100 * share_great))

figure_map <- ggplot() +
  geom_sf(data = parts_of_town, aes(fill = shade), colour = "white", linewidth = 0.6) +
  geom_sf(data = restaurant_points, aes(colour = great), size = 0.9, alpha = 0.85) +
  ggrepel::geom_label_repel(data = map_labels, aes(X, Y, label = label), size = 3, lineheight = 0.95,
                            fill = "white", label.size = 0.15, colour = "grey10", seed = 9426,
                            box.padding = 0.3, point.size = NA, max.overlaps = Inf) +
  scale_fill_gradient(low = "#f1e3dc", high = "#b5442f", na.value = "#e9e6de", labels = scales::percent,
                      name = "Share of restaurants in\nthe city's best quarter") +
  scale_colour_manual(values = c("TRUE" = "#3d0f08", "FALSE" = "#8a8577"),
                      labels = c("TRUE" = "Great (best quarter)", "FALSE" = "Other ranked restaurant"), name = NULL) +
  coord_sf(xlim = xlim, ylim = ylim, expand = FALSE) +
  labs(title = "The best local food is outside the tourist center",
       subtitle = "Parts of town shaded by the share of their local-food restaurants that are among the city's best.\nPale grey: fewer than 5 ranked restaurants, not compared.",
       caption = "Yelp Open Dataset, reviews through January 2022. Boundaries: City of New Orleans.") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(face = "bold", size = 15), plot.subtitle = element_text(colour = "grey30"),
        plot.caption = element_text(colour = "grey45", size = 8), legend.position = "right",
        plot.margin = margin(10, 10, 10, 10))

ggsave("figures/areas_map.png", figure_map, width = 11.5, height = 7.5, dpi = 150, bg = "white")

# ---- Report --------------------------------------------------------------------------------

show <- function(title, x) {
  cat("\n", title, "\n", sep = "")
  print(as.data.frame(mutate(x, across(where(is.double), \(v) round(v, 2)))), row.names = FALSE)
}
cat(sprintf("Great = average rating of %.3f or more: %d of %d ranked restaurants\n", great_cut, sum(ranked$great), nrow(ranked)))
show("Parts of town", area_scores)
show("Cut-off for 'great'", area_cutoff_sensitivity)
show("Who comes first under 24 ways of scoring", count(area_method_robustness, first, sort = TRUE))
show(sprintf("%s and the French Quarter in the 24 ways", leader),
     summarise(area_method_robustness,
               leader_first = sum(leader_place == 1), leader_top3 = sum(leader_place <= 3),
               french_quarter_best_place = min(french_quarter_place),
               french_quarter_max_chance_top3 = max(french_quarter_chance_top3)))
show("Tourist center against the rest of the city", center_vs_rest)
show("How often each part of town beats the French Quarter", beats_french_quarter)
show("Neighborhoods with 5+ ranked restaurants", filter(neighborhood_scores, compared))
