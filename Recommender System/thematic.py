import numpy as np
import pandas as pd
import math

THEMES = ['shopping', 'food', 'public transport', 'culture', 'outdoor', 'explore']

# Base weights contributed purely by the surrounding environment
# 0 = urban, 1 = rural, 2 = nature
ENV_WEIGHTS = {
    0: {'shopping': 1.0, 'public transport': 1.2, 'culture': 1.0, 'food': 0.6, 'explore': 0.3, 'outdoor': 0.0},
    1: {'food': 0.8, 'explore': 0.8, 'outdoor': 0.6, 'shopping': 0.3, 'culture': 0.2, 'public transport': 0.2},
    2: {'outdoor': 2.0, 'explore': 1.0, 'food': 0.5, 'culture': 0.3, 'shopping': 0.0, 'public transport': 0.0},
}

# Integer encoding for themes
theme_to_id = {theme: i for i, theme in enumerate(THEMES)}
#     'shopping': 0,
#     'food': 1,
#     'public transport': 2,
#     'culture': 3,
#     'outdoor': 4,
#     'explore': 5

def assign_theme(time_h, dow, env):
    scores = {t: 0.0 for t in THEMES}

    # Base environmental preferences with smoother transitions
    env_multipliers = {
        0: {'shopping': 1.5, 'food': 1.2, 'public transport': 1.8, 'culture': 1.3, 'outdoor': 0.3, 'explore': 0.5},
        1: {'shopping': 0.8, 'food': 1.0, 'public transport': 0.5, 'culture': 0.7, 'outdoor': 1.2, 'explore': 1.3},
        2: {'shopping': 0.2, 'food': 0.6, 'public transport': 0.1, 'culture': 0.4, 'outdoor': 2.3, 'explore': 1.8},
    }

    for theme in THEMES:
        scores[theme] = env_multipliers[env].get(theme, 0.5)

    # Meal times with Gaussian peaks
    meal_times = [(8, 1.5), (12.5, 1.8), (19, 2)]  # (peak_hour, std_dev)
    for peak, std in meal_times:
        meal_score = math.exp(-0.5 * ((time_h - peak) / std) ** 2)
        scores['food'] += meal_score * 1.8

    # Commute patterns (weekdays only)
    if dow < 5:
        commute_morning = math.exp(-0.5 * ((time_h - 8) / 1) ** 2)
        commute_evening = math.exp(-0.5 * ((time_h - 18) / 1.5) ** 2)
        scores['public transport'] += (commute_morning + commute_evening) * 1.5

    # Shopping patterns
    if dow < 5:  # Weekday evening shopping
        if 17 <= time_h <= 20:
            scores['shopping'] += 1.2
    else:  # Saturday shopping
        if dow < 6 and 9 <= time_h <= 16:
            scores['shopping'] += 1.5

    # Culture/entertainment
    if dow >= 5 or time_h >= 19:  # Weekends or evenings
        scores['culture'] += 1.0

    # Outdoor activities (daylight preference)
    daylight_factor = math.exp(-0.5 * ((time_h - 14) / 4) ** 2)  # Peak at 2 PM
    scores['outdoor'] += daylight_factor * (1.5 if dow >= 5 else 0.7)

    # Exploration bonus for non-routine times
    if dow >= 5 or time_h < 7 or time_h > 20:
        scores['explore'] += 0.8

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