# 05_theme.R
# The chosen theme (decisions #1 and #15): local food in New Orleans.
#
# Inclusion rule
#   A restaurant is in the theme if it carries at least one of four Yelp labels:
#   Cajun/Creole, Southern, Soul Food, Seafood.
# One exception
#   "Seafood" names an ingredient, not a cooking tradition: a sushi bar carries it too.
#   So a restaurant that gets in ONLY through "Seafood" is left out when Yelp also
#   labels it with another country's or region's cuisine (Japanese, Italian, ...).
#   Every restaurant removed this way is listed in results/theme_excluded.csv.
#
# This script answers the assignment's questions about the category group:
#   - how many restaurants carry each category;
#   - how often the categories appear together (co-occurrence);
#   - which other Yelp labels these restaurants carry;
#   - whether the restaurants are spread over enough geographic areas.
# It also attaches the reviews of the theme restaurants.
#
# Input : data/new_orleans/business_new_orleans.rds, restaurant_categories.rds,
#         data/boundaries/*.rds, data/raw/derived/reviews_louisiana_with_text.rds
# Output: data/new_orleans/theme_restaurants.rds, theme_reviews.rds,
#         results/theme_*.csv

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(lubridate)
})

core_categories  <- c("cajun/creole", "southern", "soul food")
theme_categories <- c(core_categories, "seafood")

# Yelp labels that name the cuisine of another country or region, or a dish that
# belongs to one. Picked by reading all 294 labels found on New Orleans restaurants.
other_cuisines <- c(
  "african", "arabic", "argentine", "asian fusion", "basque", "brazilian", "british",
  "burmese", "caribbean", "chinese", "colombian", "cuban", "dim sum", "egyptian",
  "ethiopian", "filipino", "french", "german", "greek", "haitian", "hawaiian",
  "honduran", "indian", "irish", "italian", "japanese", "japanese curry", "korean",
  "laotian", "latin american", "lebanese", "malaysian", "mediterranean", "mexican",
  "middle eastern", "modern european", "moroccan", "new mexican cuisine", "nicaraguan",
  "pakistani", "pan asian", "persian/iranian", "peruvian", "poke", "polish", "ramen",
  "russian", "salvadoran", "shanghainese", "spanish", "sushi bars", "szechuan",
  "tacos", "taiwanese", "teppanyaki", "tex-mex", "thai", "trinidadian", "turkish",
  "ukrainian", "venezuelan", "vietnamese"
)

business   <- readRDS("data/new_orleans/business_new_orleans.rds")
categories <- readRDS("data/new_orleans/restaurant_categories.rds")
stopifnot(all(c(theme_categories, other_cuisines) %in% categories$category))

# ---- 1. Which restaurants are in the theme ---------------------------------

theme_labels_all <- categories |>
  filter(category %in% theme_categories)

# one row per restaurant, one TRUE/FALSE column per theme category
label_flags <- theme_labels_all |>
  mutate(has = TRUE,
         column = paste0("is_", gsub("[^a-z]+", "_", category))) |>
  select(business_id, column, has) |>
  pivot_wider(names_from = column, values_from = has, values_fill = FALSE)

cuisine_labels <- categories |>
  filter(category %in% other_cuisines) |>
  group_by(business_id) |>
  summarise(other_cuisine_labels = paste(category, collapse = ", "), .groups = "drop")

candidates <- business |>
  inner_join(label_flags, by = "business_id") |>
  left_join(cuisine_labels, by = "business_id") |>
  mutate(
    theme_labels = is_cajun_creole + is_southern + is_soul_food + is_seafood,
    entered_by   = if_else(is_cajun_creole | is_southern | is_soul_food, "core label", "seafood only"),
    excluded     = entered_by == "seafood only" & !is.na(other_cuisine_labels)
  )

theme_excluded <- candidates |>
  filter(excluded) |>
  arrange(desc(review_count)) |>
  select(business_id, business_name, is_open, review_count, stars, other_cuisine_labels, categories)

write.csv(theme_excluded, "results/theme_excluded.csv", row.names = FALSE)

theme_restaurants <- candidates |>
  filter(!excluded) |>
  select(-excluded, -other_cuisine_labels)

saveRDS(theme_restaurants, "data/new_orleans/theme_restaurants.rds")

theme_labels <- theme_labels_all |>
  semi_join(theme_restaurants, by = "business_id")

inclusion_summary <- candidates |>
  mutate(step = case_when(entered_by == "core label" ~ "1. has Cajun/Creole, Southern or Soul Food",
                          !excluded                  ~ "2. Seafood only, no other cuisine label: kept",
                          TRUE                       ~ "3. Seafood only, other cuisine label: left out")) |>
  group_by(step) |>
  summarise(restaurants = n(), open = sum(is_open == 1), .groups = "drop")

write.csv(inclusion_summary, "results/theme_inclusion_summary.csv", row.names = FALSE)

# ---- 2. Category counts ------------------------------------------------------

theme_category_counts <- theme_labels |>
  inner_join(select(business, business_id, is_open), by = "business_id") |>
  group_by(category) |>
  summarise(restaurants = n(), open = sum(is_open == 1), .groups = "drop") |>
  arrange(desc(restaurants)) |>
  bind_rows(tibble(category    = "THE THEME (any of the four, after the exception)",
                   restaurants = nrow(theme_restaurants),
                   open        = sum(theme_restaurants$is_open == 1)))

write.csv(theme_category_counts, "results/theme_category_counts.csv", row.names = FALSE)

