#!/usr/bin/env bash
#
# Run one axis of the autotest matrix to exhaustion, in parallel, and tabulate.
#
#   tools/sweep.sh matrix        30 weapons x 13 creature types  (390 fights)
#   tools/sweep.sh variants      every creature variant, one weapon (69)
#   tools/sweep.sh bake          7 chapters x 10 quests of ground (70)
#   tools/sweep.sh variety       each chapter's ten grounds, compared (7)
#   tools/sweep.sh lethality     every weapon against the first enemy (30)
#   tools/sweep.sh details       every weapon's detail screen (30)
#   tools/sweep.sh modes         the six endless modes, each rule (6)
#   tools/sweep.sh modemenu      the six endless modes, reached by clicking (6)
#   tools/sweep.sh named         every hand-written scenario in src/test
#   tools/sweep.sh all           all of the above
#
# Second argument is the job count (default 4). Each job is a whole LÖVE
# process with its own baked terrain canvases and its own copy of the 1080p art
# it touches, so the ceiling is RAM rather than cores: four at a time is what
# this machine takes comfortably.
#
# The lists are read out of vendor/assets rather than written down here: a
# sweep that has to be edited when the data changes is a sweep that silently
# stops covering things.
#
# Per-run isolation: CL_SHARD gives every process its own save directory
# (src/engine/paths.lua), or six runs interleave writes into one save file.
# They are named Crimsonland-Test-<pid> under Application Support and this
# script removes the ones it created when the sweep ends.
#
# A run is a failure if LÖVE exits non-zero, which the harness makes mean
# exactly one of: a scenario expectation failed, or Lua threw. A run that hangs
# is killed by the per-run alarm and counted as a failure too.

set -uo pipefail

SWEEP="${1:-matrix}"
JOBS="${2:-4}"
LIMIT="${CL_LIMIT:-180}" # wall-clock seconds one run may take
LOVE="${LOVE:-$HOME/Applications/love.app/Contents/MacOS/love}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$ROOT/vendor/assets"
OUT="${CL_SWEEP_OUT:-${TMPDIR:-/tmp}/cl-sweep}"

# ---------------------------------------------------------------- one run

if [ "$SWEEP" = "--run" ]; then
	IFS='|' read -r label mod scenario envs <<<"$2"
	log="$OUT/$label.log"
	# alarm survives exec, so this is a timeout without a timeout(1)
	# shellcheck disable=SC2086  # $envs is a list of VAR=value on purpose
	env $envs CL_SHARD="$$" perl -e 'alarm shift; exec @ARGV' "$LIMIT" \
		"$LOVE" "$ROOT" --mod="$mod" --autotest="$scenario" >"$log" 2>&1
	code=$?
	printf '%d\t%s\n' "$code" "$label" >>"$OUT/results.tsv"
	if [ "$code" -eq 0 ]; then printf '.'; else printf '\n[FAIL %s] %s\n' "$code" "$label"; fi
	exit 0
fi

# ---------------------------------------------------------------- the lists

weapon_slots() {
	# The gallery grid is the picker (mods/allweapons/picker.lua), so a weapon
	# is reachable only if the original's layout gave it a plate. It ships 30,
	# and weapons.xml carries 31 player weapons -- the Shrinkifier 5K has no
	# plate and cannot be selected here.
	grep -oE "Weapon_[0-9]+" "$ASSETS/ui/weapons.lua" |
		sed 's/Weapon_//' | sort -un
}

creature_types() {
	# From the variants file, not from creatures.xml: creatures.xml is the art
	# and sound table and includes TROOPER, which is the player's own sprite
	# (play.lua draws the marine from data.creatures.TROOPER). What can be
	# spawned is what some variant claims a type for. The difference is printed
	# below rather than quietly dropped.
	grep -oE 'type="[A-Z_0-9]+"' "$ASSETS/creatures/creature-variants.xml" |
		sed 's/type="//;s/"//' | sort -u
}

creature_types_unspawnable() {
	comm -23 \
		<(grep -oE '<array id="[A-Z_0-9]+"' "$ASSETS/creatures/creatures.xml" |
			sed 's/<array id="//;s/"//' | sort -u) \
		<(creature_types)
}

creature_variants() {
	# Every node in the file, not the Variant_NN ones: two thirds of them are
	# numbered and a third are named -- StandardZombie, BossAlien, StealthSpider,
	# LizardEmperor -- and the named ones are the bosses, the shooters and the
	# spawners. Matching only the numbered form covered 69 of 102 and said
	# nothing about the other 33. The file holds one array and no commented-out
	# nodes, so every id in it is a live variant.
	grep -oE '<node id="[A-Za-z_0-9]+"' "$ASSETS/creatures/creature-variants.xml" |
		sed 's/<node id="//;s/"//' | sort -u
}

chapters() {
	# NUM_CHAPTERS, from the game rather than from memory
	grep -oE "local NUM_CHAPTERS = [0-9]+" "$ROOT/mods/vanilla/game/play.lua" |
		grep -oE "[0-9]+"
}

