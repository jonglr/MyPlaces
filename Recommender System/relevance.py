import math
import random

import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from typing import Dict

# Implements CPL-based scoring for POI relevance with proper mandatory/desired classification.
# Mandatory inputs (must be satisfied):
# - Semantic/Topicality (semantic_p)
# - Spatio-temporal (distance_p & temporal_p combined)
# Desired inputs (nice to have):
# - Cluster (cluster_p)
# - Co-location (colocation_p)
# - Personal/Behavioral (behaviour_p)


# Theme to fclass mapping
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


class CPLRelevanceScorer:

    def __init__(self):
        # CPL parameters
        self.alpha = 0.75  # AND to reduce hard gating
        self.omega = 0.75  # OR for desired terms

    # Generalized Conjunction/Disjunction function.
    def gcd(self, x: float, y: float, alpha: float) -> float:

        if alpha == 1: # alpha = 1: pure conjunction (AND)
            return min(x, y)
        elif alpha == 0: # alpha = 0: pure disjunction (OR)
            return max(x, y)
        else:
            # Weighted power mean
            if x == 0 or y == 0:
                return 0 if alpha > 0.5 else max(x, y) # alpha = 0.5: arithmetic mean
            r = 1 - 2 * alpha  # Exponent for power mean
            if abs(r) < 0.001:  # Near geometric mean
                return math.sqrt(x * y)
            return ((x**r + y**r) / 2) ** (1/r)

    # Conjunctive Partial Absorption (CPA).
    # If mandatory = 0, output = 0 (mandatory requirement not met). Otherwise combines mandatory with desired input in a conjunctive manner.
    def cpa(self, mandatory: float, desired: float, alpha: float = None, omega: float = None) -> float:

        if alpha is None:
            alpha = self.alpha
        if omega is None:
            omega = self.omega

        if mandatory == 0:
            return 0

        # CPA_αω(x_mandatory, y_desired) = x_mandatory ⋄_α (x_mandatory ∇_ω y_desired)
        disjunction_part = self.gcd(mandatory, desired, 1 - omega)  # OR-part
        return self.gcd(mandatory, disjunction_part, alpha)  # AND with mandatory

    # Compute final relevance score using CPL operators.
    def compute_relevance_score(
        self,
        # Mandatory inputs
        semantic_p: float,
        distance_p: float,
        temporal_p: float,
        behaviour_p: float,
        # Desired inputs
        cluster_p: float,
        colocation_p: float
    ) -> float:

        # Step 1: Combine distance and temporal into spatio-temporal component
        # Using conjunction since both are important for spatio-temporal proximity
        spatio_temporal = self.gcd(distance_p, temporal_p, self.alpha)

        # Step 2: Combine the two mandatory components
        # Both semantic and spatio-temporal are mandatory, so use conjunction
        mandatory_combined = self.gcd(semantic_p, spatio_temporal, self.alpha)

        # Step 3: Make behavioural signal mandatory by AND-ing it with the mandatory block
        # First combine the two mandatory components (already computed above) with behaviour
        mandatory_combined = self.gcd(mandatory_combined, behaviour_p, 0.85)

        # Step 4: Combine cluster and co-location into geographic environment (desired)
        # Using partial conjunction as in the paper
        geo_environment = self.gcd(cluster_p, colocation_p, self.alpha)

        # Step 5: Final combination using CPA
        # Mandatory (incl. behaviour) with desired geo environment
        final_score = self.cpa(mandatory_combined, geo_environment)

        return final_score



