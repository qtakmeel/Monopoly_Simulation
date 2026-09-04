# ============================================================================
# player.R — Player (R6)
# ----------------------------------------------------------------------------
# A player holds cash, a position on the board, jail state, get-out-of-jail
# cards, and a holdings list. Holdings is a list of property records:
#   list(pos, name, type, group, price, base_rent, full_rents, improve_cost,
#        houses (0-5), mortgaged (logical))
# All monetary mutation goes through add_cash()/pay() so the engine can hook
# policy effects (e.g. UBI top-ups, taxation) at well-defined points.
# ============================================================================

library(R6)

Player <- R6Class("Player",
  public = list(
    id        = NULL,
    name      = NULL,
    color     = NULL,
    cash      = 1500L,
    pos       = 1L,          # GO
    in_jail   = FALSE,
    jail_turns= 0L,          # consecutive turns spent in jail
    got_out   = 0L,          # number of "Get Out of Jail Free" cards held
    bankrupt  = FALSE,
    eliminated_at_turn = NA_integer_,
    holdings  = list(),      # list of property records
    turn_count= 0L,

    initialize = function(id, name = NULL, color = NULL) {
      self$id <- id
      self$name <- if (is.null(name)) paste0("P", id) else name
      self$color <- if (is.null(color)) paste0("c", id) else color
    },

    # --- Cash ----------------------------------------------------------------
    add_cash = function(amount) {
      self$cash <- self$cash + amount
      invisible(self$cash)
    },
    pay = function(amount) {            # returns TRUE if affordable & paid
      if (amount <= 0) return(TRUE)
      if (self$cash < amount) return(FALSE)
      self$cash <- self$cash - amount
      TRUE
    },
    can_afford = function(amount) self$cash >= amount,

    # --- Movement ------------------------------------------------------------
    move = function(steps) {
      old_pos <- self$pos
      crossed_go <- FALSE
      new_pos <- ((self$pos - 1 + steps) %% 40) + 1
      if (new_pos < self$pos || (steps > 0 && self$pos + steps > 40)) crossed_go <- TRUE
      self$pos <- new_pos
      list(old = old_pos, new = new_pos, crossed_go = crossed_go)
    },
    teleport = function(new_pos) {
      old <- self$pos; self$pos <- new_pos; old
    },

    # --- Jail ---------------------------------------------------------------
    enter_jail = function() { self$in_jail <- TRUE; self$jail_turns <- 0L },
    leave_jail = function() { self$in_jail <- FALSE; self$jail_turns <- 0L },
    tick_jail  = function() { self$jail_turns <- self$jail_turns + 1L },

    # --- Holdings ------------------------------------------------------------
    owns_property = function(pos) any(vapply(self$holdings, function(h) h$pos == pos, logical(1))),
    properties_of_group = function(group) {
      vapply(self$holdings, function(h) identical(h$group, group), logical(1))
    },
    has_complete_group = function(group) {
      need <- length(GROUP_POSITIONS[[group]])
      sum(self$properties_of_group(group)) == need
    },
    holdings_pos   = function() as.integer(vapply(self$holdings, function(h) h$pos, numeric(1))),
    num_properties = function() length(self$holdings),
    housing_units  = function() sum(vapply(self$holdings, function(h) max(0L, min(4L, as.integer(h$houses))), integer(1)), use.names = FALSE),
    hotel_count    = function() sum(vapply(self$holdings, function(h) as.integer(h$houses) >= 5, integer(1)), use.names = FALSE),

    add_holding = function(rec) { self$holdings[[length(self$holdings)+1]] <<- rec; invisible(rec) },
    remove_holding = function(pos) {
      idx <- which(vapply(self$holdings, function(h) h$pos == pos, logical(1)))
      if (length(idx) == 0) return(invisible(NULL))
      rec <- self$holdings[[idx[1]]]
      self$holdings[idx[1]] <<- NULL
      invisible(rec)
    },
    holding_by_pos = function(pos) {
      idx <- which(vapply(self$holdings, function(h) h$pos == pos, logical(1)))
      if (length(idx) == 0) NULL else self$holdings[[idx[1]]]
    },

    # House bookkeeping (engine enforces equal-building rules before calling).
    set_houses = function(pos, n) {
      h <- self$holding_by_pos(pos); if (is.null(h)) return(FALSE)
      h$houses <- as.integer(n); TRUE
    },
    total_improvement_value = function() {
      s <- 0
      for (h in self$holdings) if (!isTRUE(h$mortgaged)) {
        ic <- h$improve_cost; if (is.na(ic)) next
        hs <- max(0L, min(4L, as.integer(h$houses)))
        s <- s + hs * ic
      }
      s
    },

    mortgage_status = function(pos) {
      h <- self$holding_by_pos(pos); if (is.null(h)) NA else isTRUE(h$mortgaged)
    },

    # --- Elimination ---------------------------------------------------------
    eliminate = function(turn) {
      self$bankrupt <- TRUE
      self$eliminated_at_turn <- turn
    },
    alive = function() !self$bankrupt,

    # --- Valuation -----------------------------------------------------------
    compute_net_worth = function() {
      nw <- self$cash
      for (h in self$holdings) {
        imp <- 0
        ic <- h$improve_cost
        if (!isTRUE(h$mortgaged) && !is.na(ic)) {
          hs <- max(0L, min(4L, as.integer(h$houses)))
          imp <- if (as.integer(h$houses) >= 5) 4 * ic else hs * ic
        }
        liab <- if (isTRUE(h$mortgaged)) 0.5 * h$price else 0
        nw <- nw + h$price + imp - liab
      }
      nw
    }
  )
)
