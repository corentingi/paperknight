-- Glicko-2 rating (Glickman, "Example of the Glicko-2 system", 2013), pure
-- math. A player is { rating, rd, vol } on the usual Elo-like scale; the
-- rating period is one day: the deviation grows with the days without play
-- (ADR-0010).
local PkGlicko = {}

PkGlicko.START = { rating = 1200, rd = 350, vol = 0.06 }
PkGlicko.TAU = 0.5            -- how fast the volatility may change
PkGlicko.MIN_RD, PkGlicko.MAX_RD = 45, 350
PkGlicko.MAX_VOL = 0.1
PkGlicko.PUZZLE_RD = 75       -- a puzzle's deviation when unknown

local SCALE = 173.7178
local EPSILON = 1e-6

local function g(phi) return 1 / math.sqrt(1 + 3 * phi * phi / (math.pi * math.pi)) end

-- Step 5: the new volatility (Illinois algorithm).
local function newVolatility(phi, vol, v, delta, tau)
    local a = math.log(vol * vol)
    local function f(x)
        local ex = math.exp(x)
        local d = phi * phi + v + ex
        return ex * (delta * delta - phi * phi - v - ex) / (2 * d * d) - (x - a) / (tau * tau)
    end
    local A, B = a, nil
    if delta * delta > phi * phi + v then
        B = math.log(delta * delta - phi * phi - v)
    else
        local k = 1
        while f(a - k * tau) < 0 do k = k + 1 end
        B = a - k * tau
    end
    local fA, fB = f(A), f(B)
    while math.abs(B - A) > EPSILON do
        local C = A + (A - B) * fA / (fB - fA)
        local fC = f(C)
        if fC * fB <= 0 then
            A, fA = B, fB
        else
            fA = fA / 2
        end
        B, fB = C, fC
    end
    return math.exp(A / 2)
end

--- The player after `results` ({ {rating, rd, score} }, score 1 or 0),
-- `periods` rating periods after their last update (default 1; fractional
-- days in Paperknight). The deviation stays within MIN_RD..MAX_RD.
function PkGlicko.rate(player, results, periods)
    periods = periods or 1
    local mu = (player.rating - 1500) / SCALE
    local phi = player.rd / SCALE
    local v_inv, sum = 0, 0
    for _, r in ipairs(results) do
        local gj = g(r.rd / SCALE)
        local e = 1 / (1 + math.exp(-gj * (mu - (r.rating - 1500) / SCALE)))
        v_inv = v_inv + gj * gj * e * (1 - e)
        sum = sum + gj * (r.score - e)
    end
    local v = 1 / v_inv
    local vol = math.min(PkGlicko.MAX_VOL, newVolatility(phi, player.vol, v, v * sum, PkGlicko.TAU))
    local phi_star = math.min(PkGlicko.MAX_RD / SCALE, math.sqrt(phi * phi + periods * vol * vol))
    local new_phi = 1 / math.sqrt(1 / (phi_star * phi_star) + v_inv)
    local new_mu = mu + new_phi * new_phi * sum
    return {
        rating = 1500 + SCALE * new_mu,
        rd = math.max(PkGlicko.MIN_RD, math.min(PkGlicko.MAX_RD, SCALE * new_phi)),
        vol = vol,
    }
end

--- The deviation after `periods` without play (what the next game starts from).
function PkGlicko.idleRd(player, periods)
    local phi = player.rd / SCALE
    return math.min(PkGlicko.MAX_RD, SCALE * math.sqrt(phi * phi + periods * player.vol * player.vol))
end

return PkGlicko
