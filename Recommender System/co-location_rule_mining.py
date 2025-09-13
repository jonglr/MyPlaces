import geopandas as gpd
import pandas as pd
import numpy as np
from shapely.geometry import Point
from collections import defaultdict
from tqdm import tqdm
import warnings

warnings.filterwarnings('ignore')

# Excluded fclasses that don't provide meaningful co-location patterns
excluded_fclasses = {
    "post", "car_sharing", "general", "comms_tower", "hunting_stand", "water_works",
    "observation_tower", "wastewater_plant", "water_tower", "embassy", "prison", "courthouse",
    "car_wash", "graveyard", "shelter", "chalet", "bank", "police", "fire_station", "toilet",
    "atm", "vending_any", "vending_parking", "vending_machine", "vending_cigarette",
    "telephone", "recycling_metal", "recycling_paper", "recycling", "recycling_glass",
    "recycling_clothes", "waste_basket", "drinking_water", "fountain", "water_well"
}

# Define parameters
input_file = "OSM_POI.gpkg"
layer_name = "osm_poi"
distance_threshold = 200  # meters
min_support = 5  # Minimum number of premise POIs to consider a rule

print("Co-location Rule Mining for POIs")

# Load data
print("\n1. Loading POI data...")
gdf = gpd.read_file(input_file, layer=layer_name)
print(f"   Loaded {len(gdf)} POIs")

# Clean and prepare data
gdf = gdf[['fclass', 'geometry']].dropna()
gdf = gdf[~gdf['fclass'].isin(excluded_fclasses)]
print(f"   After filtering: {len(gdf)} POIs")

# Project to metric CRS for accurate distance calculations
print("\n2. Projecting to metric CRS...")
gdf = gdf.to_crs(epsg=3857)

# Get fclass counts for filtering
fclass_counts = gdf['fclass'].value_counts()
print(f"   Found {len(fclass_counts)} unique fclass types")

# Build spatial index for faster queries
print("\n3. Building spatial index...")
gdf['geometry_id'] = range(len(gdf))
gdf.reset_index(drop=True, inplace=True)
spatial_index = gdf.sindex

print("\n4. Finding co-located POIs using spatial index...")
co_locations = defaultdict(lambda: defaultdict(int))

# Process each POI and find neighbors within threshold
for idx, poi in tqdm(gdf.iterrows(), total=len(gdf), desc="Processing POIs"):
    # Create buffer bounds (not the buffer geometry itself)
    buffer = poi.geometry.buffer(distance_threshold)
    bounds = buffer.bounds  # This gives (minx, miny, maxx, maxy)

    # Find potential neighbors using spatial index
    possible_matches_index = list(spatial_index.intersection(bounds))
    possible_matches = gdf.iloc[possible_matches_index]

    # Filter to actual neighbors within distance
    if not possible_matches.empty:
        distances = possible_matches.geometry.distance(poi.geometry)
        actual_neighbors = possible_matches[distances <= distance_threshold]

        # Count co-locations (exclude self)
        actual_neighbors = actual_neighbors[actual_neighbors.index != idx]

        for _, neighbor in actual_neighbors.iterrows():
            if poi.fclass != neighbor.fclass:  # Exclude same-type co-locations
                co_locations[poi.fclass][neighbor.fclass] += 1

print("\n5. Computing co-location rules...")
rules_data = []

