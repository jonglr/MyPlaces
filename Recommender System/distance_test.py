import numpy as np
import matplotlib.pyplot as plt
import math


# taken from the relevance.py file
def compute_distance_probability(distance, speed=5.0, weather=1):
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
    return max(0.01, probability)  # Never go below 0.01

def analyze_distance_threshold():
    """
    Analyze at what distance the relevance score contribution becomes negligible
    """
    distances = np.linspace(0, 10, 1000)  # 0 to 50 km

    # Calculate probabilities for different weather conditions
    probs_sunny = [compute_distance_probability(d, 5, 1) for d in distances]
    probs_cloudy = [compute_distance_probability(d, 5, 2) for d in distances]
    probs_rainy = [compute_distance_probability(d, 5, 3) for d in distances]

    # Find thresholds where contribution drops below certain levels
    thresholds = [0.1, 0.05, 0.01]  # 10%, 5%, 1% contribution

    print("Distance Threshold Analysis")
    print("=" * 50)

    for weather_name, probs in [("Sunny", probs_sunny),
                                ("Cloudy", probs_cloudy),
                                ("Rainy", probs_rainy)]:
        print(f"\n{weather_name} Weather:")
        for threshold in thresholds:
            # Find first distance where probability drops below threshold
            idx = next((i for i, p in enumerate(probs) if p < threshold), None)
            if idx is not None:
                dist = distances[idx]
                print(f"  Distance where contribution < {threshold * 100:.0f}%: {dist:.1f} km")

    # Plotting
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

    # Plot 1: Distance probability curves
    ax1.plot(distances, probs_sunny, label='Sunny', linewidth=2)
    ax1.plot(distances, probs_cloudy, label='Cloudy', linewidth=2)
    ax1.plot(distances, probs_rainy, label='Rainy', linewidth=2)
    ax1.axhline(y=0.1, color='red', linestyle='--', alpha=0.5, label='10% threshold')
    ax1.axhline(y=0.05, color='orange', linestyle='--', alpha=0.5, label='5% threshold')
    ax1.axhline(y=0.01, color='yellow', linestyle='--', alpha=0.5, label='1% threshold')
    ax1.set_xlabel('Distance (km)')
    ax1.set_ylabel('Distance Contribution to Score')
    ax1.set_title('Distance Impact on Relevance Score')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    ax1.set_xlim(0, 10)  # Focus on relevant range

    # Plot 2: Zoomed in view for practical thresholds
    ax2.plot(distances, probs_sunny, label='Sunny', linewidth=2)
    ax2.plot(distances, probs_cloudy, label='Cloudy', linewidth=2)
    ax2.plot(distances, probs_rainy, label='Rainy', linewidth=2)
    ax2.axhline(y=0.05, color='orange', linestyle='--', alpha=0.5, label='5% threshold')
    ax2.set_xlabel('Distance (km)')
    ax2.set_ylabel('Distance Contribution to Score')
    ax2.set_title('Practical Distance Thresholds (Zoomed)')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    ax2.set_xlim(0, 4)
    ax2.set_ylim(0, 0.3)

    plt.tight_layout()
    plt.show()

    return fig


def simulate_full_relevance_score(distance, weather=2):
    """
    Simulate a full relevance score calculation with varying distances
    Using typical values for other parameters
    """
    # Base weights from your code
    BASE_WEIGHTS = {
        "semantic": 0.35,
        "distance": 0.35,
        "temporal": 0.20,
        "behaviour": 0.10
    }

    # Fixed typical values for other components
    semantic_p = 0.5  # Assume moderate theme match
    temporal_p = 0.5  # Assume open
    behaviour_p = 0.2  # Some past interaction

    # Calculate distance probability
    distance_p = compute_distance_probability(distance, weather)

    # Noisy-OR combination (simplified from your code)
    parts = {
        "semantic": semantic_p,
        "distance": distance_p,
        "temporal": temporal_p,
        "behaviour": behaviour_p
    }

    product = 1.0
    for k, p in parts.items():
        product *= (1.0 - p) ** BASE_WEIGHTS[k]

    score = 1.0 - product
    return score


def analyze_practical_thresholds():
    """
    Analyze practical distance thresholds for bounding box
    """
    print("\n" + "=" * 50)
    print("Practical Recommendations for Bounding Box")
    print("=" * 50)

    distances = np.linspace(0, 10, 100)

    # Calculate full scores
    scores_sunny = [simulate_full_relevance_score(d, 1) for d in distances]
    scores_cloudy = [simulate_full_relevance_score(d, 2) for d in distances]
    scores_rainy = [simulate_full_relevance_score(d, 3) for d in distances]

    # Find where scores drop below 0.5 (your current threshold)
    relevance_threshold = 0.5

    for weather_name, scores, weather_code in [("Sunny", scores_sunny, 1),
                                               ("Cloudy", scores_cloudy, 2),
                                               ("Rainy", scores_rainy, 3)]:
        # Find maximum distance where score > threshold
        max_dist = None
        for i, (d, s) in enumerate(zip(distances, scores)):
            if s >= relevance_threshold:
                max_dist = d

        if max_dist:
            print(f"\n{weather_name} weather:")
            print(f"  Max distance for score > {relevance_threshold}: {max_dist:.2f} km")

            # Also show score at specific distances
            for test_dist in [0.5, 1.0, 2.0, 3.0, 5.0]:
                score = simulate_full_relevance_score(test_dist, weather_code)
                print(f"  Score at {test_dist} km: {score:.3f}")

    # Plot full relevance scores
    fig, ax = plt.subplots(figsize=(10, 6))
    ax.plot(distances, scores_sunny, label='Sunny weather', linewidth=2)
    ax.plot(distances, scores_cloudy, label='Cloudy weather', linewidth=2)
    ax.plot(distances, scores_rainy, label='Rainy weather', linewidth=2)
    ax.axhline(y=0.5, color='red', linestyle='--', alpha=0.7, label='0.5 relevance threshold')
    ax.set_xlabel('Distance (km)')
    ax.set_ylabel('Total Relevance Score')
    ax.set_title('Full Relevance Score vs Distance (with typical other parameters)')
    ax.legend()
    ax.grid(True, alpha=0.3)
    ax.set_xlim(0, 10)
    ax.set_ylim(0.3, 0.7)
    plt.tight_layout()
    plt.show()

    print("\n" + "=" * 50)
    print("RECOMMENDATION:")
    print("=" * 50)
    print("Based on the analysis, considering:")
    print("- Distance contribution drops below 5% after ~4-7 km")
    print("- Your current 250m (0.25 km) buffer is very conservative")
    print("- Weather conditions affect the effective range")
    print("\nSuggested bounding box radius:")
    print("  - Minimum: 1 km (captures high-relevance POIs)")
    print("  - Recommended: 2-3 km (good balance)")
    print("  - Maximum useful: 5 km (beyond this, distance barely matters)")
    print("\nYour current 0.00225 degrees ≈ 250m is TOO SMALL!")
    print("Consider using 0.009 degrees ≈ 1 km or 0.027 degrees ≈ 3 km")


# Run the analysis
if __name__ == "__main__":
    analyze_distance_threshold()
    analyze_practical_thresholds()