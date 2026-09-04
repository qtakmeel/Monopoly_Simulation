# ============================================================================
# bank.R — Bank / central ledger (R6)
# ----------------------------------------------------------------------------
# The bank is the source of truth for property ownership and the two card
# decks. It mediates all money transfers so the engine can observe them for
# policy hooks (taxation, UBI redistribution, rent-control caps). Deck draws
# reshuffle when exhausted (standard Monopoly behaviour).
# ============================================================================

library(R6)

Bank <- R6Class("Bank",
  public = list(
    chance_deck   = NULL,
    chest_deck    = NULL,
    owner         = NULL,      # named vector: pos -> player id (0 = unowned)
    initialized   = FALSE,

    initialize = function() {
      self$chance_deck <- CHANCE_DECK
      self$chest_deck  <- CHEST_DECK
      self$owner       <- setNames(integer(nrow(BOARD_LAYOUT)), as.character(BOARD_LAYOUT$pos))
      names(self$owner) <- as.character(BOARD_LAYOUT$pos)
      self$initialized <- TRUE
    },

    # --- Ownership -----------------------------------------------------------
    owner_of = function(pos) {
      o <- self$owner[[as.character(pos)]]
      if (is.null(o) || o == 0L) NA_integer_ else as.integer(o)
    },
    set_owner = function(pos, pid) {
      self$owner[[as.character(pos)]] <<- as.integer(pid)
    },
    owned_positions = function(pid) {
      ps <- which(as.integer(self$owner) == as.integer(pid))
      BOARD_LAYOUT$pos[ps]
    },
    unowned_purchasable = function() {
      idx <- BOARD_LAYOUT$type %in% c(TYPE_PROPERTY, TYPE_RAILROAD, TYPE_UTIL) &
             as.integer(self$owner) == 0L
      BOARD_LAYOUT[idx, ]
    },

    # --- Card decks ----------------------------------------------------------
    draw_chance = function() self$draw_card("chance"),
    draw_chest  = function() self$draw_card("chest"),

    draw_card = function(slot) {
      deck <- if (slot == "chance") self$chance_deck else self$chest_deck
      card <- deck[[1]]
      remaining <- deck[-1]
      if (length(remaining) == 0) remaining <- if (slot == "chance") CHANCE_DECK else CHEST_DECK
      if (slot == "chance") self$chance_deck <<- remaining else self$chest_deck <<- remaining
      card
    }
  )
)
