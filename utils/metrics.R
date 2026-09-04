# ============================================================================
# metrics.R — Inequality / concentration / mobility metric primitives
# ----------------------------------------------------------------------------
# Pure functions operating on numeric vectors or data.tables. Kept dependency-
# light (base R + data.table) so they can be called cheaply inside hot loops.
# ============================================================================

library(data.table)

# ---------------------------------------------------------------------------
# Gini coefficient of a wealth vector. Handles zeros and negatives gracefully:
#   - If all values are equal -> 0.
#   - Negative values (possible after debt) are shifted by |min| before ranking
#     so the measure stays in [0,1]; this is the standard "shifted Gini".
#   - Empty / single-element input -> 0.
# ---------------------------------------------------------------------------
gini <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 2) return(0)
  if (all(diff(range(x)) == 0)) return(0)
  if (any(x < 0)) x <- x - min(x)   # shift to non-negative
  if (sum(x) <= 0) return(0)
  x <- sort(x)
  # Ranked formula: G = (2 * sum(i*x_i)) / (n * sum(x)) - (n+1)/n
  idx <- seq_len(n)
  (2 * sum(idx * x)) / (n * sum(x)) - (n + 1) / n
}

# ---------------------------------------------------------------------------
# Herfindahl-Hirschman Index of property ownership concentration.
# `shares` = vector of each player's share of total owned properties (sums to 1).
# Returns sum(shares^2) scaled to [0,1]. With N players uniform -> 1/N.
# If no properties are owned at all, returns 0.
# ---------------------------------------------------------------------------
hhi <- function(shares) {
  shares <- as.numeric(shares)
  shares <- shares[is.finite(shares)]
  s <- sum(shares)
  if (s <= 0) return(0)
  shares <- shares / s
  sum(shares^2)
}

# ---------------------------------------------------------------------------
# Net worth of a single player given their holdings.
#   cash + market value of unimproved properties (purchase price)
#        + improvement value (houses*cost, hotel counted as 5th house cost)
#        - mortgage liabilities (mortgaged props valued at half price, i.e.
#          the outstanding loan)
# Mortgage accounting: when a property is mortgaged the player receives half
# its purchase price in cash and owes that amount back. We model the liability
# as an asset reduction of half-price for each mortgaged property.
# Holdings structure (list per property): pos, group, price, houses (0-5),
# mortgaged (logical).
# ---------------------------------------------------------------------------
player_net_worth <- function(cash, holdings) {
  nw <- cash
  for (h in holdings) {
    base_val <- h$price
    ic <- h$improve_cost
    # Improvements add value only if not mortgaged (can't improve mortgaged prop)
    imp_val <- 0
    if (!isTRUE(h$mortgaged) && !is.na(ic)) {
      hs <- max(0L, min(4L, as.integer(h$houses)))
      if (as.integer(h$houses) >= 5) imp_val <- 4 * ic   # hotel ~ 4 house-costs
      else if (hs > 0) imp_val <- hs * ic
    }
    liab <- if (isTRUE(h$mortgaged)) 0.5 * base_val else 0
    nw <- nw + base_val + imp_val - liab
  }
  nw
}

# Convenience: net worth from a player object (expects $cash, $holdings list).
net_worth_of <- function(player) {
  player_net_worth(player$cash, player$holdings)
}

# ---------------------------------------------------------------------------
# Quartile membership helper. Given a wealth vector and a threshold set,
# returns logical vectors for bottom/top quartile membership. Used for social
# mobility tracking (bottom-quartile -> top-quartile transitions).
# ---------------------------------------------------------------------------
quartile_bounds <- function(x) {
  q <- quantile(as.numeric(x), probs = c(0.25, 0.75), na.rm = TRUE)
  list(q1 = q[1], q3 = q[2])
}

in_bottom_quartile <- function(w, q1) !is.na(q1) && w <= q1
in_top_quartile     <- function(w, q3) !is.na(q3) && w >= q3

# ---------------------------------------------------------------------------
# Summary statistics block used across all aggregate outputs.
# Returns a named numeric vector: mean, median, sd, p05, p95, min, max.
# ---------------------------------------------------------------------------
summary_stats <- function(x) {
  x <- as.numeric(x); x <- x[is.finite(x)]
  if (length(x) == 0) {
    return(setNames(rep(NA_real_, 7),
                    c("mean","median","sd","p05","p95","min","max")))
  }
  qs <- quantile(x, probs = c(0.05, 0.95), names = FALSE, na.rm = TRUE)
  c(mean = mean(x), median = median(x), sd = stats::sd(x),
    p05 = qs[1], p95 = qs[2], min = min(x), max = max(x))
}

# ---------------------------------------------------------------------------
# Rent-burden ratio for a single rent event: rent_paid / tenant_liquid_cash.
# Guarded against zero/negative cash (returns NA if denominator <= 0).
# ---------------------------------------------------------------------------
rent_burden <- function(rent_paid, tenant_cash) {
  if (!(tenant_cash > 0)) return(NA_real_)
  rent_paid / tenant_cash
}

# ---------------------------------------------------------------------------
# Capital formation tally: count houses and hotels separately from a holdings
# list. A hotel (houses>=5) counts as 1 hotel; otherwise houses count.
# ---------------------------------------------------------------------------
capital_tally <- function(all_holdings_list) {
  houses <- 0L; hotels <- 0L
  for (h in all_holdings_list) {
    hh <- as.integer(h$houses)
    if (hh >= 5) hotels <- hotels + 1L
    else houses <- houses + hh
  }
  c(houses = houses, hotels = hotels, total_units = houses + hotels)
}
