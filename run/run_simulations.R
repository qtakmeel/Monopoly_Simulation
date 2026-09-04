# ============================================================================
# run_simulations.R — Parallel Monte Carlo driver + aggregation + outputs
# ----------------------------------------------------------------------------
# Runs N games per scenario (5 arms) for a given player count. Parallelism uses
# base R `parallel::makeCluster` (PSOCK sockets — portable across Windows/macOS/
# Linux), falling back to sequential lapply when workers <= 1. Each worker gets
# a full copy of the project modules via clusterExport so Engine/R6 classes are
# available in the child sessions. For each game we extract the six study
# metrics; aggregate across games into tidy data.tables; and write CSVs + a
# summary markdown to results/.
#
# Metrics captured per game:
#   gini_final          Gini of final net worth across all players
#   hhi_final           HHI of property-ownership shares at end
#   n_bankruptencies    number of bankruptcies in the game
#   first_bankruptcy_turn turn of first bankruptcy (NA if none)
#   social_mobility     bottom->top quartile wealth transitions observed
#   capital_formation   total houses+hotels built over the whole game
# Plus descriptive stats: game length, winner identity, final wealth spread.
# ============================================================================

suppressMessages(library(data.table))
library(parallel)

# ---- Load project modules ---------------------------------------------------
load_project <- function(root = ".") {
  source(file.path(root, "data", "board.R"))
  source(file.path(root, "utils", "metrics.R"))
  source(file.path(root, "game", "player.R"))
  source(file.path(root, "game", "bank.R"))
  source(file.path(root, "game", "engine.R"))
  source(file.path(root, "policy", "scenarios.R"))
}

# ---- Per-game metric extraction --------------------------------------------
# Plays one game and returns a single-row list of metrics.
play_one_game <- function(cfg, seed) {
  eng <- Engine$new(cfg, n_players = cfg$n_players, seed = as.integer(seed))
  res <- eng$run()
  ev  <- eng$log_events

  # Final wealth vector (all players, incl. eliminated at 0).
  wealth <- vapply(eng$players, function(p) p$compute_net_worth(), numeric(1))
  gini_f <- gini(wealth)

  # Property ownership shares -> HHI.
  total_props <- sum(vapply(eng$players, function(p) p$num_properties(), integer(1)))
  shares <- vapply(eng$players, function(p) p$num_properties(), numeric(1))
  hhi_f  <- if (total_props > 0) hhi(shares) else 0

  bk_ev <- ev[ev$event == "bankrupt"]
  n_bk  <- nrow(bk_ev)
  first_bk_turn <- if (n_bk > 0) min(bk_ev$turn) else NA_integer_

  # Social mobility: track quartile membership of net worth over turns. We
  # approximate by sampling wealth at each bankruptcy/turn boundary is costly,
  # so instead we use the recorded event stream to detect a player moving from
  # <=Q1 to >=Q3 of that turn's wealth distribution. Lightweight proxy: count
  # distinct players whose final rank jumped from bottom half to top half
  # relative to initial (turn-1) standing. Computed below via sampled snapshots.
  mobility <- compute_social_mobility(eng)

  # Capital formation: cumulative houses/hotels ever built (build events).
  build_ev <- ev[ev$event == "build"]
  cap_form <- nrow(build_ev)   # number of house-placement actions

  list(
    seed              = as.integer(seed),
    scenario          = cfg$name,
    n_players         = cfg$n_players,
    game_length       = as.integer(res$turn),
    terminated_by_cap = (res$turn >= cfg$max_turns),
    n_winners         = length(res$winners),
    winner_ids        = paste(res$winners, collapse = ","),
    gini_final        = gini_f,
    hhi_final         = hhi_f,
    n_bankruptcies    = n_bk,
    first_bankruptcy_turn = first_bk_turn,
    social_mobility   = mobility,
    capital_formation = cap_form,
    wealth_min        = min(wealth),
    wealth_max        = max(wealth),
    wealth_mean       = mean(wealth),
    wealth_sd         = if (length(wealth) > 1) stats::sd(wealth) else 0,
    rent_burden_mean  = mean_rent_burden(ev)
  )
}

