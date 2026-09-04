# ============================================================================
# engine.R — Monopoly game engine (R6)
# ----------------------------------------------------------------------------
# Drives a single full game to termination under a given scenario config.
# The scenario object (see policy/scenarios.R) exposes flags that gate each
# policy lever; the engine consults them at the relevant decision points so a
# single code path serves all five scenarios.
#
# Scenario-config fields consumed by the engine:
#   name                       : string label
#   ubi_per_turn               : $ granted to every alive player each turn
#   income_tax_rate            : fraction of net worth taxed per GO pass (0 = off)
#   luxury_tax_cap             : max luxury-tax payment (NULL = uncapped)
#   income_tax_cap             : max income-tax payment (NULL = uncapped)
#   rent_control_max           : cap on any single rent payment (NULL = off)
#   filter_money_cards         : TRUE -> money-granting Chance/Chest voided
#   forced_jail_payment        : $ paid on entering jail (DS uses 50)
#   ds_free_housing            : TRUE -> houses are free (no build cost)
#   allow_trading              : FALSE -> no trade offers accepted
#   mortgage_allowed           : FALSE -> no voluntary mortgages
#   ai_buy_ratio               : buy if cash > ratio * price (default 1.5)
#   ai_build_evenly            : TRUE -> even-build rule on complete groups
#   max_turns                  : hard stop (default 200)
#   seed                       : RNG seed for reproducibility
# ============================================================================

library(R6)
library(data.table)