# 1) Interest score computation
# Calculate the base probability components for relevance scoring.
# Returns dictionary with semantic_p, distance_p, temporal_p, and behaviour_p.
def calculate_base_probabilities(
    distance: float,
    speed: float,
    weather: int,
    is_open: int,
    favorite: int,
    click_count: int,
    last_clicked_date: datetime,
    theme: str,
    fclass: str,
) -> Dict[str, float]:

    # 1. Semantic probability ------------------------------------------------------------------------------------------
    valid_fclasses = theme_to_fclass.get(theme, set())
    semantic_p = 1.0 if fclass in valid_fclasses else 0.0

    # 2. Distance probability ------------------------------------------------------------------------------------------
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
        2: 0.7,  # Cloudy - slightly reduced
        3: 0.3  # Rainy - significantly reduced
    }
    base_distance *= weather_factors.get(weather, 1.0)

    # Gaussian decay: e^(-0.5 * (distance / sigma)^2)
    # sigma controls the spread
    sigma = base_distance
    distance_p = max(0.0, math.exp(-0.5 * (distance / sigma) ** 2))  # Never go below 0

    # 3. Temporal probability ------------------------------------------------------------------------------------------
    temporal_p = 0.6 if is_open == 1 else 0.1

    # 4. Behavioral probability ----------------------------------------------------------------------------------------
    favorite_p = 1.0 if favorite == 1 else 0.3
    days_ago = (datetime.now() - last_clicked_date).days
    click_rate = click_count / (days_ago + 1.0)
    click_p = 1 - math.exp(-click_rate / 5.0)
    behaviour_p = max(favorite_p, click_p)
    
    return {
        'semantic_p': semantic_p,
        'distance_p': distance_p,
        'temporal_p': temporal_p,
        'behaviour_p': behaviour_p
    }

# Complete function to compute CPL-based relevance score.
# This is the main entry point for scoring.
def compute_cpl_relevance_score(
    distance: float,
    speed: float,
    weather: int,
    is_open: int,
    favorite: int,
    click_count: int,
    last_clicked_date: datetime,
    theme: str,
    fclass: str,
    cluster_score: float,
    colocation_score: float
) -> float:
    
    # Calculate base probabilities
    probs = calculate_base_probabilities(
        distance, speed, weather, is_open, favorite,
        click_count, last_clicked_date, theme, fclass
    )
    
    # Create scorer and compute final score
    scorer = CPLRelevanceScorer()
    
    return scorer.compute_relevance_score(
        semantic_p=probs['semantic_p'],
        distance_p=probs['distance_p'],
        temporal_p=probs['temporal_p'],
        cluster_p=cluster_score,
        colocation_p=colocation_score,
        behaviour_p=probs['behaviour_p']
    )


