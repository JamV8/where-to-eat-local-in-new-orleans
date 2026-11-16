# 06_geography.R
# Compare six ways of dividing New Orleans into areas (decision #5): the five systems
# listed in the assignment, plus the city's planning districts ("parts of town").
# For each system: how many areas there are, how many theme restaurants each area
# holds, how many restaurants could not be assigned, and how many areas are too
# small to compare. The numbers are computed twice: for all theme restaurants and
# for those still open.
#
# Input : data/new_orleans/theme_restaurants.rds, theme_reviews.rds, data/boundaries/*.rds
# Output: results/geography_comparison.csv   one row per system and scope
#         results/geography_area_stats.csv   one row per system, scope and area
#         figures/geography_systems.png      the six systems on one map
#         figures/geography_area_sizes.png   how many areas are large enough

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(sf)
  library(patchwork)
})

theme_restaurants <- readRDS("data/new_orleans/theme_restaurants.rds")
theme_reviews     <- readRDS("data/new_orleans/theme_reviews.rds")

systems <- tribble(
  ~system,                ~column,             ~layer,
  "Parts of town",        "part_of_town",      "planning_districts",
  "Neighborhoods",        "neighborhood",      "neighborhoods",
  "Wards",                "ward_name",         "wards",
  "ZIP code areas",       "zcta",              "zctas",
  "Census tracts",        "tract_name",        "tracts",
  "Census block groups",  "block_group_name",  "block_groups"
)
read_layer <- function(layer) readRDS(file.path("data/boundaries", paste0(layer, ".rds")))

small_area <- 5   # an area with fewer restaurants than this is treated as too small to compare

# reviews per restaurant, to get an area's average over reviews (not over restaurants)
review_totals <- theme_reviews |>
  group_by(business_id) |>
  summarise(n_reviews = n(), sum_stars = sum(stars), .groups = "drop")

restaurants <- theme_restaurants |>
  left_join(review_totals, by = "business_id")

# ---- Per-area statistics ------------------------------------------------------------

area_stats_one <- function(system, column, scope) {
  x <- if (scope == "open") filter(restaurants, is_open == 1) else restaurants
  x |>
    filter(!is.na(.data[[column]])) |>
    group_by(area = .data[[column]]) |>
    summarise(
      restaurants        = n(),
      mean_yelp_stars    = mean(stars),                       # Yelp's rounded business rating
      reviews            = sum(n_reviews),
      mean_review_stars  = sum(sum_stars) / sum(n_reviews),   # average over all reviews in the area
      .groups = "drop"
    ) |>
    mutate(system = system, scope = scope, .before = 1)
}

grid <- crossing(systems, scope = c("all", "open"))
geography_area_stats <- bind_rows(Map(area_stats_one, grid$system, grid$column, grid$scope))

write.csv(geography_area_stats, "results/geography_area_stats.csv", row.names = FALSE)

# ---- Comparison table -----------------------------------------------------------------

n_in_scope <- c(all = nrow(restaurants), open = sum(restaurants$is_open == 1))
areas_in_city <- setNames(vapply(systems$layer, \(l) nrow(read_layer(l)), integer(1)), systems$system)

geography_comparison <- geography_area_stats |>
  group_by(system, scope) |>
  summarise(
    areas_with_restaurants  = n(),
    restaurants_assigned    = sum(restaurants),
    smallest_area_count     = min(restaurants),
    median_area_count       = median(restaurants),
    largest_area_count      = max(restaurants),
    areas_too_small         = sum(restaurants < small_area),
    areas_large_enough      = sum(restaurants >= small_area),
    restaurants_in_large_enough_areas = sum(restaurants[restaurants >= small_area]),
    .groups = "drop"
  ) |>
  mutate(
    areas_in_city           = areas_in_city[system],
    unmatched_restaurants   = n_in_scope[scope] - restaurants_assigned,
    share_in_largest_area   = largest_area_count / restaurants_assigned,
    share_of_restaurants_in_large_enough_areas = restaurants_in_large_enough_areas / restaurants_assigned
  ) |>
  select(system, scope, areas_in_city, areas_with_restaurants, restaurants_assigned,
         unmatched_restaurants, smallest_area_count, median_area_count, largest_area_count,
         share_in_largest_area, areas_too_small, areas_large_enough,
         share_of_restaurants_in_large_enough_areas) |>
  arrange(scope, match(system, systems$system))

write.csv(geography_comparison, "results/geography_comparison.csv", row.names = FALSE)

# ---- Figure 1: the six systems on one map ---------------------------------------------

dir.create("figures", showWarnings = FALSE)

points <- restaurants |>
  filter(is_open == 1) |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326)

# zoom to where the restaurants are; the empty wetlands in the east are cut off
box <- st_bbox(points)
pad <- 0.01
xlim <- c(box["xmin"] - pad, box["xmax"] + pad)
ylim <- c(box["ymin"] - pad, box["ymax"] + pad)

map_one <- function(system, layer) {
  row <- filter(geography_comparison, system == !!system, scope == "open")
  ggplot() +
    geom_sf(data = read_layer(layer), fill = "#f4f1ea", colour = "#8a8577", linewidth = 0.25) +
    geom_sf(data = points, colour = "#c0392b", size = 0.35, alpha = 0.7) +
    coord_sf(xlim = xlim, ylim = ylim, expand = FALSE) +
    labs(title = system,
         subtitle = sprintf("%d areas with restaurants, %d of them with %d or more",
                            row$areas_with_restaurants, row$areas_large_enough, small_area)) +
    theme_void(base_size = 11) +
    theme(plot.title = element_text(face = "bold"),
          plot.subtitle = element_text(colour = "grey30", size = 9),
          panel.border = element_rect(colour = "grey80", fill = NA))
}

maps <- Map(map_one, systems$system, systems$layer)
figure_systems <- wrap_plots(maps, ncol = 3) +
  plot_annotation(
    title = "Six ways to divide New Orleans",
    subtitle = sprintf("Each red dot is one of the %d open local-food restaurants", nrow(points)),
    theme = theme(plot.title = element_text(face = "bold", size = 15))
  )

ggsave("figures/geography_systems.png", figure_systems, width = 12, height = 8.5, dpi = 150, bg = "white")

# ---- Figure 2: how many areas are large enough to compare ----------------------------

size_classes <- geography_area_stats |>
  filter(scope == "open") |>
  mutate(size = cut(restaurants, breaks = c(0, 1, 4, 9, Inf),
                    labels = c("1 restaurant", "2 to 4", "5 to 9", "10 or more"))) |>
  count(system, size) |>
  mutate(system = factor(system, levels = rev(systems$system)))

figure_sizes <- ggplot(size_classes, aes(x = n, y = system, fill = size)) +
  geom_col(position = position_stack(reverse = TRUE), width = 0.7) +
  scale_fill_manual(values = c("#d9d4c7", "#b9b29f", "#e08e79", "#c0392b"), name = "Open restaurants in the area") +
  labs(title = "Small areas hold too few restaurants to compare",
       subtitle = "Number of areas by how many open local-food restaurants they contain",
       x = "Number of areas", y = NULL) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold"), legend.position = "bottom",
        panel.grid.major.y = element_blank(), panel.grid.minor = element_blank())

ggsave("figures/geography_area_sizes.png", figure_sizes, width = 9, height = 4.5, dpi = 150, bg = "white")

# ---- Report --------------------------------------------------------------------------

geography_comparison |>
  mutate(across(where(is.double), \(v) round(v, 2))) |>
  as.data.frame() |>
  print(row.names = FALSE)
