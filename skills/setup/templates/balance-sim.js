// Pacing sim for the economy doc (`features/economy.md` § Progression Pacing): plays the core loop many times with a
// seeded random player and prints the median, p10 and p90 time to each milestone. Copy to `tools/balance-sim.js`,
// replace CONFIG and playOnce() with the game's loop, and keep every number in step with `economy.md`.
// Run: node tools/balance-sim.js            Override any knob without editing: RUNS=300 PRICE_GROWTH=1.6 node tools/balance-sim.js
const knob = (name, fallback) => (process.env[name] !== undefined ? Number(process.env[name]) : fallback);

const CONFIG = {
  runs: knob("RUNS", 150),
  maxHours: knob("MAX_HOURS", 200),
  incomePerUnit: knob("INCOME", 1),
  basePrice: knob("PRICE", 10),
  priceGrowth: knob("PRICE_GROWTH", 1.5),
  actionSeconds: knob("ACTION_SECONDS", 15),
  upgradeCount: knob("UPGRADES", 20),
};

const MILESTONES = ["first_upgrade", "upgrade_5", "upgrade_10", "complete"];

function seededRandom(seed) {
  let state = seed;
  return () => (state = (state * 16807) % 2147483647) / 2147483647;
}

function weightedPick(random, weights) {
  let roll = random() * weights.reduce((sum, weight) => sum + weight, 0);
  for (let index = 0; index < weights.length; index++) {
    roll -= weights[index];
    if (roll <= 0) return index;
  }
  return weights.length - 1;
}

function playOnce(seed) {
  const random = seededRandom(seed);
  const reached = {};
  const mark = (milestone, time) => {
    if (!(milestone in reached)) reached[milestone] = time;
  };
  let time = 0;
  let gold = 0;
  let units = 1;
  let upgrades = 0;
  while (time < CONFIG.maxHours * 3600) {
    time += CONFIG.actionSeconds;
    gold += units * CONFIG.incomePerUnit * CONFIG.actionSeconds;
    if (weightedPick(random, [0.7, 0.3]) === 1) units += 1;
    const price = CONFIG.basePrice * Math.pow(CONFIG.priceGrowth, upgrades);
    if (gold >= price) {
      gold -= price;
      upgrades += 1;
      if (upgrades === 1) mark("first_upgrade", time);
      if (upgrades === 5) mark("upgrade_5", time);
      if (upgrades === 10) mark("upgrade_10", time);
      if (upgrades >= CONFIG.upgradeCount) {
        mark("complete", time);
        break;
      }
    }
  }
  return reached;
}

function formatTime(seconds) {
  if (seconds == null) return "never";
  return seconds < 3600 ? `${(seconds / 60).toFixed(1)}m` : `${(seconds / 3600).toFixed(1)}h`;
}

const results = Array.from({ length: CONFIG.runs }, (_, index) => playOnce(1234 + index * 7919));
console.log(`${"milestone".padEnd(18)} ${"median".padStart(7)} ${"p10".padStart(7)} ${"p90".padStart(7)}  reached`);
for (const milestone of MILESTONES) {
  const times = results.map((result) => result[milestone]).filter((value) => value != null).sort((left, right) => left - right);
  const at = (fraction) => times[Math.min(times.length - 1, Math.floor(times.length * fraction))];
  console.log(`${milestone.padEnd(18)} ${formatTime(at(0.5)).padStart(7)} ${formatTime(at(0.1)).padStart(7)} ${formatTime(at(0.9)).padStart(7)}  ${times.length}/${CONFIG.runs}`);
}
