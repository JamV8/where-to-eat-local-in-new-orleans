# 01_import.R
# One pass over the raw Yelp JSON files (one JSON record per line).
#
#   business.json (~120 MB, 150k rows)  -> read whole, keep the columns we need
#   review.json   (~5 GB, ~7M rows)     -> read in chunks, never held in memory at once
#
# From the single pass over the review file we keep two things:
#   1. every review of a Louisiana business (New Orleans is the only Louisiana metro in the dataset);
#      the exact "New Orleans restaurant" definition is applied later, in 02_clean.R, so changing that
#      definition never requires re-reading 5 GB
#   2. a per-reviewer, per-state tally of ALL their reviews (count and sum of stars), which lets us
#      tell locals from visitors and compute a reviewer's overall baseline
#
# Run from the project root:  Rscript R/01_import.R

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(jsonlite)
})

raw_dir <- "data/raw"
out_dir <- "data/new_orleans"
big_dir <- "data/raw/derived"          # large intermediate files, not committed
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(big_dir, recursive = TRUE, showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

business_file <- file.path(raw_dir, "yelp_academic_dataset_business.json")
review_file   <- file.path(raw_dir, "yelp_academic_dataset_review.json")
stopifnot(file.exists(business_file), file.exists(review_file))

# ---- 1. Business table ----------------------------------------------------------------------------

t_business <- system.time({
  business_raw <- stream_in(file(business_file), verbose = FALSE)
})

# `attributes` and `hours` arrive as nested data frames; pull out the few attributes we may use
# and drop the rest.
business <- tibble(
  business_id  = business_raw$business_id,
  name         = business_raw$name,
  address      = business_raw$address,
  city         = business_raw$city,
  state        = business_raw$state,
  postal_code  = business_raw$postal_code,
  latitude     = business_raw$latitude,
  longitude    = business_raw$longitude,
  stars        = business_raw$stars,
  review_count = business_raw$review_count,
  is_open      = business_raw$is_open,
  categories   = business_raw$categories,
  price_range  = suppressWarnings(as.integer(business_raw$attributes$RestaurantsPriceRange2))
)
rm(business_raw)

saveRDS(business, file.path(big_dir, "business_all.rds"), compress = "xz")

louisiana <- business |> filter(state == "LA")
saveRDS(louisiana, file.path(out_dir, "business_louisiana.rds"), compress = "xz")

cat(sprintf("Businesses: %s total, %s in Louisiana (%.1f s)\n",
            format(nrow(business), big.mark = ","), format(nrow(louisiana), big.mark = ","),
            t_business[["elapsed"]]))

# ---- 2. Review table, in chunks -------------------------------------------------------------------

la_ids         <- louisiana$business_id
state_of       <- setNames(business$state, business$business_id)   # business_id -> state lookup
page_size      <- 100000
review_chunks  <- list()
tally_chunks   <- list()
rows_seen      <- 0
peak_chunk_mb  <- 0

handle_chunk <- function(df) {
  rows_seen <<- rows_seen + nrow(df)
  peak_chunk_mb <<- max(peak_chunk_mb, as.numeric(object.size(df)) / 1024^2)

  # (2) reviewer tally over ALL reviews in this chunk
  tally_chunks[[length(tally_chunks) + 1]] <<- df |>
    transmute(user_id, state = unname(state_of[business_id]), stars) |>
    group_by(user_id, state) |>
    summarise(n_reviews = n(), sum_stars = sum(stars), .groups = "drop")

  # (1) keep only reviews of Louisiana businesses, and only the columns we need
  keep <- df$business_id %in% la_ids
  if (any(keep)) {
    review_chunks[[length(review_chunks) + 1]] <<- df[keep, c(
      "review_id", "business_id", "user_id", "stars", "date", "text", "useful", "funny", "cool"
    )]
  }

  if (rows_seen %% 1e6 == 0) {
    cat(sprintf("  ... %s reviews read\n", format(rows_seen, big.mark = ",")))
  }
  invisible(NULL)
}

t_review <- system.time({
  stream_in(file(review_file), handler = handle_chunk, pagesize = page_size, verbose = FALSE)
})

reviews_la <- bind_rows(review_chunks) |> as_tibble()
rm(review_chunks)

reviewer_tally <- bind_rows(tally_chunks) |>
  group_by(user_id, state) |>
  summarise(n_reviews = sum(n_reviews), sum_stars = sum(sum_stars), .groups = "drop")
rm(tally_chunks)

cat(sprintf("Reviews: %s read, %s kept for Louisiana businesses (%.1f min)\n",
            format(rows_seen, big.mark = ","), format(nrow(reviews_la), big.mark = ","),
            t_review[["elapsed"]] / 60))

# Full reviews (with text) are large: keep them outside the committed folder.
saveRDS(reviews_la, file.path(big_dir, "reviews_louisiana_with_text.rds"), compress = "xz")
saveRDS(reviewer_tally, file.path(big_dir, "reviewer_tally_by_state.rds"), compress = "xz")

# ---- 3. Record what the import cost, for the large-data section of the report --------------------

import_log <- tibble(
  step = c("business.json (whole file)", "review.json (chunked)"),
  file_size_gb = round(file.size(c(business_file, review_file)) / 1024^3, 2),
  rows_read = c(nrow(business), rows_seen),
  rows_kept = c(nrow(louisiana), nrow(reviews_la)),
  seconds = round(c(t_business[["elapsed"]], t_review[["elapsed"]]), 1),
  chunk_rows = c(NA, page_size),
  peak_chunk_mb = c(NA, round(peak_chunk_mb, 1))
)
write.csv(import_log, "results/import_log.csv", row.names = FALSE)
print(import_log)
