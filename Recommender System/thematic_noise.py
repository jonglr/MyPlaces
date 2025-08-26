import numpy as np
import pandas as pd

def add_noise(df, flip=0.3, rng= None):
    rng = rng or np.random.default_rng()
    df = df.copy()
    env_size = df["environmentType"].nunique()  # 3
    dow_size = df["dayOfWeek"].nunique()  # 7

    # environmentType / dayOfWeek flips
    m = rng.random(len(df)) < flip
    df.loc[m, "environmentType"] = rng.integers(0, env_size, m.sum())
    m = rng.random(len(df)) < flip
    df.loc[m, "dayOfWeek"] = rng.integers(0, dow_size, m.sum())

    # time-of-day ±3 hours wrap-around
    df["timeOfDay"] = (df["timeOfDay"] + rng.integers(-3, 4, len(df))) % 24
    df["timeOfDay"] = df["timeOfDay"].astype(int)

    df[["environmentType", "dayOfWeek"]] = df[["environmentType", "dayOfWeek"]].astype(int)
    return df

def augmented(df, n_copies=3, flip_p=0.3, seed=42):
    rng = np.random.default_rng(seed)
    dfs = [df]
    for _ in range(n_copies):
        dfs.append(add_noise(df, flip_p, rng))
    return pd.concat(dfs, ignore_index=True)
