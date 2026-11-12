class_name NewsDef
extends ContentDef
## One breaking-news headline. `title` is the headline; `reward` picks what tapping it gives (see News):
## cash, compute, double_cash or viral. `weight` is its share of the random pick.

@export var weight: float = 1.0
@export var reward: String = "cash"