# Longitudinal social mobility: using the engine's periodic wealth snapshots,
# classify each player's position at each snapshot into {bottom-half, top-half}
# relative to that snapshot's cross-sectional median. A "mobility transition"
# is counted each time a player flips halves between two consecutive snapshots
# in which they appear. Summing over all players yields a game-level mobility
# score (higher = more fluid wealth ranking; lower = entrenched hierarchy).
compute_social_mobility <- function(eng) {
  wh <- eng$wealth_history
  if (is.null(wh) || nrow(wh) < 4) return(0L)
  # Determine each player's half at every snapshot turn.
  half <- function(w) ifelse(w >= stats::median(w), 1L, 0L)   # 1=top, 0=bottom
  transitions <- 0L
  turns <- sort(unique(wh$turn))
  prev_half <- NULL
  for (t in turns) {
    sub <- wh[wh$turn == t]
    h <- half(sub$net_worth)
    names(h) <- sub$player
    if (!is.null(prev_half)) {
      common <- intersect(names(h), names(prev_half))
      if (length(common) > 0) {
        transitions <- transitions + sum(abs(unname(h[common]) - unname(prev_half[common])))
      }
    }
    prev_half <- h
  }
  as.integer(transitions)
}

mean_rent_burden <- function(ev) {
  r <- ev[ev$event == "rent"]
  if (nrow(r) == 0) return(NA_real_)
  # Approximate tenant cash-at-event is unavailable post-hoc; use rent magnitude
  # relative to a $1500 baseline as a burden proxy (documented).
  mean(r$amount / 1500)
}

# ---- Aggregation -------------------------------------------------------------
aggregate_games <- function(game_dt) {
  game_dt[, .(
    gini_mean        = mean(gini_final),
    gini_median      = median(gini_final),
    gini_sd          = sd(gini_final),
    hhi_mean         = mean(hhi_final),
    hhi_median       = median(hhi_final),
    avg_bankruptcies = mean(n_bankruptcies),
    pct_with_bankruptcy = 100 * mean(n_bankruptcies > 0),
    avg_first_bk_turn  = mean(first_bankruptcy_turn, na.rm = TRUE),
    avg_mobility     = mean(social_mobility),
    avg_capital      = mean(capital_formation),
    avg_game_length  = mean(game_length),
    pct_reached_cap  = 100 * mean(terminated_by_cap),
    avg_wealth_gap   = mean(wealth_max - wealth_min),
    avg_rent_burden  = mean(rent_burden_mean, na.rm = TRUE),
    n_games          = .N
  ), by = .(scenario, n_players)]
}

# ---- Parallel driver ---------------------------------------------------------
# Build a PSOCK cluster once and reuse it across all scenarios to avoid the
# overhead of spawning/stopping worker processes per scenario. Workers source
# the full project from `root` so Engine/R6/data.tables are available in child
# sessions. The cluster is created lazily and stopped via on.exit in run_study.
.make_cluster <- function(workers, root) {
  cl <- parallel::makeCluster(workers)
  # Each worker sources the full project so Engine/R6/data.tables are present.
  parLapply(cl, seq_len(workers), function(i) {
    suppressMessages(library(data.table))
    source(file.path(root, "data", "board.R"))
    source(file.path(root, "utils", "metrics.R"))
    source(file.path(root, "game", "player.R"))
    source(file.path(root, "game", "bank.R"))
    source(file.path(root, "game", "engine.R"))
    invisible(NULL)
  })
  # Export the three closures defined in THIS file (not auto-sourced into workers).
  clusterExport(cl, varlist = c("play_one_game", "compute_social_mobility",
                                 "mean_rent_burden"),
                envir = environment())
  cl
}

run_scenario <- function(cfg, n_sims, cl = NULL, verbose = TRUE) {
  seeds <- seq_len(n_sims) + sample.int(1e6, 1)   # stable-ish unique offsets
  t0 <- Sys.time()
  if (!is.null(cl)) {
    rows <- parallel::parLapply(cl, seeds, function(sd) play_one_game(cfg, sd))
  } else {
    rows <- lapply(seeds, function(sd) play_one_game(cfg, sd))
  }
  dt <- rbindlist(rows)   # expand list-of-named-lists into one col per field
  if (verbose) {
    el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    message(sprintf("[%s] %d sims in %.1fs (%.1f sims/s)",
                    cfg$name, n_sims, el, n_sims / max(el, 0.01)))
  }
  dt
}