# ---- 3. Co-occurrence of the theme categories ---------------------------------
# Counted on all New Orleans restaurants, before the exception is applied, because
# this is the evidence for choosing the categories in the first place.
# lift = how many times more often the two labels appear together than they
# would if they were handed out independently (1 = no relationship).

n_all_restaurants <- nrow(business)
category_sizes <- count(theme_labels_all, category, name = "n")

theme_category_pairs <- theme_labels_all |>
  inner_join(theme_labels_all, by = "business_id", relationship = "many-to-many") |>
  filter(category.x < category.y) |>
  count(category_a = category.x, category_b = category.y, name = "both") |>
  left_join(rename(category_sizes, category_a = category, n_a = n), by = "category_a") |>
  left_join(rename(category_sizes, category_b = category, n_b = n), by = "category_b") |>
  mutate(share_of_smaller = both / pmin(n_a, n_b),
         expected_if_independent = n_a * n_b / n_all_restaurants,
         lift = both / expected_if_independent)

write.csv(theme_category_pairs, "results/theme_category_pairs.csv", row.names = FALSE)

# which combinations of the four labels the theme restaurants actually carry
theme_label_combinations <- theme_labels |>
  arrange(category) |>
  group_by(business_id) |>
  summarise(labels = paste(category, collapse = " + "), .groups = "drop") |>
  count(labels, name = "restaurants", sort = TRUE) |>
  mutate(share = restaurants / sum(restaurants))

write.csv(theme_label_combinations, "results/theme_label_combinations.csv", row.names = FALSE)

# ---- 4. Other labels carried by theme restaurants ------------------------------

all_category_sizes <- count(categories, category, name = "restaurants_citywide")

theme_other_categories <- categories |>
  semi_join(theme_restaurants, by = "business_id") |>
  filter(!category %in% theme_categories) |>
  count(category, name = "theme_restaurants_with_label", sort = TRUE) |>
  left_join(all_category_sizes, by = "category") |>
  mutate(share_of_theme = theme_restaurants_with_label / nrow(theme_restaurants),
         share_of_label_inside_theme = theme_restaurants_with_label / restaurants_citywide) |>
  head(20)

write.csv(theme_other_categories, "results/theme_other_categories.csv", row.names = FALSE)

# ---- 5. Spread over geographic areas --------------------------------------------
# Assignment: at least 10 restaurants located in at least 7 different areas.
# The first five systems are the ones listed in the assignment; parts of town are added
# because that is how people actually name areas of the city (decision #5).

systems <- tribble(
  ~system,                           ~column,             ~boundary_file,
  "ZIP code areas (ZCTA)",           "zcta",              "data/boundaries/zctas.rds",
  "Census tracts",                   "tract_name",        "data/boundaries/tracts.rds",
  "Census block groups",             "block_group_name",  "data/boundaries/block_groups.rds",
  "Neighborhood statistical areas",  "neighborhood",      "data/boundaries/neighborhoods.rds",
  "Wards",                           "ward_name",         "data/boundaries/wards.rds",
  "Parts of town (planning districts)", "part_of_town",   "data/boundaries/planning_districts.rds"
)

coverage_one <- function(system, column, boundary_file) {
  per_area <- theme_restaurants |>
    filter(!is.na(.data[[column]])) |>
    group_by(area = .data[[column]]) |>
    summarise(restaurants = n(), open = sum(is_open == 1), .groups = "drop")
  tibble(
    system                 = system,
    areas_in_city          = nrow(readRDS(boundary_file)),
    areas_with_theme       = nrow(per_area),
    areas_with_theme_open  = sum(per_area$open > 0),
    restaurants_assigned   = sum(per_area$restaurants),
    restaurants_unassigned = nrow(theme_restaurants) - sum(per_area$restaurants),
    largest_area_share     = max(per_area$restaurants) / sum(per_area$restaurants)
  )
}

theme_area_coverage <- bind_rows(Map(coverage_one, systems$system, systems$column, systems$boundary_file))

write.csv(theme_area_coverage, "results/theme_area_coverage.csv", row.names = FALSE)

# ---- 6. Reviews of the theme restaurants ----------------------------------------
# The text of the reviews is not needed for the analysis and is left out.

theme_reviews <- readRDS("data/raw/derived/reviews_louisiana_with_text.rds") |>
  select(review_id, business_id, user_id, stars, date) |>
  semi_join(theme_restaurants, by = "business_id") |>
  mutate(date = as_date(ymd_hms(date)))   # dates are stored as "2018-07-07 22:09:11"

stopifnot(!anyNA(theme_reviews$date), !anyDuplicated(theme_reviews$review_id))

saveRDS(theme_reviews, "data/new_orleans/theme_reviews.rds")

# ---- Report ----------------------------------------------------------------------

show <- function(title, x) {
  cat("\n", title, "\n", sep = "")
  print(as.data.frame(mutate(x, across(where(is.double), \(v) round(v, 2)))), row.names = FALSE)
}

show("Who is in the theme", inclusion_summary)
show("Category counts", theme_category_counts)
show("Pairs of theme categories", theme_category_pairs)
show("Label combinations", theme_label_combinations)
show("Other labels on theme restaurants (top 20)", theme_other_categories)
show("Spread over geographic areas", theme_area_coverage)

cat(sprintf(
  "\nReviews: %s reviews of %s restaurants by %s reviewers, %s to %s\n",
  format(nrow(theme_reviews), big.mark = ","),
  format(n_distinct(theme_reviews$business_id), big.mark = ","),
  format(n_distinct(theme_reviews$user_id), big.mark = ","),
  min(theme_reviews$date), max(theme_reviews$date)
))
