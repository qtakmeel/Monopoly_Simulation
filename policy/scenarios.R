# ============================================================================
# scenarios.R — Economic-policy scenario configurations
# ----------------------------------------------------------------------------
# Each scenario is a plain list of named parameters consumed by Engine. A
# single `base_config()` supplies defaults; each scenario overrides only the
# levers it changes, so the five arms differ in exactly the intended ways.
#
# Levers (see game/engine.R header for semantics):
#   ubi_per_turn        $ to every alive player at start of their turn
#   income_tax_rate     fraction of net worth levied on passing GO
#   luxury_tax_cap      cap on Luxury Tax payment (NULL = uncapped $100)
#   income_tax_cap      cap on per-pass income tax (NULL = uncapped)
#   rent_control_max    cap on any single rent payment (NULL = off)
#   filter_money_cards  void money-granting Chance/Chest cards
#   forced_jail_payment $ paid on entering jail (DS uses 50)
#   ds_free_housing     houses cost nothing to build
#   allow_trading       permit group-completing trades
#   mortgage_allowed    permit voluntary mortgages
#   allow_liquidation   permit selling assets to cover debts (FALSE => strict
#                       bankruptcy on insolvency; used so "bankruptcy timing"
#                       is a meaningful metric)
#   ai_buy_ratio        buy if cash > ratio * price
#   ai_build_evenly     even-build rule on complete groups
#   max_turns           hard stop (default 200)
#
# Player-count scaling: redistributive amounts scale with n_players so the
# per-capita fiscal load stays comparable across 2/4/6/8-player games.
# ============================================================================

base_config <- function(n_players = 4L, max_turns = 200L) {
  list(
    name = "baseline",
    # Fiscal levers (off by default)
    ubi_per_turn       = 0,
    income_tax_rate    = 0,
    luxury_tax_cap     = NULL,
    income_tax_cap     = NULL,
    rent_control_max   = NULL,
    filter_money_cards = FALSE,
    forced_jail_payment= NULL,
    ds_free_housing    = FALSE,
    # Behavioural / market levers
    allow_trading      = TRUE,
    mortgage_allowed   = TRUE,
    allow_liquidation  = FALSE,
    ai_buy_ratio       = 1.5,
    ai_build_evenly    = TRUE,
    # Structure
    n_players          = as.integer(n_players),
    max_turns          = as.integer(max_turns)
  )
}

scenario_configs <- function(n_players = 4L, max_turns = 200L) {
  bp <- as.integer(n_players)
  b  <- base_config(bp, max_turns)

  # --- Baseline: standard Monopoly rules, no policy intervention -------------
  baseline <- b
  baseline$name <- "Baseline"

  # --- Extreme Capitalism: maximal deregulation & wealth concentration --------
  # No safety nets, no redistribution, money cards voided (no windfalls),
  # aggressive buying, trading allowed, higher effective inequality pressure.
  ec <- b
  ec$name               <- "Extreme_Capitalism"
  ec$filter_money_cards <- TRUE     # eliminate random wealth transfers
  ec$ai_buy_ratio       <- 1.2      # more aggressive acquisition
  ec$allow_liquidation  <- FALSE    # harsh: insolvency = immediate exit
  ec$mortgage_allowed   <- TRUE

  # --- Democratic Socialism: strong redistribution & public goods ------------
  # UBI + progressive income tax + free housing + capped taxes + soft jail.
  ds <- b
  ds$name                <- "Democratic_Socialism"
  ds$ubi_per_turn        = round(50 * (bp / 4))        # scales with players
  ds$income_tax_rate     = 0.05                        # 5% of net worth on GO
  ds$income_tax_cap      = 200                         # bounded levy
  ds$luxury_tax_cap      = 25                          # compress top-end tax
  ds$ds_free_housing     = TRUE                        # public-good housing
  ds$forced_jail_payment = 50                          # soft jail penalty
  ds$rent_control_max    = 75                          # also cap rents
  ds$allow_liquidation   = FALSE

  # --- Rent Control Only: sole lever is a cap on rent payments ---------------
  rc <- b
  rc$name             <- "Rent_Control_Only"
  rc$rent_control_max = 50                             # hard cap per rent event

  # --- UBI Only: sole lever is an unconditional basic income -----------------
  ubi <- b
  ubi$name         <- "UBI_Only"
  ubi$ubi_per_turn = round(50 * (bp / 4))              # scales with players

  list(Baseline = baseline,
       Extreme_Capitalism = ec,
       Democratic_Socialism = ds,
       Rent_Control_Only = rc,
       UBI_Only = ubi)
}

# Convenience: fetch one scenario config by key.
get_scenario <- function(key, n_players = 4L, max_turns = 200L) {
  cfgs <- scenario_configs(n_players, max_turns)
  if (!key %in% names(cfgs)) stop("Unknown scenario: ", key, call. = FALSE)
  cfgs[[key]]
}

SCENARIO_KEYS <- c("Baseline", "Extreme_Capitalism", "Democratic_Socialism",
                   "Rent_Control_Only", "UBI_Only")
