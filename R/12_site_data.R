# 12_site_data.R
# Everything the website shows, taken from the same result files as the report.
# The site never computes a result of its own: it draws what this file exports.
#
# Input : results/*.csv, data/new_orleans/theme_reviews.rds, data/boundaries/*.rds
# Output: assets/data/site_data.json   (and site_data.js, the same data as a script)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(sf)
  library(jsonlite)
})

scores    <- read.csv("results/restaurant_scores.csv")
stability <- read.csv("results/ranking_stability.csv")
areas     <- read.csv("results/area_scores.csv")
stab_sum  <- read.csv("results/stability_summary.csv")
center    <- read.csv("results/center_vs_rest.csv")
import    <- read.csv("results/import_log.csv")
thresholds <- read.csv("results/reviewer_thresholds.csv")
beats     <- read.csv("results/beats_french_quarter.csv")
reviews   <- readRDS("data/new_orleans/theme_reviews.rds")

great_cut <- unname(quantile(stability$ordinary_average, 0.75))

# ---- Restaurants: the ranked ones, with the star counts the "shake" needs -------------------

star_counts <- reviews |>
  semi_join(stability, by = "business_id") |>
  count(business_id, stars) |>
  pivot_wider(names_from = stars, values_from = n, values_fill = 0, names_prefix = "s") |>
  select(business_id, s1, s2, s3, s4, s5)

restaurants <- stability |>
  left_join(star_counts, by = "business_id") |>
  arrange(rank_ordinary) |>
  transmute(
    rank     = rank_ordinary,
    name     = business_name,
    part     = part_of_town,
    hood     = neighborhood,
    lon      = round(longitude, 5),
    lat      = round(latitude, 5),
    reviews  = reviews_all,
    # six decimals, so that the page rounds to the same two decimals as the report
    avg      = round(ordinary_average, 6),
    low      = round(ordinary_low, 6),
    high     = round(ordinary_high, 6),
    chance   = round(ordinary_chance_top10, 6),
    adjusted = round(adjusted_score, 6),
    rankAdjusted = rank_adjusted,
    great    = ordinary_average >= great_cut,
    stars    = Map(c, s1, s2, s3, s4, s5)     # how many 1-, 2-, 3-, 4- and 5-star reviews
  )

# ---- Boundaries, simplified so the file stays small -------------------------------------------

rings <- function(layer, name_column, tolerance_m = 35) {
  shapes <- readRDS(file.path("data/boundaries", paste0(layer, ".rds"))) |>
    st_transform(32615) |>                       # metres, so the tolerance means metres
    st_simplify(dTolerance = tolerance_m, preserveTopology = TRUE) |>
    st_transform(4326)
  lapply(seq_len(nrow(shapes)), function(i) {
    coordinates <- as.data.frame(st_coordinates(st_cast(shapes[i, ], "MULTIPOLYGON")))
    pieces <- split(coordinates, list(coordinates$L1, coordinates$L2), drop = TRUE)
    list(name  = shapes[[name_column]][i],
         rings = unname(lapply(pieces, function(p) unname(as.matrix(round(p[, c("X", "Y")], 5))))))
  })
}

parts <- rings("planning_districts", "part_of_town")
parts <- lapply(parts, function(p) {
  row <- areas[areas$part_of_town == p$name, ]
  c(p, if (nrow(row) == 1) list(
    restaurants = row$restaurants, great = row$great_restaurants, share = round(row$share_great, 3),
    top10 = row$top10_restaurants, average = round(row$average_rating, 3), compared = row$compared,
    chanceFirst = if (is.na(row$chance_first)) NULL else round(row$chance_first, 3),
    beatsQuarter = if (p$name %in% beats$part_of_town) round(beats$beats_on_share_great[beats$part_of_town == p$name], 3) else NULL
  ) else list(restaurants = 0, compared = FALSE))
})

# ---- Headline numbers ---------------------------------------------------------------------------

ordinary <- stab_sum[stab_sum$ranking == "ordinary", ]
tourist  <- center[center$where == "Tourist center", ]
rest     <- center[center$where == "Rest of the city", ]

# Water inside the frame of the map, as plain rings (the lake reaches far beyond the city, so it is cut to the frame)
frame <- st_as_sfc(st_bbox(c(xmin = -90.30, xmax = -89.80, ymin = 29.80, ymax = 30.16), crs = 4326))
water_shapes <- readRDS("data/boundaries/water.rds") |>
  st_transform(32615) |> st_simplify(dTolerance = 40, preserveTopology = TRUE) |> st_transform(4326) |>
  st_make_valid() |> suppressWarnings(expr = _) |> st_intersection(frame) |> suppressWarnings(expr = _)
water_shapes <- water_shapes[st_geometry_type(water_shapes) %in% c("POLYGON", "MULTIPOLYGON"), ]
water <- lapply(seq_len(nrow(water_shapes)), function(i) {
  coordinates <- as.data.frame(st_coordinates(st_cast(water_shapes[i, ], "MULTIPOLYGON")))
  outer <- coordinates[coordinates$L1 == 1, ]                      # outer rings only: islands are not needed at this scale
  pieces <- split(outer, outer$L2, drop = TRUE)
  list(name = water_shapes$name[i], rings = unname(lapply(pieces, function(p) unname(as.matrix(round(p[, c("X", "Y")], 5))))))
})

site_data <- list(
  numbers = list(
    reviewsRead        = import$rows_read[grepl("review", import$step)],
    themeReviews       = nrow(reviews),
    themeRestaurants   = n_distinct(reviews$business_id),
    reviewers          = n_distinct(reviews$user_id),
    activeReviewers    = thresholds$reviewers_kept[thresholds$threshold == 5],
    ranked             = nrow(stability),
    greatCut           = round(great_cut, 2),
    surePlaces         = ordinary$restaurants_with_90pct_chance,
    contenders         = ordinary$restaurants_with_5pct_chance,
    keptOnAverage      = round(ordinary$average_top10_members_kept, 1),
    centerAverage      = round(tourist$average_rating, 2),
    restAverage        = round(rest$average_rating, 2),
    firstYear          = as.integer(format(min(reviews$date), "%Y")),
    lastMonth          = format(max(reviews$date), "%B %Y")
  ),
  restaurants   = restaurants,
  parts         = parts,
  water         = water
)

dir.create("assets/data", recursive = TRUE, showWarnings = FALSE)
json <- toJSON(site_data, auto_unbox = TRUE, digits = NA, null = "null")
writeLines(json, "assets/data/site_data.json", useBytes = TRUE)
writeLines(paste0("window.SITE_DATA = ", json, ";"), "assets/data/site_data.js", useBytes = TRUE)

cat(sprintf("site_data.json: %.0f KB, %d restaurants, %d parts of town\n",
            file.size("assets/data/site_data.json") / 1024, nrow(restaurants), length(parts)))
