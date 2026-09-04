#!/usr/bin/env Rscript
# ============================================================================
# main.R — Entry point for the Monopoly economic-policy Monte Carlo study.
# ----------------------------------------------------------------------------
# Usage (from the project root):
#   Rscript main.R                          # 4 players, 100 sims, all cores-1
#   Rscript main.R --players 8              # 8-player games
#   Rscript main.R --sims 500 --workers 4   # larger study, 4 workers
#   Rscript main.R --scenarios Baseline,UBI_Only --tag pilot
#
# Arguments:
#   --players N      number of players per game (2, 4, 6, or 8)     [default 4]
#   --sims N         Monte Carlo replications per scenario          [default 100]
#   --max-turns N    hard turn cap per game                         [default 200]
#   --workers N      parallel PSOCK workers (<=1 = sequential)      [default cores-1]
#   --scenarios L    comma-separated subset of scenario keys        [default all]
#   --out DIR        output directory                               [default results]
#   --tag STR        filename tag                                   [default ""]
#   --quiet          suppress progress messages
#   --help           show this help
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)

USAGE <- paste0(
  "Usage: Rscript main.R [options]\n",
  "  --players N      players per game (2/4/6/8)        [default 4]\n",
  "  --sims N         replications per scenario          [default 100]\n",
  "  --max-turns N    turn cap per game                  [default 200]\n",
  "  --workers N      parallel workers (<=1 sequential)  [default cores-1]\n",
  "  --scenarios L    comma-separated scenario subset    [default all]\n",
  "  --out DIR        output directory                   [default results]\n",
  "  --tag STR        filename tag                       [default '']\n",
  "  --quiet          suppress progress\n",
  "  --help           show this help\n"
)

parse_args <- function(args) {
  opt <- list(players = 4L, sims = 100L, max_turns = 200L, workers = NULL,
              scenarios = NULL, out = "results", tag = "", quiet = FALSE)
  i <- 1
  while (i <= length(args)) {
    a <- args[i]; nxt <- if (i < length(args)) args[i + 1] else NULL
    if (a %in% c("--help", "-h")) { cat(USAGE); quit(status = 0) }
    switch(a,
      "--players"   = { opt$players   <- as.integer(nxt); i <- i + 1 },
      "--sims"      = { opt$sims      <- as.integer(nxt); i <- i + 1 },
      "--max-turns" = { opt$max_turns <- as.integer(nxt); i <- i + 1 },
      "--workers"   = { opt$workers   <- as.integer(nxt); i <- i + 1 },
      "--scenarios" = { opt$scenarios <- strsplit(nxt, ",")[[1]]; i <- i + 1 },
      "--out"       = { opt$out       <- nxt; i <- i + 1 },
      "--tag"       = { opt$tag       <- nxt; i <- i + 1 },
      "--quiet"     = { opt$quiet     <- TRUE },
      stop("Unknown argument: ", a, call. = FALSE)
    )
    i <- i + 1
  }
  opt
}

main <- function() {
  opt <- parse_args(args)

  # Default worker count: one fewer than available cores (leave one free).
  # `inclusive` was added in newer R; guard for older builds like 4.4.x.
  if (is.null(opt$workers)) {
    nc <- tryCatch(parallel::detectCores(inclusive = FALSE),
                   error = function(e) parallel::detectCores())
    opt$workers <- max(1L, as.integer(nc) - 1L)
  }

  # Run from the directory containing run/run_simulations.R. Prefer the current
  # working directory; if the driver isn't there, search one level up (in case
  # the user launched from a subfolder).
  root <- getwd()
  if (!file.exists(file.path(root, "run", "run_simulations.R"))) {
    parent <- normalizePath("..", mustWork = FALSE)
    if (file.exists(file.path(parent, "run", "run_simulations.R"))) root <- parent
  }
  if (!file.exists(file.path(root, "run", "run_simulations.R"))) {
    stop("Cannot locate run/run_simulations.R. Run from the project root.")
  }
  setwd(root)

  source(file.path(root, "policy", "scenarios.R"))   # for SCENARIO_KEYS
  source(file.path(root, "run", "run_simulations.R"))

  scenarios <- if (is.null(opt$scenarios)) SCENARIO_KEYS else opt$scenarios
  bad <- setdiff(scenarios, SCENARIO_KEYS)
  if (length(bad) > 0) stop("Unknown scenario(s): ", paste(bad, collapse = ", "),
                            ". Valid: ", paste(SCENARIO_KEYS, collapse = ", "))

  if (!opt$quiet) {
    cat(sprintf("Monopoly Policy Study\n  players=%d  sims/scenario=%d  max_turns=%d  workers=%d\n  scenarios: %s\n  output: %s\n\n",
                opt$players, opt$sims, opt$max_turns, opt$workers,
                paste(scenarios, collapse=", "), opt$out))
  }

  t0 <- Sys.time()
  res <- run_study(n_players = opt$players, n_sims = opt$sims,
                   max_turns = opt$max_turns, workers = opt$workers,
                   out_dir = opt$out, tag = opt$tag, scenarios = scenarios,
                   verbose = !opt$quiet, root = root)
  el <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  if (!opt$quiet) cat(sprintf("\nDone in %.1f min.\n", el))
  invisible(res)
}

main()