run_all_scenarios <- function(n_players = 4L, n_sims = 100L,
                              max_turns = 200L, cl = NULL,
                              scenarios = SCENARIO_KEYS, verbose = TRUE) {
  cfgs <- scenario_configs(n_players, max_turns)
  out <- lapply(scenarios, function(k) {
    if (verbose) message(">> Running ", k, " (", n_sims, " sims, ", n_players, "p)")
    run_scenario(cfgs[[k]], n_sims, cl = cl, verbose = verbose)
  })
  names(out) <- scenarios
  do.call(rbind, out)
}

# ---- Output writers ------------------------------------------------------------
write_outputs <- function(game_dt, agg_dt, out_dir = "results", tag = "") {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  slug  <- if (nzchar(tag)) paste0("_", tag) else ""
  f_game <- file.path(out_dir, sprintf("games%s_%s.csv", slug, stamp))
  f_agg  <- file.path(out_dir, sprintf("summary%s_%s.csv", slug, stamp))
  f_md   <- file.path(out_dir, sprintf("summary%s_%s.md", slug, stamp))
  fwrite(game_dt, f_game)
  fwrite(agg_dt, f_agg)
  write_markdown_summary(agg_dt, f_md)
  list(games_csv = f_game, summary_csv = f_agg, summary_md = f_md)
}

write_markdown_summary <- function(agg_dt, path) {
  lines <- c(
    "# Monopoly Policy Simulation — Aggregate Results",
    "",
    sprintf("_Generated: %s_", format(Sys.time())),
    "",
    "| Scenario | Players | Games | Gini (mean±sd) | HHI (mean) | Avg Bankr. | % w/ Bankr. | First BK Turn | Mobility | Capital | Game Len | Reached Cap | Wealth Gap | Rent Burden |",
    "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"
  )
  for (i in seq_len(nrow(agg_dt))) {
    r <- agg_dt[i, ]
    lines <- c(lines, sprintf(
      "| %s | %d | %d | %.3f ± %.3f | %.3f | %.2f | %.0f%% | %s | %.2f | %.1f | %.0f | %.0f%% | %.0f | %.3f |",
      r$scenario, r$n_players, r$n_games,
      r$gini_mean, r$gini_sd, r$hhi_mean,
      r$avg_bankruptcies, r$pct_with_bankruptcy,
      ifelse(is.na(r$avg_first_bk_turn), "—", round(r$avg_first_bk_turn, 1)),
      r$avg_mobility, r$avg_capital, r$avg_game_length,
      r$pct_reached_cap, r$avg_wealth_gap, r$avg_rent_burden
    ))
  }
  writeLines(lines, path)
}

# ---- Top-level convenience ----------------------------------------------------
run_study <- function(n_players = 4L, n_sims = 100L, max_turns = 200L,
                      workers = NULL, out_dir = "results", tag = "",
                      scenarios = SCENARIO_KEYS, verbose = TRUE, root = ".") {
  load_project(root)
  root_abs <- normalizePath(root, mustWork = FALSE)

  cl <- NULL
  use_par <- !is.null(workers) && workers > 1
  if (use_par) {
    if (verbose) message(sprintf("Spawning %d-worker PSOCK cluster...", workers))
    cl <- .make_cluster(workers, root_abs)
    on.exit(stopCluster(cl), add = TRUE)
  }

  game_dt <- run_all_scenarios(n_players, n_sims, max_turns, cl = cl,
                               scenarios = scenarios, verbose = verbose)
  agg_dt  <- aggregate_games(game_dt)
  files   <- write_outputs(game_dt, agg_dt, out_dir, tag)
  if (verbose) {
    cat("\n=== AGGREGATE SUMMARY ===\n")
    print(agg_dt[, .(scenario, n_games, gini_mean, hhi_mean,
                     avg_bankruptcies, avg_game_length)])
    cat("\nWrote:\n"); for (f in files) cat("  ", f, "\n")
  }
  invisible(list(games = game_dt, aggregate = agg_dt, files = files))
}
