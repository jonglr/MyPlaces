import numpy as np
import pandas as pd
import math

themes = ['shopping', 'food', 'public transport', 'culture', 'outdoor', 'explore']

# Integer encoding for themes
theme_to_id = {theme: i for i, theme in enumerate(themes)}
#     'shopping': 0,
#     'food': 1,
#     'public transport': 2,
#     'culture': 3,
#     'outdoor': 4,
#     'explore': 5

def assign_theme(time_h, dow, env):
    scores = {t: 0.0 for t in themes}

    # Environment-aware base multipliers (0=urban, 1=rural/small town, 2=nature)
    # Urban: higher PT and culture; later food; low outdoor
    # Rural: higher outdoor & daylight culture; lower PT & shopping overall
    # Nature: very high outdoor & explore; minimal PT & shopping
    env_multipliers = {
        0: {'shopping': 1.8, 'food': 1.2, 'public transport': 2.0, 'culture': 1.5, 'outdoor': 0.2, 'explore': 0.6},
        1: {'shopping': 1.0, 'food': 1.3, 'public transport': 0.3, 'culture': 0.9, 'outdoor': 1.6, 'explore': 1.2},
        2: {'shopping': 0.3, 'food': 0.7, 'public transport': 0.05, 'culture': 0.5, 'outdoor': 2.5, 'explore': 2.0},
    }

    for theme in themes:
        scores[theme] = env_multipliers[env].get(theme, 0.5)

    # Food timing (urban later & wider on weekdays; rural earlier & consistent) ----------------------------------------
    if env == 0:  # urban
        if dow < 5:
            food_peaks = [(8.5, 1.2), (13.0, 1.4), (20.0, 2.0)]
        else:  # weekend: even later social dinners
            food_peaks = [(9.0, 1.2), (13.5, 1.4), (20.5, 2.2)]
    else:  # rural & nature earlier and steadier
        food_peaks = [(7.5, 1.0), (12.0, 1.0), (18.0, 1.2)]

    for peak, std in food_peaks:
        meal_score = math.exp(-0.5 * ((time_h - peak) / std) ** 2)
        # Urban supermarkets emphasize convenience/price; rural links stronger to local supply
        # Slightly stronger weight in rural to reflect tighter food-environment coupling
        weight = 1.9 if env in (1, 2) else 1.75
        scores['food'] += meal_score * weight

    # Rural weekend market mornings (food + shopping bump)
    if env in (1, 2) and dow >= 5 and 8 <= time_h <= 12:
        scores['food'] += 0.6
        scores['shopping'] += 0.8

    # Public transport / commute patterns ------------------------------------------------------------------------------
    # Urban commute peaks strong; rural much weaker and shorter
    commute_morning = math.exp(-0.5 * ((time_h - 8) / (1.0 if env == 0 else 0.8)) ** 2)
    commute_evening = math.exp(-0.5 * ((time_h - 18) / (1.5 if env == 0 else 1.0)) ** 2)
    pt_scale = 1.6 if env == 0 else 0.5  # rural travels less & uses PT less
    scores['public transport'] += (commute_morning + commute_evening) * pt_scale

    # Shopping patterns ------------------------------------------------------------------------------------------------
    if env == 0:
        # Urban weekday evening shopping windows
        if dow < 5 and 15 <= time_h <= 19:
            scores['shopping'] += 1.3
        # Urban weekend afternoon shopping
        if dow >= 5 and 11 <= time_h <= 17:
            scores['shopping'] += 1.1
    else:
        # Rural: fewer opportunities overall; essentials trips spread across the week
        if 9 <= time_h <= 18:
            scores['shopping'] += 0.3
        # Extra weight for Saturday morning markets already handled above

    # Weekly shopping patterns
    if dow == 5:  # Saturday
        if 9 <= time_h <= 16:
            scores['shopping'] += 1.3

    # Culture & leisure ------------------------------------------------------------------------------------------------
    if env == 0:
        # Five-day workweek expands urban leisure in evenings/weekends
        if dow >= 5:
            scores['culture'] += 1.2
        if time_h >= 18:
            scores['culture'] += 0.8
    else:
        # Rural culture/daylight-structured; moderate weekend/daytime emphasis
        daylight_culture = math.exp(-0.5 * ((time_h - 16) / 3) ** 2)
        scores['culture'] += daylight_culture * (1.0 if dow >= 5 else 0.6)

    # Outdoor activities (higher in rural & nature; weekend peak) ------------------------------------------------------
    daylight_factor = math.exp(-0.5 * ((time_h - 14) / 4) ** 2)  # peak early afternoon
    base_outdoor = 1.8 if env in (1, 2) else 0.7
    weekend_boost = 1.2 if dow >= 5 else (0.8 if env in (1, 2) else 0.5)
    scores['outdoor'] += daylight_factor * base_outdoor * weekend_boost

    # Exploration bonus (non-routine times; stronger in nature contexts) -----------------------------------------------
    explore_bonus = 0.8
    if env in (1, 2):
        explore_bonus += 0.3
    if dow >= 5 or time_h < 7 or  time_h >= 20:
        scores['explore'] += explore_bonus

    # Add some randomness for diversity
    for theme in scores:
        scores[theme] += np.random.normal(0, 0.1)

    return theme_to_id[max(scores, key=scores.get)]

def generate_dataset(num_samples):
    data = []
    for _ in range(num_samples):
        # Correlate environment with time patterns
        if np.random.random() < 0.7:  # 70% realistic patterns
            hour = np.random.randint(0, 24)
            dow = np.random.randint(0, 7)

            # Urban areas more active during work hours
            if 9 <= hour <= 17 and dow < 5:
                env = np.random.choice([0, 1, 2], p=[0.7, 0.2, 0.1])
            # Nature/rural on weekends
            elif dow >= 5:
                env = np.random.choice([0, 1, 2], p=[0.3, 0.3, 0.4])
            else:
                env = np.random.choice([0, 1, 2], p=[0.5, 0.3, 0.2])
        else:  # 30% random for diversity
            hour = np.random.randint(0, 24)
            dow = np.random.randint(0, 7)
            env = np.random.choice([0, 1, 2])

        # Generate theme with more nuanced logic
        theme = assign_theme(hour, dow, env)
        data.append([env, hour, dow, theme])

    return pd.DataFrame(data, columns=['environmentType', 'timeOfDay', 'dayOfWeek', 'themeLabel'])

# Generate and save the main dataset (1000 samples)
df_main = generate_dataset(1000)
df_main.to_csv('synthetic_thematic.csv', index=False)