# Process each potential rule
for premise_fclass, conclusions in co_locations.items():
    # Skip if premise has too few instances
    premise_count = fclass_counts[premise_fclass]
    if premise_count < min_support:
        continue

    premise_pois = gdf[gdf['fclass'] == premise_fclass].copy()

    for conclusion_fclass, co_occur_count in conclusions.items():
        conclusion_count = fclass_counts[conclusion_fclass]
        if conclusion_count < min_support:
            continue

        conclusion_pois = gdf[gdf['fclass'] == conclusion_fclass].copy()

        # Build spatial index for conclusion POIs
        conclusion_sindex = conclusion_pois.sindex

        # Calculate metrics
        coloc_cards = []
        coloc_dists = []
        num_premises_with_conclusion = 0

        for _, premise_poi in premise_pois.iterrows():
            # Get bounds for the buffer around premise POI
            buffer_bounds = (
                premise_poi.geometry.x - distance_threshold,
                premise_poi.geometry.y - distance_threshold,
                premise_poi.geometry.x + distance_threshold,
                premise_poi.geometry.y + distance_threshold
            )

            # Find nearby conclusion POIs
            nearby_idx = list(conclusion_sindex.intersection(buffer_bounds))

            if nearby_idx:
                nearby_conclusions = conclusion_pois.iloc[nearby_idx]
                # Further filter by actual distance
                distances = nearby_conclusions.geometry.distance(premise_poi.geometry)
                within_threshold = nearby_conclusions[distances <= distance_threshold]

                if not within_threshold.empty:
                    num_premises_with_conclusion += 1
                    # Calculate minimum distance
                    min_dist = distances[distances <= distance_threshold].min()
                    coloc_dists.append(min_dist / distance_threshold)
                    # Calculate cardinality metric
                    coloc_cards.append(len(within_threshold))
                else:
                    coloc_dists.append(1.0)
                    coloc_cards.append(0)
            else:
                coloc_dists.append(1.0)
                coloc_cards.append(0)

        # Calculate rule metrics
        if coloc_cards and sum(coloc_cards) > 0:
            # Support: fraction of premise POIs that have at least one conclusion nearby
            support = num_premises_with_conclusion / len(premise_pois)

            # Confidence: average number of conclusions per premise (normalized)
            avg_cardinality = np.mean(coloc_cards)
            max_possible_card = min(len(conclusion_pois), 10)  # Cap at 10 for normalization
            confidence = min(avg_cardinality / max_possible_card, 1.0)

            # Average distance (normalized)
            avg_dist = np.mean(coloc_dists)

            # Lift: how much more likely than random
            expected_random = min(conclusion_count * (np.pi * (distance_threshold / 1000) ** 2) / 1000,
                                  1.0)  # Rough estimate
            lift = support / max(expected_random, 0.01)

            # Combined score
            score = support * confidence * (1 - avg_dist / 2)

            rules_data.append({
                "rule": f"{premise_fclass} → {conclusion_fclass}",
                "premise": premise_fclass,
                "conclusion": conclusion_fclass,
                "support": round(support, 3),
                "confidence": round(confidence, 3),
                "lift": round(lift, 2),
                "avg_distance_norm": round(avg_dist, 3),
                "avg_cardinality": round(avg_cardinality, 2),
                "score": round(score, 4),
                "premise_count": premise_count,
                "conclusion_count": conclusion_count,
                "co_occurrences": co_occur_count
            })

# Create results DataFrame
print(f"\n6. Found {len(rules_data)} valid rules")
results_df = pd.DataFrame(rules_data)

if not results_df.empty:
    # Sort by score
    results_df = results_df.sort_values(by='score', ascending=False)

    # Display top rules
    print("\n" + "=" * 60)
    print("TOP CO-LOCATION RULES (by score)")
    print("=" * 60)

    top_rules = results_df.head(30)
    for idx, row in top_rules.iterrows():
        print(f"\n{row['rule']}")
        print(f"  Support: {row['support']:.1%} | Confidence: {row['confidence']:.1%} | Lift: {row['lift']:.1f}x")
        print(f"  Avg Distance: {row['avg_distance_norm'] * distance_threshold:.0f}m | Score: {row['score']:.3f}")

    # Show statistics
    print("\n" + "=" * 60)
    print("RULE STATISTICS")
    print("=" * 60)
    print(f"Total rules discovered: {len(results_df)}")
    print(f"Rules with support > 50%: {len(results_df[results_df['support'] > 0.5])}")
    print(f"Rules with lift > 2: {len(results_df[results_df['lift'] > 2])}")

    # Most common premises and conclusions
    print(f"\nMost common premises:")
    premise_counts = results_df['premise'].value_counts().head(5)
    for premise, count in premise_counts.items():
        print(f"  {premise}: {count} rules")

    print(f"\nMost common conclusions:")
    conclusion_counts = results_df['conclusion'].value_counts().head(5)
    for conclusion, count in conclusion_counts.items():
        print(f"  {conclusion}: {count} rules")

    # Save results
    output_file = "co-location_rules.csv"
    results_df.to_csv(output_file, index=False)
    print(f"\n7. Results saved to {output_file}")

    # Also save a filtered version with only high-quality rules
    high_quality = results_df[(results_df['support'] > 0.3) & (results_df['lift'] > 1.5)]
    if not high_quality.empty:
        high_quality.to_csv("co-location_rules_high_quality.csv", index=False)
        print(f"   High-quality rules saved to co-location_rules_high_quality.csv ({len(high_quality)} rules)")
else:
    print("\nNo valid rules found!")

print("Processing complete!")