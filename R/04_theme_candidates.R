# 04_theme_candidates.R
# Evidence for choosing the theme (decision #1 in notes/decisions.md).
# For each candidate group of categories, count what the assignment asks about:
# restaurants, how the categories overlap, how the restaurants spread over
# geographic areas, and how many reviewers are active enough inside the theme.
#
# Input : data/new_orleans/business_new_orleans.rds, restaurant_categories.rds,
#         data/raw/derived/reviews_louisiana_with_text.rds
# Output: results/theme_candidates.csv

suppressPackageStartupMessages(library(dplyr))

business   <- readRDS("data/new_orleans/business_new_orleans.rds")
categories <- readRDS("data/new_orleans/restaurant_categories.rds")
reviews    <- readRDS("data/raw/derived/reviews_louisiana_with_text.rds") |>
  select(business_id, user_id, stars) |>
  semi_join(business, by = "business_id")

themes <- list(
  "Local classics" = c("cajun/creole", "seafood", "southern", "soul food"),
  "Morning"        = c("breakfast & brunch", "coffee & tea", "cafes", "bakeries", "desserts", "donuts"),
  "Quick bite"     = c("sandwiches", "fast food", "delis", "burgers", "pizza"),
  "Comfort/BBQ"    = c("barbeque", "chicken wings", "burgers", "soul food", "chicken shop", "comfort food", "hot dogs"),
  "Europe"         = c("italian", "french", "mediterranean", "pizza", "spanish", "tapas/small plates", "greek"),
  "Nightlife"      = c("cocktail bars", "wine bars", "lounges", "pubs", "dive bars", "gastropubs"),
  "Plant-based"    = c("vegetarian", "vegan", "salad", "juice bars & smoothies", "gluten-free"),
  "Asian"          = c("vietnamese", "chinese", "japanese", "sushi bars", "thai", "asian fusion", "korean", "ramen", "noodles"),
  "Latin"          = c("mexican", "latin american", "tacos", "tex-mex", "cuban", "caribbean", "honduran"),
  "Sweet tooth"    = c("desserts", "bakeries", "ice cream & frozen yogurt", "donuts", "patisserie/cake shop", "creperies")
)

min_reviewer_activity <- 5   # the assignment's suggested starting threshold

describe_theme <- function(theme_name, theme_categories) {
  # how many of the theme's categories each restaurant carries
  labels_per_restaurant <- categories |>
    filter(category %in% theme_categories) |>
    count(business_id, name = "theme_labels")

  theme_business <- business |> inner_join(labels_per_restaurant, by = "business_id")
  theme_open     <- theme_business |> filter(is_open == 1)

  per_neighborhood <- theme_open |> count(neighborhood)

  theme_reviews <- reviews |> semi_join(theme_business, by = "business_id")
  reviewer_activity <- theme_reviews |> count(user_id, name = "reviews_in_theme")
  eligible <- reviewer_activity |> filter(reviews_in_theme >= min_reviewer_activity)

  reviews_per_open_restaurant <- theme_reviews |>
    semi_join(theme_open, by = "business_id") |>
    count(business_id)

  tibble(
    theme                          = theme_name,
    n_categories                   = length(theme_categories),
    restaurants                    = nrow(theme_business),
    restaurants_open               = nrow(theme_open),
    share_with_2plus_theme_labels  = mean(theme_business$theme_labels >= 2),
    neighborhoods_open             = nrow(per_neighborhood),
    neighborhoods_5plus_open       = sum(per_neighborhood$n >= 5),
    neighborhoods_10plus_open      = sum(per_neighborhood$n >= 10),
    zctas_10plus_open              = sum(count(theme_open, zcta)$n >= 10),
    wards_10plus_open              = sum(count(filter(theme_open, !is.na(ward_name)), ward_name)$n >= 10),
    share_in_top2_neighborhoods    = sum(sort(per_neighborhood$n, decreasing = TRUE)[1:2]) / nrow(theme_open),
    reviews                        = nrow(theme_reviews),
    reviewers                      = nrow(reviewer_activity),
    eligible_reviewers             = nrow(eligible),
    share_reviews_from_eligible    = sum(eligible$reviews_in_theme) / nrow(theme_reviews),
    open_with_50plus_reviews       = sum(reviews_per_open_restaurant$n >= 50),
    mean_stars_of_reviews          = mean(theme_reviews$stars)
  )
}

theme_candidates <- bind_rows(Map(describe_theme, names(themes), themes))

write.csv(theme_candidates, "results/theme_candidates.csv", row.names = FALSE)

theme_candidates |>
  mutate(across(where(is.double), \(x) round(x, 2))) |>
  as.data.frame() |>
  print(row.names = FALSE)
