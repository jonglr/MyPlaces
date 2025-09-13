import matplotlib.pyplot as plt
from datetime import datetime
import relevance
import relevance_model
import relevance_noise
from sklearn.metrics import mean_squared_error, mean_absolute_error
from datetime import timedelta
import time

def df_to_dict_list(df, n):
    data = []
    for i in range(n):
        row = df.iloc[i]
        entry = {
            "distance": row["distance"],
            "speed": row["speed"],
            "weather": int(row["weather"]),
            "is_open": int(row["isOpen"]),
            "favorite": int(row["favorite"]),
            "click_count": int(row["clickCount"]),
            "last_clicked_date": row["lastClickedDate"],
            "theme": list(relevance.theme_to_id.keys())[int(row["theme"])],
            "fclass": list(relevance.fclass_to_id.keys())[int(row["fclass"])],
            "cluster_score": row["cluster_score"],
            "colocation_score": row["colocation_score"]
        }
        data.append(entry)
    return data

def rule_predict(d):
    return relevance.compute_cpl_relevance_score(
        distance=d["distance"],
        speed=d["speed"],
        weather=d["weather"],
        is_open=d["is_open"],
        favorite=d["favorite"],
        click_count=d["click_count"],
        last_clicked_date=datetime.now() - timedelta(days=d["last_clicked_date"]),
        theme=d["theme"],
        fclass=d["fclass"],
        cluster_score=d["cluster_score"],
        colocation_score=d["colocation_score"]
    )

def ml_predict(d):
    features = [[
        d["distance"],
        d["speed"],
        d["weather"],
        d["is_open"],
        d["favorite"],
        d["click_count"],
        d["last_clicked_date"],
        list(relevance.theme_to_id.keys()).index(d["theme"]),
        list(relevance.fclass_to_id.keys()).index(d["fclass"]),
        d["cluster_score"],
        d["colocation_score"]
    ]]
    return relevance_model.best_model.predict(features)[0]

def benchmark_prediction(fn, df_test, n, label=""):
    """Run prediction function fn on first n rows of df_test and return elapsed time in ms."""
    test_data = df_to_dict_list(df_test, n)
    start = time.time()
    for d in test_data:
        fn(d)
    elapsed = (time.time() - start) * 1000  # convert to ms
    print(f"{n} predictions with {label}: {elapsed:.2f} ms")
    return elapsed

def run_benchmark():
    sizes = [1, 500, 5000]
    ml_times = []
    rule_times = []

    # Generate test data once
    df_test = relevance.generate_dataset(5000)

    # Warm-up prediction
    _ = relevance_model.best_model.predict([[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]])

    for n in sizes:
        ml_times.append(benchmark_prediction(ml_predict, df_test, n, "ML Model"))
        rule_times.append(benchmark_prediction(rule_predict, df_test, n, "Rule-based"))

    # Plot results
    plt.figure(figsize=(8, 5))
    plt.plot(sizes, ml_times, marker="o", label="ML Model", linewidth=2)
    plt.plot(sizes, rule_times, marker="o", label="Rule-based", linewidth=2)

    plt.xlabel("Number of Predictions")
    plt.ylabel("Time (ms)")
    plt.title("Prediction Speed Comparison (ms)")
    plt.legend()
    plt.grid(True)
    plt.show()

if __name__ == "__main__":
    run_benchmark()

def evaluate_under_noise(df_clean, noise_level, model, rule_func):
    # Keep original clean labels as ground truth
    y_true = df_clean["interestScore"].values

    if noise_level == 0.0:
        df_noisy = df_clean.copy()  # No noise for baseline
    else:
        df_noisy = relevance_noise.add_noise(
            df_clean,
            flip_p=noise_level,
            cont_frac=0.3,
            thematic_flip_p=noise_level
        )
    rule_pred = []
    model_pred = []

    for _, row in df_noisy.iterrows():
        # Convert theme and fclass back to strings for rule-based prediction
        theme_str = list(relevance.theme_to_id.keys())[int(row["theme"])]
        fclass_str = list(relevance.fclass_to_id.keys())[int(row["fclass"])]

        # Convert timestamp back to datetime for rule-based prediction
        last_clicked_dt = datetime.now() - timedelta(days=row["lastClickedDate"])

        # Rule-based prediction
        rule = rule_func(
            distance=row["distance"],
            speed=row["speed"],
            weather=int(row["weather"]),
            is_open=int(row["isOpen"]),
            favorite=int(row["favorite"]),
            click_count=int(row["clickCount"]),
            last_clicked_date=last_clicked_dt,
            theme=theme_str,
            fclass=fclass_str,
            cluster_score=row["cluster_score"],
            colocation_score=row["colocation_score"]
        )
        rule_pred.append(rule)

        # ML model prediction
        model_input = [[row["distance"], row["speed"], row["weather"], row["isOpen"], row["favorite"],
                        row["clickCount"], row["lastClickedDate"], row["theme"], row["fclass"], row["cluster_score"],
                        row["colocation_score"]]]
        pred = model.predict(model_input)[0]
        model_pred.append(pred)

    # For regression, use MSE
    rule_mse = mean_squared_error(y_true, rule_pred)
    model_mse = mean_squared_error(y_true, model_pred)

    # Convert MSE to a "performance score" (lower MSE = higher performance)
    rule_perf = 1 / (1 + rule_mse)
    model_perf = 1 / (1 + model_mse)

    return rule_perf, model_perf


noise_levels = [0.0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3]
rule_performances = []
model_performances = []

# Generate clean test set (now returns DataFrame directly)
df_test = relevance.generate_dataset(500)

for noise in noise_levels:
    rule_perf, model_perf = evaluate_under_noise(
        df_test,
        noise,
        relevance_model.best_model,
        relevance.compute_cpl_relevance_score
    )
    rule_performances.append(rule_perf)
    model_performances.append(model_perf)

# Create the plot
plt.figure(figsize=(10, 6))
plt.plot([n * 100 for n in noise_levels], rule_performances, label="Rule-Based", marker='o', linewidth=2)
plt.plot([n * 100 for n in noise_levels], model_performances, label="ML Model", marker='s', linewidth=2)
plt.xlabel("Noise Level (%)")
plt.ylabel("Performance Score (1/(1+MSE))")
plt.title("Model vs Rule-Based Approach: Robustness to Input Noise (Relevance Prediction)")
plt.legend()
plt.grid(True, alpha=0.3)
plt.ylim(0, 1.05)
plt.tight_layout()
plt.show()