Engine <- R6Class("Engine",
  public = list(
    cfg       = NULL,
    players   = NULL,     # named list of Player objects
    bank      = NULL,
    turn      = 0L,
    current   = 1L,
    log_events= data.table(),
    wealth_history = data.table(),   # periodic net-worth snapshots (mobility)
    snapshot_every = 10L,            # sample cadence (turns)
    rng_state = NULL,

    initialize = function(cfg, n_players, seed = NULL) {
      self$cfg <- cfg
      if (!is.null(seed)) set.seed(seed)
      colors <- c("red","blue","green","yellow","orange","pink","white","black")
      self$players <- vector("list", n_players)
      for (i in seq_len(n_players)) {
        self$players[[i]] <<- Player$new(i, paste0("P", i), colors[i])
      }
      self$bank <- Bank$new()
      self$log_events <- data.table(event = character(), turn = integer(),
                                    player = integer(), amount = numeric())
      # Periodic wealth snapshots for longitudinal social-mobility measurement.
      self$wealth_history <- data.table(turn = integer(), player = integer(),
                                        net_worth = numeric())
      self$snapshot_every <- 10L   # sample every N turns (cheap, low-overhead)
    },

    # ---- Public entry point -------------------------------------------------
    run = function() {
      alive_n <- n_players_alive(self)
      while (alive_n > 1 && self$turn < self$cfg$max_turns) {
        self$turn <- self$turn + 1L
        self$current <- next_alive_player(self, self$current)
        p <- self$players[[self$current]]
        self$play_turn(p)
        alive_n <- n_players_alive(self)
        # Cheap periodic wealth snapshot for social-mobility tracking.
        if (self$turn %% self$snapshot_every == 0L) self$snapshot_wealth()
      }
      # Final snapshot so the end-state is always captured.
      self$snapshot_wealth()
      self$result_summary()
    },

    snapshot_wealth = function() {
      rows <- lapply(self$players, function(pp) {
        data.table(turn = self$turn, player = pp$id,
                   net_worth = pp$compute_net_worth())
      })
      self$wealth_history <- rbind(self$wealth_history, do.call(rbind, rows))
    },

    result_summary = function() {
      survivors <- which(vapply(self$players, function(p) p$alive(), logical(1)))
      winners <- if (length(survivors) >= 1) survivors else integer(0)
      wealth <- vapply(self$players, function(p) p$compute_net_worth(), numeric(1))
      list(turn = self$turn, winners = winners,
           final_wealth = setNames(wealth, sapply(self$players, `[[`, "id")),
           events = self$log_events)
    },

    # ---- One turn ------------------------------------------------------------
    play_turn = function(p) {
      # UBI grant (policy): paid to the actor at the start of their turn.
      if (self$cfg$ubi_per_turn > 0) {
        p$add_cash(self$cfg$ubi_per_turn)
        self$log_event("ubi", p$id, self$cfg$ubi_per_turn)
      }

      if (p$in_jail) { self$resolve_jail(p); return(invisible(NULL)) }

      # Roll up to three times; doubles let you roll again, three strikes -> jail.
      consecutive_doubles <- 0L
      while (TRUE) {
        die <- sample(1:6, 2, replace = TRUE)
        is_double <- die[1] == die[2]
        moved <- p$move(sum(die))
        if (moved$crossed_go) {
          p$add_cash(200); self$log_event("go_bonus", p$id, 200)
          self$income_tax_on_go(p)
        }
        self$handle_space(p)
        if (!is_double) break
        consecutive_doubles <- consecutive_doubles + 1L
        if (consecutive_doubles >= 3L) {
          p$enter_jail(); self$log_event("three_doubles_jail", p$id, 0)
          break
        }
        if (p$in_jail) break   # sent to jail by a card/space this turn
      }

      # Deterministic AI post-move actions (build / mortgage / trade).
      if (p$alive()) self$do_ai_actions(p)
    },

    roll_dice_once = function() sum(sample(1:6, 2, replace = TRUE)),

    # ---- Jail resolution (policy priority order) ----------------------------
    resolve_jail = function(p) {
      # Priority: 1) Get-out card  2) pay fine  3) forced payment (DS)  4) roll doubles
      if (p$got_out > 0) {
        p$got_out <- p$got_out - 1L; p$leave_jail(); self$log_event("jail_card", p$id, 0)
        return(invisible(NULL))
      }
      fine <- 50
      if (p$can_afford(fine)) {
        p$pay(fine); p$leave_jail(); self$log_event("jail_fine", p$id, fine)
        return(invisible(NULL))
      }
      fp <- self$cfg$forced_jail_payment
      if (!is.null(fp) && p$can_afford(fp)) {
        p$pay(fp); p$leave_jail(); self$log_event("jail_forced", p$id, fp)
        return(invisible(NULL))
      }
      # Roll for doubles
      r <- self$roll_dice_once()
      if (r %in% c(2,4,6,8,10,12)) {
        p$leave_jail(); p$move(r)
        self$handle_space(p)
      } else {
        p$tick_jail()
        if (p$jail_turns >= 3) {
          owed <- min(50, p$cash)
          p$pay(owed); p$leave_jail(); self$log_event("jail_timeout", p$id, owed)
        }
      }
    },

    # ---- Space handling ------------------------------------------------------
    handle_space = function(p) {
      sq <- BOARD_LAYOUT[BOARD_LAYOUT$pos == p$pos, ]
      t <- sq$type
      if (t == TYPE_GO) {
        # passing already handled; landing exactly on GO pays nothing extra
      } else if (t == TYPE_PROPERTY || t == TYPE_RAILROAD || t == TYPE_UTIL) {
        self$on_property(p, sq)
      } else if (t == TYPE_TAX) {
        amt <- self$tax_amount(sq)
        if (amt > 0) {
          paid <- self$settle_debt(p, amt, "tax")   # bank is creditor (NULL)
          self$log_event("tax", p$id, paid)
        }
      } else if (t == TYPE_CHANCE) {
        self$apply_card(p, self$bank$draw_chance())
      } else if (t == TYPE_CHEST) {
        self$apply_card(p, self$bank$draw_chest())
      } else if (t == TYPE_GOTO) {
        p$enter_jail(); self$log_event("goto_jail", p$id, 0)
      } else if (t == TYPE_JAIL) {
        # just visiting
      } else if (t == TYPE_PARKING) {
        # house rule: no jackpot (official rules)
      }
    },

    tax_amount = function(sq) {
      base <- sq$tax
      if (sq$name == "Luxury Tax" && !is.null(self$cfg$luxury_tax_cap)) {
        base <- min(base, self$cfg$luxury_tax_cap)
      }
      base
    },

    income_tax_on_go = function(p) {
      rate <- self$cfg$income_tax_rate
      if (rate <= 0) return(invisible(NULL))
      nw <- p$compute_net_worth()
      amt <- round(rate * nw)
      if (!is.null(self$cfg$income_tax_cap)) amt <- min(amt, self$cfg$income_tax_cap)
      amt <- max(0, min(amt, p$cash))
      if (amt > 0) { p$pay(amt); self$log_event("income_tax", p$id, amt) }
    },

    # ---- Property / rent -----------------------------------------------------
    on_property = function(p, sq) {
      owner_id <- self$bank$owner_of(sq$pos)
      # Unowned: deterministic AI decides whether to buy.
      if (is.na(owner_id)) {
        if (p$can_afford(sq$price) && p$cash > self$cfg$ai_buy_ratio * sq$price) {
          p$pay(sq$price)
          self$bank$set_owner(sq$pos, p$id)
          rec <- make_holding(sq)
          p$add_holding(rec)
          self$log_event("buy", p$id, sq$price)
        } else {
          self$auction(p, sq)
        }
        return(invisible(NULL))
      }
      # Owned by someone else: pay rent (with debt settlement / bankruptcy).
      if (owner_id != p$id) {
        owner <- self$players[[owner_id]]
        rent <- self$calc_rent(p, owner, sq)
        if (rent > 0) {
          paid <- self$settle_debt(p, rent, "rent", creditor = owner)
          if (!p$alive()) return(invisible(NULL))   # bankrupt mid-settlement
          owner$add_cash(paid)
          self$log_event("rent", p$id, paid)
        }
      }
    },

    # ---- Debt settlement & bankruptcy ---------------------------------------
    # Attempt to make `payer` pay `amount` to settle an obligation. Pays from
    # cash first; if short, sells improvements then properties (highest value
    # first) until the bill is covered or assets are exhausted. If still short,
    # the payer goes bankrupt: remaining assets transfer to `creditor` (or the
    # bank if NULL), all cash is forfeited, and the player is eliminated.
    settle_debt = function(payer, amount, kind, creditor = NULL) {
      need <- amount
      if (need <= 0) return(0)
      # 1) Cash
      take_cash <- min(payer$cash, need)
      payer$pay(take_cash); need <- need - take_cash
      if (need <= 0) return(amount)
      # Liquidation is optional (cfg$allow_liquidation). When disabled, a player
      # who cannot pay from cash goes straight to bankruptcy -- this is what makes
      # "bankruptcy timing" a meaningful metric in the policy scenarios.
      if (isTRUE(self$cfg$allow_liquidation)) {
        # 2) Sell improvements (recover half of improvement cost per house sold)
        while (need > 0) {
          best <- self$highest_improvement(payer)
          if (is.null(best)) break
          recover <- 0.5 * best$improve_cost
          payer$set_houses(best$pos, as.integer(best$houses) - 1L)
          payer$add_cash(recover); need <- need - recover
          self$log_event("sell_house", payer$id, recover)
        }
        # 3) Sell properties (recover full price)
        while (need > 0) {
          best <- self$highest_property(payer)
          if (is.null(best)) break
          payer$remove_holding(best$pos)
          self$bank$set_owner(best$pos, 0L)
          payer$add_cash(best$price); need <- need - best$price
          self$log_event("sell_prop", payer$id, best$price)
        }
      }
      # 4) Still short -> bankruptcy: creditor collects whatever remains.
      if (need > 0) {
        self$declare_bankruptcy(payer, creditor)
        return(amount - need)   # shortfall is unrecoverable
      }
      amount
    },

    highest_improvement = function(p) {
      cands <- Filter(function(h) !isTRUE(h$mortgaged) && as.integer(h$houses) > 0 && !is.na(h$improve_cost), p$holdings)
      if (length(cands) == 0) return(NULL)
      ord <- order(vapply(cands, function(h) h$improve_cost, numeric(1)), decreasing = TRUE)
      cands[[ord[1]]]
    },

    highest_property = function(p) {
      cands <- Filter(function(h) !isTRUE(h$mortgaged), p$holdings)
      if (length(cands) == 0) return(NULL)
      ord <- order(vapply(cands, function(h) h$price, numeric(1)), decreasing = TRUE)
      cands[[ord[1]]]
    },

    declare_bankruptcy = function(payer, creditor) {
      # Transfer all remaining holdings + cash to creditor (or discard to bank).
      for (h in payer$holdings) {
        self$bank$set_owner(h$pos, if (!is.null(creditor)) creditor$id else 0L)
        if (!is.null(creditor)) creditor$add_holding(h)
      }
      if (!is.null(creditor)) creditor$add_cash(payer$cash)
      payer$holdings <- list(); payer$cash <- 0
      payer$eliminate(self$turn)
      self$log_event("bankrupt", payer$id, 0)
    },

    calc_rent = function(tenant, landlord, sq) {
      rent <- 0
      if (sq$type == TYPE_PROPERTY) {
        h <- landlord$holding_by_pos(sq$pos)
        hs <- if (!is.null(h) && !isTRUE(h$mortgaged)) as.integer(h$houses) else 0L
        sched <- as.numeric(sq$full_rents[[1]])
        rent <- sched[hs + 1L]
      } else if (sq$type == TYPE_RAILROAD) {
        n_rr <- length(intersect(landlord$holdings_pos(), railroad_positions()))
        rent <- c(25, 50, 100, 200)[min(max(n_rr,1), 4)]
      } else if (sq$type == TYPE_UTIL) {
        n_util <- length(intersect(landlord$holdings_pos(), utility_positions()))
        last_roll <- 7L
        rent <- if (n_util >= 2) 10 * last_roll else 4 * last_roll
      }
      # Rent control cap (policy)
      if (!is.null(self$cfg$rent_control_max)) rent <- min(rent, self$cfg$rent_control_max)
      rent
    },

    auction = function(actor, sq) {
      # Simplified deterministic auction: highest bidder among alive players who
      # can afford wins; ties broken by lowest id. If nobody bids, stays unowned.
      bidders <- which(vapply(self$players, function(q) q$alive() && q$can_afford(sq$price), logical(1)))
      if (length(bidders) == 0) return(invisible(NULL))
      winner <- min(bidders)
      w <- self$players[[winner]]
      w$pay(sq$price); self$bank$set_owner(sq$pos, w$id)
      w$add_holding(make_holding(sq)); self$log_event("auction", w$id, sq$price)
    },

    # ---- Cards ---------------------------------------------------------------
    apply_card = function(p, card) {
      e <- card$effect
      # Policy: void money-granting cards in Extreme Capitalism.
      if (isTRUE(self$cfg$filter_money_cards) && CARD_GRANTS_MONEY(card)) {
        self$log_event("card_voided", p$id, 0); return(invisible(NULL))
      }
      switch(e,
        money = { amt <- card$amt; p$add_cash(amt); self$log_event("card_money", p$id, amt) },
        inherit = { p$add_cash(card$amt); self$log_event("card_inherit", p$id, card$amt) },
        advance_go = { p$teleport(1); p$add_cash(200); self$log_event("card_gogo", p$id, 200) },
        goto = { p$teleport(card$dest); self$handle_space(p) },
        goto_jail = { p$enter_jail(); self$log_event("card_jail", p$id, 0) },
        next_rail = {
          cur <- p$pos
          nxt <- railroad_positions()[railroad_positions() > cur][1]
          if (is.na(nxt)) nxt <- railroad_positions()[1]
          p$teleport(nxt); self$handle_space(p)
        },
        repair_houses = {
          cost <- p$housing_units() * card$per_house + p$hotel_count() * card$per_hotel
          if (cost > 0) { paid <- self$settle_debt(p, cost, "repairs"); self$log_event("card_repairs", p$id, paid) }
        },
        pay_each = {
          others <- which(vapply(self$players, function(q) q$alive() && q$id != p$id, logical(1)))
          tot <- length(others) * card$amt
          if (tot > 0) {
            paid <- self$settle_debt(p, tot, "payeach")
            per_o <- floor(paid / max(length(others), 1))
            for (o in others) self$players[[o]]$add_cash(per_o)
            self$log_event("card_payeach", p$id, paid)
          }
        },
        get_out = { p$got_out <- p$got_out + 1L; self$log_event("card_getout", p$id, 0) }
      )
    },

    # ---- Deterministic AI actions -------------------------------------------
    do_ai_actions = function(p) {
      self$ai_build(p)
      self$ai_mortgage(p)
      self$ai_trade(p)
    },

    ai_build = function(p) {
      if (!isTRUE(self$cfg$ai_build_evenly)) return(invisible(NULL))
      for (g in names(GROUP_POSITIONS)) {
        if (!p$has_complete_group(g)) next
        pos_list <- GROUP_POSITIONS[[g]]
        # even build: raise the minimum-house property up to 4 (or hotel)
        for (round_no in 0:4) {
          target <- pos_list[vapply(pos_list, function(pp) {
            h <- p$holding_by_pos(pp); !is.null(h) && !isTRUE(h$mortgaged) && as.integer(h$houses) == round_no
          }, logical(1))]
          if (length(target) == 0) break
          pp <- target[1]; h <- p$holding_by_pos(pp)
          cost <- if (isTRUE(self$cfg$ds_free_housing)) 0 else h$improve_cost
          if (p$can_afford(cost)) {
            p$pay(cost); p$set_houses(pp, round_no + 1L)
            self$log_event("build", p$id, cost)
          } else break
        }
      }
    },

    ai_mortgage = function(p) {
      if (!isTRUE(self$cfg$mortgage_allowed)) return(invisible(NULL))
      if (p$cash >= 100) return(invisible(NULL))  # only when tight
      # Mortgage lowest-rent unimproved property first.
      cand <- Filter(function(h) !isTRUE(h$mortgaged) && as.integer(h$houses) == 0, p$holdings)
      if (length(cand) == 0) return(invisible(NULL))
      ord <- order(vapply(cand, function(h) h$base_rent, numeric(1)))
      h <- cand[[ord[1]]]
      loan <- 0.5 * h$price
      h$mortgaged <- TRUE; p$add_cash(loan); self$log_event("mortgage", p$id, loan)
    },

    ai_trade = function(p) {
      if (!isTRUE(self$cfg$allow_trading)) return(invisible(NULL))
      # Utility-based: propose buying a needed group-mate from an owner if it
      # completes a group and we can afford it. Keep minimal & deterministic.
      for (g in names(GROUP_POSITIONS)) {
        have <- vapply(GROUP_POSITIONS[[g]], function(pp) p$owns_property(pp), logical(1))
        missing <- GROUP_POSITIONS[[g]][!have]
        if (sum(have) == 0 || length(missing) != 1) next
        mp <- missing[1]
        oid <- self$bank$owner_of(mp)
        if (is.na(oid) || oid == p$id) next
        seller <- self$players[[oid]]
        sh <- seller$holding_by_pos(mp)
        if (is.null(sh)) next
        price <- sh$price
        if (p$can_afford(price)) {
          p$pay(price); seller$add_cash(price)
          self$bank$set_owner(mp, p$id)
          seller$remove_holding(mp); p$add_holding(sh)
          self$log_event("trade", p$id, price)
        }
      }
    },

    # ---- Logging -------------------------------------------------------------
    log_event = function(event, pid, amount) {
      self$log_events <- rbind(self$log_events,
        data.table(event = event, turn = self$turn, player = pid, amount = amount))
    }
  )
)

# ---- Helpers ----------------------------------------------------------------
n_players_alive <- function(engine) {
  sum(vapply(engine$players, function(p) p$alive(), logical(1)))
}

next_alive_player <- function(engine, from) {
  n <- length(engine$players)
  i <- from
  repeat {
    i <- i %% n + 1L
    if (engine$players[[i]]$alive()) return(i)
  }
}

make_holding <- function(sq) {
  list(pos = sq$pos, name = sq$name, type = sq$type, group = sq$group,
       price = sq$price, base_rent = sq$base_rent, full_rents = sq$full_rents,
       improve_cost = sq$improve_cost, houses = 0L, mortgaged = FALSE)
}

railroad_positions <- function() BOARD_LAYOUT$pos[BOARD_LAYOUT$type == TYPE_RAILROAD]
utility_positions <- function() BOARD_LAYOUT$pos[BOARD_LAYOUT$type == TYPE_UTIL]
