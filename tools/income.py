"""What doubling brainrot income does to the rest of the economy.

Reads the real Config, Rarity, Variants and Brainrots rather than carrying its
own copy of the numbers, so it cannot drift from the game.
"""
import io, re

ROOT = "src/ReplicatedStorage/Shared/"

def read(name):
    return io.open(ROOT + name, encoding="utf-8").read()

cfg = read("Config.lua")
def num(key):
    m = re.search(r"Config\.%s\s*=\s*([\d_.*\s]+?)(?:\s*--|\n)" % key, cfg)
    return eval(m.group(1).replace("_", ""))

# tier income and weight
rar = read("Rarity.lua")
tiers = {}
for block in re.finditer(r"(\w+)\s*=\s*\{(.*?)\n\t\}", rar, re.S):
    name, body = block.group(1), block.group(2)
    inc = re.search(r"income\s*=\s*([\d.]+)", body)
    wt = re.search(r"weight\s*=\s*([\d.]+)", body)
    if inc and wt:
        tiers[name] = (float(inc.group(1)), float(wt.group(1)))

# variant multiplier and weight
var = read("Variants.lua")
variants = {}
for block in re.finditer(r"(\w+)\s*=\s*\{(.*?)\n\t\}", var, re.S):
    name, body = block.group(1), block.group(2)
    mult = re.search(r"mult\s*=\s*([\d.]+)", body)
    wt = re.search(r"weight\s*=\s*([\d.]+)", body)
    if mult and wt:
        variants[name] = (float(mult.group(1)), float(wt.group(1)))

# expected value of one drop: tier income x mean char mul x variant mult
brains = read("Brainrots.lua")
muls = [float(m) for m in re.findall(r"mul = ([\d.]+)", brains)]
mean_mul = sum(muls) / len(muls)

tw = sum(w for _, w in tiers.values())
exp_tier = sum(inc * w for inc, w in tiers.values()) / tw
vw = sum(w for _, w in variants.values())
exp_var = sum(m * w for m, w in variants.values()) / vw

base = exp_tier * mean_mul * exp_var
mult = num("IncomeMultiplier")
pads = int(num("MaxSlots"))

print(f"expected tier income   {exp_tier:8.2f}/s   (weighted over rollable tiers)")
print(f"mean character mul     {mean_mul:8.3f}     over {len(muls)} characters")
print(f"expected variant mult  {exp_var:8.3f}")
print(f"\none average brainrot   {base:8.2f}/s  ->  {base * mult:8.2f}/s")
print(f"a full {pads} pads         {base * pads:8.2f}/s  ->  {base * pads * mult:8.2f}/s")

full_before = base * pads
full_after = full_before * mult

def hhmm(seconds):
    h = seconds / 3600
    if h < 1:
        return f"{seconds / 60:.0f} min"
    if h < 48:
        return f"{h:.1f} h"
    return f"{h / 24:.1f} days"

targets = [
    ("last pad", num("SlotBaseCost") * num("SlotCostGrowth") ** (pads - int(num("StartingSlots")) - 1)),
    ("jetpack", num("JetpackCost")),
    ("one Plinko drop", num("PlinkoDropCost")),
    ("first rebirth", num("RebirthBaseCost")),
]
print("\ntime to afford, on a full board of average brainrots:")
print(f"  {'':<18}{'before':>12}{'after':>12}")
for name, cost in targets:
    print(f"  {name:<18}{hhmm(cost / full_before):>12}{hhmm(cost / full_after):>12}")

cap = num("CollectCapSeconds")
print(f"\ncollect cap is {cap / 3600:.0f}h of income, so the pile you walk back to")
print(f"  goes {full_before * cap:,.0f}  ->  {full_after * cap:,.0f}")
