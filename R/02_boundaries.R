# 02_boundaries.R
# Download every boundary layer the project compares and cache it in data/boundaries/.
#
#   Census (via tigris):      city boundary (place), ZCTAs, census tracts, block groups
#   City of New Orleans:      Neighborhood Statistical Areas, wards   (data.nola.gov)
#
# All layers are stored in WGS84 (EPSG:4326) so they match Yelp's latitude/longitude.
# Run from the project root:  Rscript R/02_boundaries.R

suppressPackageStartupMessages({
  library(dplyr)
  library(sf)
  library(tigris)
  library(stringr)
})
options(tigris_use_cache = TRUE)

out_dir <- "data/boundaries"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
save_layer <- function(x, name) {
  saveRDS(x, file.path(out_dir, paste0(name, ".rds")), compress = "xz")
  cat(sprintf("%-22s %4d areas\n", name, nrow(x)))
}

# ---- Census layers --------------------------------------------------------------------------------

# City boundary. New Orleans city and Orleans Parish are the same area (consolidated city-parish).
places_la <- places(state = "LA", cb = TRUE, year = 2024, class = "sf") |>
  st_transform(4326) |>
  select(GEOID, place_name = NAME)
save_layer(places_la, "places_louisiana")

nola_boundary <- places_la |> filter(place_name == "New Orleans")
save_layer(nola_boundary, "new_orleans_boundary")

# Census tracts and block groups for Orleans Parish (FIPS 22071)
tracts <- tracts(state = "LA", county = "071", cb = TRUE, year = 2024, class = "sf") |>
  st_transform(4326) |>
  select(GEOID, tract_name = NAMELSAD)
save_layer(tracts, "tracts")

block_groups <- block_groups(state = "LA", county = "071", cb = TRUE, year = 2024, class = "sf") |>
  st_transform(4326) |>
  # "Block Group 2" repeats inside every tract, so the tract number (characters 6-11 of GEOID)
  # goes into the name to make it unique: "Tract 60, Block Group 2".
  mutate(block_group_name = paste0("Tract ", as.numeric(substr(GEOID, 6, 11)) / 100, ", ", NAMELSAD)) |>
  select(GEOID, block_group_name)
stopifnot(!anyDuplicated(tracts$tract_name), !anyDuplicated(block_groups$block_group_name))
save_layer(block_groups, "block_groups")

# ZCTAs are published for the whole country; keep those that overlap the city.
zcta_all <- zctas(cb = TRUE, starts_with = "70", year = 2020, class = "sf") |>
  st_transform(4326)
zcta_col <- names(zcta_all)[str_detect(names(zcta_all), "^ZCTA5CE")][1]
zctas_nola <- zcta_all |>
  select(zcta = all_of(zcta_col)) |>
  st_filter(nola_boundary, .predicate = st_intersects)
save_layer(zctas_nola, "zctas")

# ---- City of New Orleans layers (Socrata open data portal) ----------------------------------------

read_nola <- function(dataset_id) {
  url <- sprintf("https://data.nola.gov/resource/%s.geojson?$limit=5000", dataset_id)
  st_read(url, quiet = TRUE) |> st_transform(4326) |> st_make_valid()
}

# Neighborhood Statistical Areas (72 areas, defined by the City Planning Commission / Data Center)
neighborhoods <- read_nola("exvn-jeh2") |>
  transmute(neigh_id, neighborhood = str_to_title(gnocdc_lab))
save_layer(neighborhoods, "neighborhoods")

# Wards (17 historical political divisions)
wards <- read_nola("d4y8-p3zu") |>
  transmute(ward = as.integer(ward), ward_name = paste("Ward", ward)) |>
  arrange(ward)
save_layer(wards, "wards")

# Planning districts: the City Planning Commission groups the neighborhoods into 13 larger
# parts of town (district 1 is split into 1a and 1b, so the layer has 14 areas). These are the
# areas people actually name when they talk about the city: Uptown, Mid-City, Marigny/Bywater.
# The file only carries the district numbers; the names are the ones the Commission uses.
part_of_town_names <- c(
  "Planning District 1a" = "CBD / Warehouse District",
  "Planning District 1b" = "French Quarter",
  "Planning District 2"  = "Central City / Garden District",
  "Planning District 3"  = "Uptown / Carrollton",
  # District 4 is officially "Mid-City", but it also holds Tremé and Bayou St. John, where most of
  # its best restaurants are; the longer label says where a visitor would actually go.
  "Planning District 4"  = "Mid-City / Tremé / Bayou St. John",
  "Planning District 5"  = "Lakeview",
  "Planning District 6"  = "Gentilly",
  "Planning District 7"  = "Marigny / Bywater",
  "Planning District 8"  = "Lower Ninth Ward",
  "Planning District 9"  = "New Orleans East",
  "Planning District 10" = "Village de L'Est",
  "Planning District 11" = "Venetian Isles / Lake Catherine",
  "Planning District 12" = "Algiers",
  "Planning District 13" = "English Turn"
)
planning_districts <- read_nola("put8-sks2") |>
  transmute(planning_district = district_n,
            part_of_town = unname(part_of_town_names[district_n]))
stopifnot(!anyNA(planning_districts$part_of_town), !anyDuplicated(planning_districts$part_of_town))
save_layer(planning_districts, "planning_districts")

# Water, for the site's map only: the lake and the river are what make the outline of New Orleans
# recognisable. Census area-water polygons for Orleans Parish, larger bodies only.
water <- area_water("LA", "071", year = 2024) |>
  st_transform(4326) |>
  filter(AWATER > 3e5) |>
  transmute(water_id = HYDROID, name = FULLNAME, square_km = AWATER / 1e6) |>
  st_make_valid()
save_layer(water, "water")
