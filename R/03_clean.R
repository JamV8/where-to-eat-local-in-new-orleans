# 03_clean.R
# Define "New Orleans restaurant", attach every geographic label, and build the category tables.
#
# Inputs : data/new_orleans/business_louisiana.rds, data/boundaries/*.rds
# Outputs: data/new_orleans/business_new_orleans.rds      one row per restaurant, all area labels
#          data/new_orleans/restaurant_categories.rds     one row per restaurant-category pair
#          results/city_vs_boundary.csv                   Yelp city label vs. official city polygon
#          results/category_counts.csv, results/category_pairs.csv
#
# Run from the project root:  Rscript R/03_clean.R

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(sf)
})

louisiana <- readRDS("data/new_orleans/business_louisiana.rds")
b <- function(name) readRDS(file.path("data/boundaries", paste0(name, ".rds")))

# ---- 1. Restaurants anywhere in Louisiana, as points ----------------------------------------------

la_restaurants <- louisiana |>
  filter(!is.na(categories), str_detect(categories, regex("\\bRestaurants\\b", ignore_case = TRUE))) |>
  mutate(
    business_name = str_squish(name),
    city_clean    = str_to_title(str_squish(city)),
    postal_code   = na_if(str_squish(postal_code), ""),
    categories    = str_squish(categories)
  ) |>
  distinct(business_id, .keep_all = TRUE)

stopifnot(!anyNA(la_restaurants$latitude), !anyNA(la_restaurants$longitude))

points <- st_as_sf(la_restaurants, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

# ---- 2. Yelp's city label vs. the official city polygon -------------------------------------------

points <- points |> st_join(b("places_louisiana"), join = st_within, left = TRUE)

city_vs_boundary <- points |>
  st_drop_geometry() |>
  count(city_clean, place_name, name = "restaurants", sort = TRUE)
write.csv(city_vs_boundary, "results/city_vs_boundary.csv", row.names = FALSE)

# Definition used in this project: a restaurant is "in New Orleans" when its coordinates fall
# inside the official Census boundary of the city, whatever Yelp's free-text city field says.
nola <- points |> filter(place_name == "New Orleans")

# ---- 3. Attach every geographic system we compare -------------------------------------------------

join_area <- function(x, layer, cols) {
  st_join(x, b(layer)[cols], join = st_within, left = TRUE)
}
nola <- nola |>
  join_area("zctas", "zcta") |>
  join_area("tracts", "tract_name") |>
  join_area("block_groups", "block_group_name") |>
  join_area("neighborhoods", "neighborhood") |>
  join_area("wards", "ward_name") |>
  join_area("planning_districts", c("planning_district", "part_of_town"))

# A point on a shared edge can match two polygons; keep one row per business.
nola <- nola |> distinct(business_id, .keep_all = TRUE)

# Parts of town are the first level of the analysis, so no restaurant should be left without one.
# A few restaurants stand on piers over the lake, just outside every district polygon:
# they get the nearest district, and the distance is reported below.
districts <- b("planning_districts")
outside <- which(is.na(nola$part_of_town))
nearest <- st_nearest_feature(nola[outside, ], districts)
nearest_distance_m <- as.numeric(st_distance(nola[outside, ], districts[nearest, ], by_element = TRUE))
nola$planning_district[outside] <- districts$planning_district[nearest]
nola$part_of_town[outside]      <- districts$part_of_town[nearest]

business_new_orleans <- nola |>
  st_drop_geometry() |>
  select(
    business_id, business_name, address, city, city_clean, postal_code, latitude, longitude,
    stars, review_count, is_open, price_range, categories,
    zcta, tract_name, block_group_name, neighborhood, ward_name, planning_district, part_of_town
  )
saveRDS(business_new_orleans, "data/new_orleans/business_new_orleans.rds", compress = "xz")

# ---- 4. Category tables ---------------------------------------------------------------------------

restaurant_categories <- business_new_orleans |>
  select(business_id, categories) |>
  separate_longer_delim(categories, delim = ",") |>
  mutate(category = str_to_lower(str_squish(categories))) |>
  filter(category != "", !category %in% c("restaurants", "food")) |>
  distinct(business_id, category)
saveRDS(restaurant_categories, "data/new_orleans/restaurant_categories.rds", compress = "xz")

category_counts <- restaurant_categories |> count(category, name = "restaurants", sort = TRUE)
write.csv(category_counts, "results/category_counts.csv", row.names = FALSE)

category_pairs <- restaurant_categories |>
  inner_join(restaurant_categories, by = "business_id", relationship = "many-to-many") |>
  filter(category.x < category.y) |>
  count(category.x, category.y, name = "restaurants", sort = TRUE)
write.csv(category_pairs, "results/category_pairs.csv", row.names = FALSE)

# ---- 5. Console summary ---------------------------------------------------------------------------

cat("\nLouisiana restaurants:", nrow(la_restaurants),
    "\nInside the New Orleans boundary:", nrow(business_new_orleans),
    "\n  of which Yelp city is not 'New Orleans':", sum(business_new_orleans$city_clean != "New Orleans"),
    "\nYelp city 'New Orleans' but outside the boundary:",
    sum(points$city_clean == "New Orleans" & (is.na(points$place_name) | points$place_name != "New Orleans")),
    "\nStill open:", sum(business_new_orleans$is_open == 1), "\n")

cat("\nUnmatched restaurants per geographic system:\n")
print(colSums(is.na(business_new_orleans[c("zcta", "tract_name", "block_group_name", "neighborhood", "ward_name", "part_of_town")])))

cat(sprintf("\nPart of town taken from the nearest district for %d restaurants (farthest: %.0f m from a district edge)\n",
            length(outside), if (length(outside) > 0) max(nearest_distance_m) else 0))

cat("\nTop 40 categories:\n")
print(head(category_counts, 40), n = 40)
