import csv
import random
import math
import pandas as pd
from datetime import datetime, timedelta

# 1) Defines theme->fclass mapping
theme_to_fclass = {
    "shopping": {
        "supermarket","convenience","beverages","market_place","mall","greengrocer",
        "hairdresser","clothes","bakery","beauty_shop","car_dealership","florist",
        "sports_shop","jeweller","butcher","shoe_shop","furniture_shop","gift_shop",
        "doityourself","mobile_phone_shop","car_rental","toy_shop","computer_shop",
        "department_store","garden_centre","outdoor_shop","video_shop","travel_agent",
        "laundry","stationery","chemist","bicycle_shop","bicycle_rental","kiosk",
        "newsagent","bookshop","optician"
    },
    "food": {
        "restaurant","fast_food","food_court","cafe"
    },
    "public transport": {
        "airport","airfield","bus_station","bus_stop","helipad","taxi","ferry_terminal",
        "railway_halt","railway_station","tram_stop"
    },
    "culture": {
        "artwork","arts_centre","bar","pub","museum","theatre","nightclub","cinema",
        "biergarten","theme_park","community_centre","public_building","town_hall"
    },
    "outdoor": {
        "picnic_site","park","dog_park","zoo","peak","beach","spring","viewpoint",
        "tower","tourist_info","wayside_shrine"
    },
    "explore": set()  # no direct boost
}

# Integer encoding for themes
theme_to_id = {theme: i for i, theme in enumerate(theme_to_fclass.keys())}
#     'shopping': 0,
#     'food': 1,
#     'public transport': 2,
#     'culture': 3,
#     'outdoor': 4,
#     'explore': 5

# Integer encoding for fclasses
all_fclasses = sorted(set().union(*theme_to_fclass.values()))
fclass_to_id = {fclass: i for i, fclass in enumerate(all_fclasses)}
#     'airport': 0,
#     'artwork': 1,
#     ...

# Scoring configuration
BASE_WEIGHTS = {
    "semantic": 0.35,
    "distance": 0.50,
    "temporal": 0.20,
    "behaviour": 0.10
}

# Thematic Scoring Adjustments
THEMATIC_GATE = 0.15

def thematic_gate(theme: str, fclass: str, eps: float = THEMATIC_GATE) -> float:
    valid = theme_to_fclass.get(theme, set())
    match = 1.0 if fclass in valid else 0.0
    # If on-theme => gate=1; off-theme => gate=eps
    return eps + (1.0 - eps) * match

# Tunable penalties for missing data
MISSING_NAME_PENALTY = 0.50
MISSING_HOURS_PENALTY = 0.20
MIN_QUALITY_MULT = 0.2  # don’t drop below this

def data_quality_multiplier(has_name: bool, has_opening_hours: bool) -> float:
    penalty = 0.0
    if not has_name:
        penalty += MISSING_NAME_PENALTY
    if not has_opening_hours:
        penalty += MISSING_HOURS_PENALTY
    return max(1.0 - penalty, MIN_QUALITY_MULT)

def adapt_weights(base, theme: str, speed: float):
    w = base.copy()

    # Quick, routine tasks (e.g. cafés/fast food) -> distance ↑, semantic ↓
    if theme == "food":
        w["distance"] += 0.15
        w["semantic"] -= 0.10

    # Planned / leisure activities -> temporal & semantic ↑, distance ↓
    if theme in {"culture", "outdoor"}:
        w["temporal"] += 0.10
        w["semantic"] += 0.05
        w["distance"]  -= 0.10

    # Transport speed diminishes distance sensitivity
    if speed >= 25:            # car / e‑bike
        w["distance"] *= 0.6
    elif speed >= 10:          # bicycle
        w["distance"] *= 0.8

    # Normalise so the weights sum to 1
    s = sum(w.values())
    for k in w:
        w[k] /= s
    return w

def get_temporal_probability(is_open: int) -> float:
    return 0.5 if is_open == 1 else 0.0

