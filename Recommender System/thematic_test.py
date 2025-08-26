import matplotlib.pyplot as plt
import thematic
import thematic_model
import thematic_noise
from sklearn.metrics import accuracy_score

def evaluate_under_noise(df_clean, noise_level, model, rule_func):
    # Keep original clean labels as ground truth
    y_true = df_clean["themeLabel"].values

    # Add noise
    if noise_level == 0.0:
        df_noisy = df_clean.copy()  # No noise for baseline
    else:
        df_noisy = thematic_noise.add_noise(df_clean, flip=noise_level)

    rule_pred = []
    model_pred = []

    for _, row in df_noisy.iterrows():
        # Rule-based prediction
        rule = rule_func(row["timeOfDay"], row["dayOfWeek"], row["environmentType"])
        rule_pred.append(rule)

        # ML model prediction
        model_input = [[row["environmentType"], row["timeOfDay"], row["dayOfWeek"]]]
        pred = model.predict(model_input)[0]
        model_pred.append(pred)

    rule_acc = accuracy_score(y_true, rule_pred)
    model_acc = accuracy_score(y_true, model_pred)

    return rule_acc, model_acc

noise_levels = [0.0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3]
rule_accuracies = []
model_accuracies = []

# Generate clean test set
df_test = thematic.generate_dataset(500)

for noise in noise_levels:
    rule_acc, model_acc = evaluate_under_noise(
        df_test,
        noise,
        thematic_model.best_model,
        thematic.assign_theme
    )
    rule_accuracies.append(rule_acc)
    model_accuracies.append(model_acc)

plt.figure(figsize=(10, 6))
plt.plot([n*100 for n in noise_levels], rule_accuracies, label="Rule-Based", marker='o', linewidth=2)
plt.plot([n*100 for n in noise_levels], model_accuracies, label="ML Model", marker='s', linewidth=2)
plt.xlabel("Noise Level (%)")
plt.ylabel("Accuracy")
plt.title("Model vs Rule-Based Approach: Robustness to Input Noise")
plt.legend()
plt.grid(True, alpha=0.3)
plt.ylim(0, 1.05)
plt.tight_layout()
plt.show()