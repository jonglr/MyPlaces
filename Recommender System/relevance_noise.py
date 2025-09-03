import numpy as np
import pandas as pd

def add_noise(df, flip_p=0.3, cont_frac=0.3, thematic_flip_p=0.1, rng=None):
    rng = np.random.default_rng(rng)
    df = df.copy()
    theme_size = int(df["theme"].nunique())
    fclass_size = int(df["fclass"].nunique())

    # continuous jitter
    for col in ["distance", "speed"]:
        df[col] = (df[col] + rng.normal(0, cont_frac * df[col])).clip(lower=0)

    # cluster and colocation noise (bounded between 0 and 1)
    for col in ["cluster_score", "colocation_score"]:
        if col in df.columns:
            df[col] = (df[col] + rng.normal(0, cont_frac * df[col])).clip(0.0, 1.0)

    # categorical flips
    mask = rng.random(len(df)) < flip_p
    df.loc[mask, "weather"] = rng.integers(1, 4, mask.sum())
    for col in ["isOpen", "favorite"]:
        mask = rng.random(len(df)) < flip_p
        df.loc[mask, col] = 1 - df.loc[mask, col]

    # clickCount, lastClickedDate
    df["clickCount"]      = (df["clickCount"] + rng.integers(-2, 3, len(df))).clip(lower=0)
    df["lastClickedDate"] = df["lastClickedDate"] - rng.integers(0, 7 * 24 * 3600 + 1, len(df))

    # theme / fclass flips
    mask = rng.random(len(df)) < thematic_flip_p  # thematic_flip_p
    df.loc[mask, "theme"] = rng.integers(0, theme_size, mask.sum())
    mask = rng.random(len(df)) < thematic_flip_p  # thematic_flip_p
    df.loc[mask, "fclass"] = rng.integers(0, fclass_size, mask.sum())

    return df

def augmented(df, n_copies=3, flip_p=0.3, cont_frac=0.3, thematic_flip_p=0.1, seed=42):
    rng = np.random.default_rng(seed)
    dfs = [df]
    for _ in range(n_copies):
        dfs.append(add_noise(df, flip_p, cont_frac, thematic_flip_p, rng))
    return pd.concat(dfs, ignore_index=True)