named_scenarios() {
	# the hand-written ones; the parameterised three are the sweeps themselves
	for f in "$ROOT"/src/test/scenarios/*.lua; do
		n="$(basename "$f" .lua)"
		case "$n" in matrix | bake | mode | mode-menu | lethality | weapon-details) ;; *) echo "$n" ;; esac
	done
}

jobs_for() {
	case "$1" in
	matrix)
		for skip in $(creature_types_unspawnable); do
			echo "not in the matrix: $skip has no spawn variant" >&2
		done
		for w in $(weapon_slots); do
			for c in $(creature_types); do
				echo "matrix-w$w-$c|allweapons|matrix|CL_WEAPON=$w CL_CREATURE=$c"
			done
		done
		;;
	variants)
		# one weapon for every variant: the assault rifle, because a mid-range
		# automatic gets shots into anything the AI can reach
		for v in $(creature_variants); do
			echo "variant-$v|allweapons|matrix|CL_WEAPON=2 CL_CREATURE=$v"
		done
		;;
	bake)
		for ch in $(seq 1 "$(chapters)"); do
			for q in $(seq 1 10); do
				echo "bake-$ch-$q|vanilla|bake|CL_CHAPTER=$ch CL_QUEST=$q"
			done
		done
		;;
	variety)
		for ch in $(seq 1 "$(chapters)"); do
			echo "variety-$ch|vanilla|bake-variety|CL_CHAPTER=$ch"
		done
		;;
	lethality)
		# every gun against the first enemy in the game: it has to be able to
		# kill it, and three of them could not
		for w in $(weapon_slots); do
			echo "lethal-w$w|allweapons|lethality|CL_WEAPON=$w"
		done
		;;
	details)
		# every plate the grid has: the layout stores the assault rifle's own
		# values as its placeholders, so a screen that was never filled still
		# passes for slot 2 and fails for the other 29
		for w in $(weapon_slots); do
			echo "details-w$w|vanilla|weapon-details|CL_WEAPON=$w"
		done
		;;
	modes)
		for m in survival rush blitz waves nukefism weaponpicker; do
			echo "mode-$m|vanilla|mode|CL_MODE=$m"
		done
		;;
	modemenu)
		# the same six, but selected off the survival menu rather than started
		# by the call behind it -- Waves had no visible button at all
		for m in SURVIVAL RUSH BLITZ WAVES NUKEFISM WEAPONPICKER; do
			echo "modemenu-$m|vanilla|mode-menu|CL_MODE=$m"
		done
		;;
	named)
		for s in $(named_scenarios); do
			# a scenario names its cartridge by its prefix: td-* only exist
			# inside the tower defence mod's screens, allweapons-* need the
			# picker, and the rest are the base game
			case "$s" in
			td-*) echo "named-$s|towerdefence|$s|CL_NAMED=1" ;;
			allweapons-*) echo "named-$s|allweapons|$s|CL_NAMED=1" ;;
			*) echo "named-$s|vanilla|$s|CL_NAMED=1" ;;
			esac
		done
		;;
	*) echo "unknown sweep '$1'" >&2 && exit 2 ;;
	esac
}

# ---------------------------------------------------------------- the sweep

[ "$SWEEP" = "all" ] && SWEEPS="named modes modemenu details bake variety lethality variants matrix" || SWEEPS="$SWEEP"

test -x "$LOVE" || {
	echo "LÖVE not found at $LOVE" >&2
	exit 1
}
mkdir -p "$OUT"
: >"$OUT/results.tsv"

started="$(date +%s)"
total=0
for s in $SWEEPS; do
	list="$(jobs_for "$s")"
	n="$(echo "$list" | grep -c .)"
	total=$((total + n))
	echo "== $s: $n runs, $JOBS at a time"
	echo "$list" | tr '\n' '\0' | xargs -0 -P "$JOBS" -n1 "$0" --run
	echo
done
elapsed=$(($(date +%s) - started))

# the per-run save directories this sweep created
find "$HOME/Library/Application Support" -maxdepth 1 -name 'Crimsonland-Test-*' \
	-type d -exec rm -rf {} + 2>/dev/null

# ---------------------------------------------------------------- the table

fails="$(awk -F'\t' '$1 != 0' "$OUT/results.tsv" | sort -k2)"
nfail="$(echo "$fails" | grep -c .)"
{
	echo "sweep: $SWEEPS"
	echo "runs:  $total in ${elapsed}s at $JOBS jobs"
	echo "pass:  $((total - nfail))"
	echo "fail:  $nfail"
	if [ "$nfail" -gt 0 ]; then
		echo
		printf '%-38s %-5s %s\n' LABEL EXIT WHY
		echo "$fails" | while IFS=$'\t' read -r code label; do
			why="$(grep -hE '^\[test\] (FAIL|ERROR)' "$OUT/$label.log" 2>/dev/null |
				head -2 | tr '\n' ' ')"
			[ -z "$why" ] && why="(no verdict — killed after ${LIMIT}s or died early)"
			printf '%-38s %-5s %s\n' "$label" "$code" "$why"
		done
	fi
	echo
	echo "== reported lines"
	grep -hE '^\[(matrix|bake|mode)\]' "$OUT"/*.log 2>/dev/null | sort
} | tee "$OUT/report.txt"

[ "$nfail" -eq 0 ]
