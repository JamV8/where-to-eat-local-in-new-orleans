# 11_import_benchmark.R
# Large-data section: three ways to get the Louisiana reviews out of the 5 GB review file,
# with the time and the peak memory each one needs.
#
#   whole    read the entire file into memory, then filter           (the obvious first attempt)
#   chunked  read 100,000 lines at a time, keep only what is needed  (what 01_import.R does)
#   duckdb   let a database engine scan the file and return only the matching rows
#            (run twice: with all the memory it wants, and capped at 2 GB)
#
# Every method must read the same 6,990,280 rows and keep the same 761,673.
# Each method runs in its own R process so that its peak memory can be measured cleanly.
#
#   Rscript R/11_import_benchmark.R            runs all three and writes results/import_benchmark.csv
#   Rscript R/11_import_benchmark.R chunked    runs one method (used by the line above)
#
# Needs the raw Yelp file in data/raw/. Takes several minutes.

review_file <- "data/raw/yelp_academic_dataset_review.json"
stopifnot(file.exists(review_file))

method <- commandArgs(trailingOnly = TRUE)

if (length(method) == 1) {
  # ---- one method, in this process ----------------------------------------------------------
  suppressPackageStartupMessages(library(jsonlite))
  louisiana_ids <- readRDS("data/new_orleans/business_louisiana.rds")$business_id

  if (method == "whole") {
    everything <- stream_in(file(review_file), pagesize = 100000, verbose = FALSE)
    rows_read  <- nrow(everything)
    kept       <- everything[everything$business_id %in% louisiana_ids, ]

  } else if (method == "chunked") {
    rows_read <- 0
    pieces    <- list()
    stream_in(file(review_file), pagesize = 100000, verbose = FALSE, handler = function(chunk) {
      rows_read <<- rows_read + nrow(chunk)
      pieces[[length(pieces) + 1]] <<- chunk[chunk$business_id %in% louisiana_ids, ]
    })
    kept <- do.call(rbind, pieces)

  } else if (method %in% c("duckdb", "duckdb_2gb")) {
    suppressPackageStartupMessages({library(DBI); library(duckdb)})
    con <- dbConnect(duckdb())
    if (method == "duckdb_2gb") dbExecute(con, "SET memory_limit = '2GB'")
    dbWriteTable(con, "louisiana", data.frame(business_id = louisiana_ids))
    source_sql <- sprintf(
      "read_ndjson('%s', columns = {review_id: 'VARCHAR', user_id: 'VARCHAR', business_id: 'VARCHAR',
                                    stars: 'DOUBLE', useful: 'BIGINT', funny: 'BIGINT', cool: 'BIGINT',
                                    text: 'VARCHAR', date: 'VARCHAR'})", review_file)
    kept <- dbGetQuery(con, sprintf(
      "SELECT * FROM %s WHERE business_id IN (SELECT business_id FROM louisiana)", source_sql))
    rows_read <- dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s", source_sql))$n
    dbDisconnect(con, shutdown = TRUE)

  } else stop("unknown method: ", method)

  cat(sprintf("RESULT %s %d %d\n", method, as.integer(rows_read), nrow(kept)))

} else {
  # ---- all three, each timed in a separate process ----------------------------------------------
  run_one <- function(method) {
    cat("running:", method, "\n")
    output <- system2("/usr/bin/time", c("-l", "Rscript", "R/11_import_benchmark.R", method),
                      stdout = TRUE, stderr = TRUE)
    result  <- strsplit(grep("^RESULT ", output, value = TRUE), " ")[[1]]
    seconds <- as.numeric(sub("^\\s*([0-9.]+) real.*", "\\1", grep(" real ", output, value = TRUE)))
    peak    <- as.numeric(sub("^\\s*([0-9]+)\\s+maximum resident set size.*", "\\1",
                              grep("maximum resident set size", output, value = TRUE)))
    data.frame(method = method, rows_read = as.numeric(result[3]), rows_kept = as.numeric(result[4]),
               seconds = seconds, peak_memory_gb = peak / 1024^3)   # macOS reports bytes
  }
  benchmark <- do.call(rbind, lapply(c("chunked", "duckdb", "duckdb_2gb", "whole"), run_one))
  benchmark$file_size_gb <- file.size(review_file) / 1024^3
  write.csv(benchmark, "results/import_benchmark.csv", row.names = FALSE)
  print(benchmark, row.names = FALSE)
}
