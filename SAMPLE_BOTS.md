# Sample Bots - Learning Path

Study these bots in order to learn rubowar strategy and implementation techniques.

## 1. Spinner (19 lines) - **Start Here**
**File:** `robots/spinner.rb`
**Complexity:** ⭐ Beginner

The simplest complete rubot. Great first bot to study.

**What you'll learn:**
- Basic action API (probe, rotate_turret, fire)
- Sensing latency (probe_echo from previous chronon)
- Energy management (checking energy > 20 before firing)
- Phase awareness (commenting SENSE/MOVE/COMBAT phases)

**Strategy:** Stationary turret that spins and shoots when it detects something.

---

## 2. Tracker (36 lines)
**File:** `robots/tracker.rb`
**Complexity:** ⭐⭐ Beginner+

Introduces proper target tracking using the SimpleTargeting mixin.

**What you'll learn:**
- Using `SimpleTargeting` mixin for aim assistance
- Target acquisition from different sensors (probe → scan → pulse)
- Conditional targeting (turret_aligned?, energy checks)
- Basic defensive play (shields when safe)

**Strategy:** Stationary large turret that methodically tracks and shoots enemies.

**Key takeaway:** Shows how to use helper mixins to reduce complexity.

---

## 3. Coroner (200 lines)
**File:** `robots/coroner.rb`
**Complexity:** ⭐⭐⭐ Intermediate

A defensive sniper that demonstrates movement and state machines.

**What you'll learn:**
- State machine pattern (`:moving_to_corner`, `:scanning`, `:fleeing`)
- Basic movement and positioning
- Corner camping strategy
- Reactive behavior (fleeing when enemies get close)
- Using callbacks (`on_hit`, `on_wall`)

**Strategy:** Camp in corners for defense, flee to another corner if enemies get close.

**Key takeaway:** State machines let you switch between different behaviors cleanly.

---

## 4. Evader (213 lines)
**File:** `robots/evader.rb`
**Complexity:** ⭐⭐⭐ Intermediate+

A patient assassin with counter-intelligence and evasion tactics.

**What you'll learn:**
- Using `detect` for counter-intelligence (know when you're being scanned)
- Proactive juking (random direction changes)
- Adaptive evasion (different responses to being probed vs scanned)
- Kill shot calculation (waiting for the right moment)
- Small bot tactics (harder to hit, agile)

**Strategy:** Evade until aligned for a killing blow, use detect to know when targeted.

**Key takeaway:** Counter-intelligence with `detect` creates advanced mind games.

---

## 5. Crusher (323 lines)
**File:** `robots/crusher.rb`
**Complexity:** ⭐⭐⭐⭐ Advanced

A wall-ramming specialist designed to counter corner campers.

**What you'll learn:**
- Complex positioning logic (calculating ram angles)
- Target prioritization (corner-trapped > wall-adjacent > closest)
- Multi-mode combat (hunting → positioning → ramming → crushing)
- Exploiting game mechanics (corner collisions deal double damage)
- Maintaining pressure on pinned targets

**Strategy:** Ram enemies INTO walls for extra damage, especially effective against corner campers.

**Key takeaway:** Advanced bots exploit environmental mechanics and calculate optimal attack angles.

---

## 6. Hunter (326 lines)
**File:** `robots/hunter.rb`
**Complexity:** ⭐⭐⭐⭐ Advanced

An adaptive predator that adjusts tactics based on prey characteristics.

**What you'll learn:**
- Adaptive strategy (different tactics vs small/medium/large bots)
- Aggressive pursuit and interception
- Lead angle calculation for moving targets
- Ramming as a combat tactic
- Energy-efficient hunting

**Strategy:** Hunt aggressively vs small bots, ram and shoot medium bots, kite large bots.

**Key takeaway:** Adapt your strategy based on opponent characteristics for maximum effectiveness.

---

## 7. Hugger (452 lines) - **Most Complex**
**File:** `robots/hugger.rb`
**Complexity:** ⭐⭐⭐⭐⭐ Expert

A wall-hugging evader with minimal movement philosophy.

**What you'll learn:**
- Minimal movement philosophy (small bot, micro-adjustments)
- Wall-hugging tactics
- Complex state management
- Patient, defensive playstyle
- Kill confirmation logic

**Strategy:** Hug walls using small hitbox for defense, make micro-adjustments, wait for perfect shots.

**Key takeaway:** Small bots can excel with precision positioning instead of constant movement.

---

## Recommended Study Order

1. **Spinner** → Learn the basics
2. **Tracker** → Learn mixins and targeting
3. **Coroner** → Learn state machines and movement
4. **Evader** → Learn counter-intelligence and evasion
5. Pick based on interest:
   - Like ramming? → **Crusher**
   - Like hunting? → **Hunter**
   - Like wall play? → **Hugger**

## Common Patterns Across Bots

### Energy Management
- All bots check `energy > threshold` before expensive actions
- Most use conditional firing based on energy levels
- Sensing is budgeted carefully (pulse is expensive)

### Target Tracking
- **Simple:** Use `probe_echo` directly (Spinner)
- **Better:** Use `SimpleTargeting` mixin (Tracker)
- **Advanced:** Manual lead angle calculation (Crusher, Hunter)

### Movement Strategies
- **Stationary:** No thrust (Spinner, Tracker)
- **Defensive:** Move to safe positions (Coroner, Evader)
- **Aggressive:** Chase and ram (Crusher, Hunter)
- **Wall Play:** Hug walls for defense (Hugger)

### Size Choices
- **Small:** Evader, Hugger (agile, harder to hit, 8 energy regen)
- **Medium:** Spinner, Coroner (balanced, 10 energy regen)
- **Large:** Tracker, Crusher, Hunter (tanky, 12 energy regen, easier to hit)

## Next Steps

After studying these bots:
1. Copy one as a template
2. Modify its strategy
3. Test against the sample bots
4. Iterate and refine

Remember: The best bot depends on the meta (what everyone else is playing)!