# 2) Interest score computation
def compute_interest_score(
    distance,
    speed,
    weather,
    is_open,
    favorite,
    click_count,
    last_clicked_date,
    theme,
    has_name,
    has_opening_hours,
    fclass
):
    # 1. Semantic / thematic ---------------------------------------------
    def get_thematic_probability(theme_str, poi_fclass):
        valid_fclasses = theme_to_fclass.get(theme_str, set())
        return 1.0 if poi_fclass in valid_fclasses else 0.0
    semantic_p = get_thematic_probability(theme, fclass)

    # 2. Distance --------------------------------------------------------
    # Determine base comfortable distance
    if speed < 7:
        base_distance = 1.0  # 1 km walking
    elif speed < 15:
        base_distance = 3.0  # 3 km biking
    else:
        base_distance = 5.0  # 5 km driving

    # Adjust base distance for weather
    weather_factors = {
        1: 1.0,  # Sunny - normal
        2: 0.8,  # Cloudy - slightly reduced
        3: 0.6  # Rainy - significantly reduced
    }
    base_distance *= weather_factors.get(weather, 1.0)

    # Gaussian decay: e^(-0.5 * (distance / sigma)^2)
    # sigma controls the spread (we use 0.8 * base_distance for nice behavior)
    sigma = base_distance

    probability = math.exp(-0.5 * (distance / sigma) ** 2)
    distance_p = max(0.01, probability)  # Never go below 0.01

    # 3. Temporal --------------------------------------------------------
    temporal_p = get_temporal_probability(is_open)

    # --- 4. Behavioural -------------------------------------------------
    favorite_p = 0.5 if favorite == 1 else 0.0
    days_ago   = (datetime.now() - last_clicked_date).days
    click_raw  = click_count / (days_ago + 1.0)
    click_p    = min(click_raw / 10.0, 1.0)
    behaviour_p = max(favorite_p, click_p)  # take the stronger signal

    # Combine with weighted noisy‑OR
    parts = {
        "semantic":  semantic_p,
        "distance":  distance_p,
        "temporal":  temporal_p,
        "behaviour": behaviour_p
    }

    weights = adapt_weights(BASE_WEIGHTS, theme, speed)

    product = 1.0
    for k, p in parts.items():
        product *= (1.0 - p) ** weights[k]

    base_score = 1.0 - product
    # Apply the soft gate
    gate = thematic_gate(theme, fclass)
    q_mult = data_quality_multiplier(has_name, has_opening_hours)
    score = q_mult * gate * base_score
    return score



# 3) Data generator
def generate_dataset(num_samples):
    weather_options = [1, 2, 3]
    possible_themes = list(theme_to_fclass.keys())
    all_fclasses_list = list(fclass_to_id.keys())

    now = datetime.now()

    # Generate random data
    distances = [round(random.uniform(0, 360), 2) for _ in range(num_samples)]
    speeds = [round(random.uniform(0, 35), 2) for _ in range(num_samples)]
    weathers = [random.choice(weather_options) for _ in range(num_samples)]
    is_opens = [random.choice([0, 1]) for _ in range(num_samples)]
    favorites = [random.randint(0, 1) for _ in range(num_samples)]
    click_counts = [random.randint(0, 10) for _ in range(num_samples)]

    # Simulate realistic missingness patterns: popular POIs more likely to have complete data
    has_names = []
    has_opening_hours = []

    for i in range(num_samples):
        # More popular POIs (higher click count, favorited) more likely to have complete data
        popularity_boost = (click_counts[i] / 10.0) + (favorites[i] * 0.3)

        # Base probability of having name/hours, boosted by popularity
        name_prob = min(0.7 + popularity_boost * 0.2, 0.95)
        hours_prob = min(0.6 + popularity_boost * 0.25, 0.9)

        has_names.append(1 if random.random() < name_prob else 0)
        has_opening_hours.append(1 if random.random() < hours_prob else 0)

    # Generate last clicked dates
    last_clicked_dates = []
    last_clicked_timestamps = []
    for _ in range(num_samples):
        days_in_past = random.randint(0, 600)
        last_clicked_date = now - timedelta(days=days_in_past)
        last_clicked_dates.append(last_clicked_date)
        last_clicked_timestamps.append(int(last_clicked_date.timestamp()))

    themes = [random.choice(possible_themes) for _ in range(num_samples)]
    fclasses = [random.choice(all_fclasses_list) for _ in range(num_samples)]

    # Calculate interest scores
    interest_scores = []
    for i in range(num_samples):
        score = compute_interest_score(
            distance=distances[i],
            speed=speeds[i],
            weather=weathers[i],
            is_open=is_opens[i],
            favorite=favorites[i],
            click_count=click_counts[i],
            last_clicked_date=last_clicked_dates[i],
            theme=themes[i],
            fclass=fclasses[i],
            has_name = bool(has_names[i]),
            has_opening_hours = bool(has_opening_hours[i])
        )
        interest_scores.append(round(score, 3))

    # Create DataFrame
    df = pd.DataFrame({
        'distance': distances,
        'speed': speeds,
        'weather': weathers,
        'isOpen': is_opens,
        'favorite': favorites,
        'clickCount': click_counts,
        'lastClickedDate': last_clicked_timestamps,  # Store as Unix timestamp
        'theme': [theme_to_id[theme] for theme in themes],  # Convert to numeric
        'fclass': [fclass_to_id[fclass] for fclass in fclasses],  # Convert to numeric
        'hasName': has_names,
        'hasOpeningHours': has_opening_hours,
        'interestScore': interest_scores
    })

    return df

# Save the main datasets
df_main = generate_dataset(10000)
df_main.to_csv('synthetic_relevance.csv', index=False)