class_name Hiring
extends RefCounted
## Staff hiring helpers Sim does not provide: the largest hire the equity allows (the MAX choice on the hiring panel).

## Same cap as the producer MAX search (Sim.max_affordable): the search never goes past this.
const MAX_COUNT := 1000000


## Most hires of `role` the equity pays for right now. 0 when hiring is locked (no Funding Round yet), the role is
## unknown, or even one hire is unaffordable. Staff cost rises with each hire, so this bisects on Sim.staff_cost.
static func max_count(s: GameState, role: String) -> int:
	if s.db.get_def("staff", role) == null or s.resets(1) == 0:
		return 0
	var equity: BigNum = s.cur("equity")
	var lo := 0  # always affordable: staff_cost(0) is zero
	var hi := 1
	while Sim.staff_cost(s, role, hi).compare(equity) <= 0:
		if hi >= MAX_COUNT:
			return MAX_COUNT
		lo = hi
		hi = mini(hi * 2, MAX_COUNT)
	# staff_cost(lo) <= equity < staff_cost(hi): narrow the gap to one.
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if Sim.staff_cost(s, role, mid).compare(equity) <= 0:
			lo = mid
		else:
			hi = mid
	return lo