# 2) Data generator
def generate_dataset(num_samples):
    weather_options = [1, 2, 3]
    possible_themes = list(theme_to_fclass.keys())
    all_fclasses_list = list(fclass_to_id.keys())

    now = datetime.now()

    # Generate random data following realistic distributions
    distances = []
    for _ in range(num_samples):
        # 70% within 5km, 20% within 20km, 10% longer distances
        rand = random.random()
        if rand < 0.7:
            # Walking distance: 0-5 km with exponential decay
            dist = np.random.exponential(1.5)  # Mean ~1.5km
            dist = min(dist, 5.0)
        elif rand < 0.9:
            # Biking/short drive: 5-20 km
            dist = random.uniform(5, 20)
        else:
            # Long distance: 20-100 km
            dist = random.uniform(20, 100)
        distances.append(round(dist, 2))

    speeds = []
    for _ in range(num_samples):
        # 60% walking, 25% biking, 15% driving
        rand = random.random()
        if rand < 0.6:
            # Walking: 3-7 km/h
            speed = random.uniform(3, 7)
        elif rand < 0.85:
            # Biking: 10-20 km/h
            speed = random.uniform(10, 20)
        else:
            # Driving: 25-50 km/h
            speed = random.uniform(25, 50)
        speeds.append(round(speed, 2))

    weather = []
    for i in range(num_samples):
        # Weather correlates with distance/speed choices
        if distances[i] < 2 and speeds[i] < 7:
            # Short walking distance - weather matters more
            weather_probs = [0.5, 0.3, 0.2]  # Prefer sunny
        else:
            # Longer distance or driving - weather matters less
            weather_probs = [0.33, 0.34, 0.33]  # Equal distribution

        weather.append(np.random.choice([1, 2, 3], p=weather_probs))

    cluster_scores = []
    colocation_scores = []
    for _ in range(num_samples):
        rand = random.random()
        if rand < 0.4:
            # 40% have low scores (isolated POIs)
            cluster_scores.append(round(random.uniform(0.1, 0.4), 3))
            colocation_scores.append(round(random.uniform(0.1, 0.4), 3))
        elif rand < 0.55:
            # 15% have high scores (highly clustered POIs like pharmacies)
            cluster_scores.append(round(random.uniform(0.6, 0.8), 3))  # Reduced from 0.7-1.0
            colocation_scores.append(round(random.uniform(0.6, 0.8), 3))
        else:
            # 45% have medium scores (majority of POIs)
            cluster_scores.append(round(random.uniform(0.3, 0.6), 3))
            colocation_scores.append(round(random.uniform(0.3, 0.6), 3))

    is_open = [] # correlated with time/theme
    themes = [random.choice(possible_themes) for _ in range(num_samples)]
    for i in range(num_samples):
        # Shopping/food places more likely to be closed sometimes
        if themes[i] in ['shopping', 'food']:
            is_open.append(np.random.choice([0, 1], p=[0.35, 0.65]))
        else:
            is_open.append(np.random.choice([0, 1], p=[0.2, 0.8]))

    # Generate popularity metrics based on cluster and colocation scores
    favorites = []
    click_counts = []

    for i in range(num_samples):
        geo_popularity = (cluster_scores[i] + colocation_scores[i]) / 2

        # Make favorites more impactful
        favorite_prob = 0.2 + (geo_popularity * 0.6)
        favorites.append(1 if random.random() < favorite_prob else 0)

        # Increase click count variance
        if geo_popularity > 0.7:
            base_clicks = random.randint(10, 30)  # Higher range
        elif geo_popularity > 0.4:
            base_clicks = random.randint(3, 10)
        else:
            base_clicks = random.randint(0, 5)

        click_counts.append(base_clicks)

    # Generate last clicked dates (more recent for popular POIs)
    last_clicked_dates = []
    last_clicked_timestamps = []
    for i in range(num_samples):
        geo_popularity = (cluster_scores[i] + colocation_scores[i]) / 2

        # Popular POIs clicked more recently
        if geo_popularity > 0.6:
            days_in_past = random.randint(0, 30)  # Within last month
        elif geo_popularity > 0.3:
            days_in_past = random.randint(10, 180)  # Within last 6 months
        else:
            days_in_past = random.randint(30, 600)  # Could be very old

        last_clicked_date = now - timedelta(days=days_in_past)
        last_clicked_dates.append(last_clicked_date)
        last_clicked_timestamps.append((now - last_clicked_date).days)

    themes = [random.choice(possible_themes) for _ in range(num_samples)]
    fclasses = [random.choice(all_fclasses_list) for _ in range(num_samples)]

    # Calculate interest scores
    interest_scores = []
    for i in range(num_samples):
        score = compute_cpl_relevance_score(
            distance=distances[i],
            speed=speeds[i],
            weather=weather[i],
            is_open=is_open[i],
            favorite=favorites[i],
            click_count=click_counts[i],
            last_clicked_date=last_clicked_dates[i],
            theme=themes[i],
            fclass=fclasses[i],
            cluster_score = cluster_scores[i],
            colocation_score = colocation_scores[i]
        )
        interest_scores.append(round(score, 3))

    # Create DataFrame
    df = pd.DataFrame({
        'distance': distances,
        'speed': speeds,
        'weather': weather,
        'isOpen': is_open,
        'favorite': favorites,
        'clickCount': click_counts,
        'lastClickedDate': last_clicked_timestamps,
        'theme': [theme_to_id[theme] for theme in themes],  # Convert to numeric
        'fclass': [fclass_to_id[fclass] for fclass in fclasses],  # Convert to numeric
        'cluster_score': cluster_scores,
        'colocation_score': colocation_scores,
        'interestScore': interest_scores
    })

    return df

# Save the main datasets
df_main = generate_dataset(5000)
df_main.to_csv('synthetic_relevance.csv', index=False)