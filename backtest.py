# ============================================================
# TRADING ANALYZER - BACKTESTER V6
# ============================================================
#
# Características:
# - Todos los pares
# - Todas las temporalidades
# - Hasta 1,000,000 velas por combinación
# - 1M descargado UNA SOLA VEZ por par
# - 2M construido desde 1M
# - Caché reutilizable
# - Reanudación automática
# - Indicadores vectorizados con pandas/numpy
# - Rate-limit protection
# - CSV de resultados
#
# ============================================================

import os
import sys
import time
import argparse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

import numpy as np
import pandas as pd
import requests
from dotenv import load_dotenv


# ============================================================
# ENV
# ============================================================

load_dotenv()

API_KEY = os.getenv("TWELVE_DATA_API_KEY")

if not API_KEY:
    print()
    print("=" * 70)
    print("ERROR: No se encontró TWELVE_DATA_API_KEY")
    print("=" * 70)
    print()
    print("Crea un archivo .env con:")
    print()
    print("TWELVE_DATA_API_KEY=TU_API_KEY")
    print()
    sys.exit(1)


# ============================================================
# CONFIGURACIÓN
# ============================================================

PAIRS = [
    "EUR/USD",
    "GBP/USD",
    "USD/JPY",
    "USD/CHF",
    "AUD/USD",
    "USD/CAD",
    "NZD/USD",
]

TIMEFRAMES = [
    "1min",
    "2min",
    "5min",
    "15min",
    "30min",
    "1h",
]

TF_MINUTES = {
    "1min": 1,
    "2min": 2,
    "5min": 5,
    "15min": 15,
    "30min": 30,
    "1h": 60,
}

DEFAULT_TARGET_BARS = 1_000_000

CHUNK_SIZE = 5000

PAYOUT = 0.90

BREAKEVEN = 1 / (1 + PAYOUT)

CACHE_DIR = Path("twelve_data_cache_v6")
RESULTS_DIR = Path("backtest_results_v6")

CACHE_DIR.mkdir(
    parents=True,
    exist_ok=True,
)

RESULTS_DIR.mkdir(
    parents=True,
    exist_ok=True,
)


# ============================================================
# HTTP SESSION
# ============================================================

SESSION = requests.Session()

SESSION.headers.update({
    "Authorization": f"apikey {API_KEY}",
    "User-Agent": "TradingAnalyzerBacktester/6.0",
})


# ============================================================
# UTILIDADES
# ============================================================

def normalize_pair(pair: str) -> str:
    """
    Twelve Data espera símbolos como EUR/USD.
    """

    return pair.upper()


def safe_name(value: str) -> str:
    return (
        value
        .replace("/", "_")
        .replace(":", "_")
        .replace(" ", "_")
    )


def cache_file(
    pair: str,
    timeframe: str,
) -> Path:

    return (
        CACHE_DIR /
        f"{safe_name(pair)}_{timeframe}.csv"
    )


def result_file(
    pair: str,
    timeframe: str,
) -> Path:

    return (
        RESULTS_DIR /
        f"{safe_name(pair)}_{timeframe}_operations.csv"
    )


def separator():
    print("=" * 75)


# ============================================================
# REQUEST TWELVE DATA
# ============================================================

def request_time_series(
    pair: str,
    timeframe: str,
    end_date=None,
    outputsize=CHUNK_SIZE,
    retries=8,
):

    url = (
        "https://api.twelvedata.com/time_series"
    )

    params = {
        "symbol": normalize_pair(pair),
        "interval": timeframe,
        "outputsize": outputsize,
        "format": "JSON",
        "order": "ASC",
    }

    if end_date:
        params["end_date"] = end_date

    for attempt in range(retries):

        try:

            response = SESSION.get(
                url,
                params=params,
                timeout=90,
            )

            # ------------------------------------------------
            # OK
            # ------------------------------------------------

            if response.status_code == 200:

                data = response.json()

                if "values" in data:

                    return data

                message = data.get(
                    "message",
                    "Respuesta sin valores",
                )

                print(
                    f"    API: {message}"
                )

                # Rate limit
                if "rate" in message.lower():

                    wait = (
                        10 *
                        (attempt + 1)
                    )

                    print(
                        f"    Esperando {wait}s..."
                    )

                    time.sleep(wait)
                    continue

                return None

            # ------------------------------------------------
            # RATE LIMIT
            # ------------------------------------------------

            if response.status_code == 429:

                wait = (
                    15 *
                    (attempt + 1)
                )

                print(
                    f"    HTTP 429. "
                    f"Esperando {wait}s..."
                )

                time.sleep(wait)

                continue

            # ------------------------------------------------
            # 404
            # ------------------------------------------------

            if response.status_code == 404:

                print(
                    "    HTTP 404."
                )

                try:
                    error_data = (
                        response.json()
                    )

                    print(
                        "    ",
                        error_data,
                    )

                except Exception:
                    pass

                return None

            # ------------------------------------------------
            # OTROS ERRORES
            # ------------------------------------------------

            print(
                f"    HTTP "
                f"{response.status_code}"
            )

            if attempt < retries - 1:

                time.sleep(
                    5 *
                    (attempt + 1)
                )

        except requests.RequestException as e:

            print(
                f"    Error de conexión: {e}"
            )

            if attempt < retries - 1:

                wait = (
                    5 *
                    (attempt + 1)
                )

                time.sleep(wait)

    return None


# ============================================================
# PARSE DATA
# ============================================================

def parse_values(values):

    if not values:
        return pd.DataFrame()

    df = pd.DataFrame(values)

    if "datetime" not in df.columns:
        return pd.DataFrame()

    df["datetime"] = pd.to_datetime(
        df["datetime"],
        errors="coerce",
        utc=True,
    )

    numeric_columns = [
        "open",
        "high",
        "low",
        "close",
        "volume",
    ]

    for column in numeric_columns:

        if column in df.columns:

            df[column] = pd.to_numeric(
                df[column],
                errors="coerce",
            )

    required = [
        "datetime",
        "open",
        "high",
        "low",
        "close",
    ]

    for column in required:

        if column not in df.columns:

            return pd.DataFrame()

    df = df.dropna(
        subset=required
    )

    df = df[
        [
            "datetime",
            "open",
            "high",
            "low",
            "close",
        ]
    ]

    df = df.drop_duplicates(
        subset=["datetime"]
    )

    df = df.sort_values(
        "datetime"
    )

    return df.reset_index(
        drop=True
    )


# ============================================================
# LOAD CACHE
# ============================================================

def load_cache(
    pair,
    timeframe,
):

    path = cache_file(
        pair,
        timeframe,
    )

    if not path.exists():

        return pd.DataFrame()

    try:

        df = pd.read_csv(
            path
        )

        if df.empty:

            return df

        df["datetime"] = pd.to_datetime(
            df["datetime"],
            errors="coerce",
            utc=True,
        )

        for column in [
            "open",
            "high",
            "low",
            "close",
        ]:

            df[column] = pd.to_numeric(
                df[column],
                errors="coerce",
            )

        df = df.dropna(
            subset=[
                "datetime",
                "open",
                "high",
                "low",
                "close",
            ]
        )

        df = df.drop_duplicates(
            "datetime"
        )

        df = df.sort_values(
            "datetime"
        )

        return df.reset_index(
            drop=True
        )

    except Exception as e:

        print(
            f"    Error leyendo cache: {e}"
        )

        return pd.DataFrame()


# ============================================================
# SAVE CACHE
# ============================================================

def save_cache(
    pair,
    timeframe,
    df,
):

    path = cache_file(
        pair,
        timeframe,
    )

    temp_path = path.with_suffix(
        ".tmp"
    )

    df.to_csv(
        temp_path,
        index=False,
    )

    temp_path.replace(
        path
    )


# ============================================================
# DESCARGA 1 MINUTO
# ============================================================

def download_1m(
    pair,
    target_bars,
):

    separator()

    print(
        f"{pair} | BASE 1MIN"
    )

    # --------------------------------------------------------
    # Cache existente
    # --------------------------------------------------------

    df = load_cache(
        pair,
        "1min",
    )

    if not df.empty:

        print(
            f"    Cache 1M: "
            f"{len(df):,} velas"
        )

    # --------------------------------------------------------
    # Ya tenemos suficiente
    # --------------------------------------------------------

    if len(df) >= target_bars:

        print(
            f"    1M completo."
        )

        return df

    # --------------------------------------------------------
    # Continuar desde la vela más antigua
    # --------------------------------------------------------

    if df.empty:

        end_date = None

    else:

        oldest = df["datetime"].min()

        end_date = (
            oldest -
            pd.Timedelta(
                seconds=1
            )
        ).strftime(
            "%Y-%m-%d %H:%M:%S"
        )

    request_number = 0

    while len(df) < target_bars:

        request_number += 1

        print(
            f"    Request "
            f"#{request_number} | "
            f"{len(df):,}/"
            f"{target_bars:,}"
        )

        data = request_time_series(
            pair=pair,
            timeframe="1min",
            end_date=end_date,
            outputsize=CHUNK_SIZE,
        )

        if not data:

            print(
                "    No se recibieron "
                "más datos."
            )

            break

        values = data.get(
            "values",
            []
        )

        if not values:

            print(
                "    No hay más velas."
            )

            break

        chunk = parse_values(
            values
        )

        if chunk.empty:

            print(
                "    Bloque vacío."
            )

            break

        previous_length = len(df)

        if df.empty:

            df = chunk

        else:

            df = pd.concat(
                [
                    df,
                    chunk,
                ],
                ignore_index=True,
            )

            df = df.drop_duplicates(
                subset=["datetime"]
            )

            df = df.sort_values(
                "datetime"
            ).reset_index(
                drop=True
            )

        added = (
            len(df) -
            previous_length
        )

        print(
            f"    +{added:,} "
            f"| total "
            f"{len(df):,}"
        )

        if added <= 0:

            print(
                "    No hubo datos nuevos."
            )

            break

        # Guardar inmediatamente
        save_cache(
            pair,
            "1min",
            df,
        )

        # Nueva fecha de paginación
        oldest = df["datetime"].min()

        new_end_date = (
            oldest -
            pd.Timedelta(
                seconds=1
            )
        ).strftime(
            "%Y-%m-%d %H:%M:%S"
        )

        if new_end_date == end_date:

            print(
                "    La fecha no avanzó."
            )

            break

        end_date = new_end_date

        # ----------------------------------------------------
        # Pausa anti-rate-limit
        # ----------------------------------------------------

        time.sleep(
            0.35
        )

        # ----------------------------------------------------
        # Menos de 5000 = posiblemente fin
        # ----------------------------------------------------

        if len(values) < CHUNK_SIZE:

            print(
                "    Bloque menor de 5000."
            )

            print(
                "    Probablemente se "
                "alcanzó el historial "
                "disponible."
            )

            break

    df = df.sort_values(
        "datetime"
    ).reset_index(
        drop=True
    )

    save_cache(
        pair,
        "1min",
        df,
    )

    print(
        f"    1M FINAL: "
        f"{len(df):,} velas"
    )

    if len(df) < target_bars:

        print(
            f"    AVISO: objetivo "
            f"{target_bars:,}, "
            f"disponibles "
            f"{len(df):,}"
        )

    return df


# ============================================================
# AGREGAR 2 MINUTOS
# ============================================================

def build_2m_from_1m(
    pair,
    df_1m,
    target_bars,
):

    separator()

    print(
        f"{pair} | CONSTRUYENDO 2MIN DESDE 1MIN"
    )

    if df_1m.empty:

        return pd.DataFrame()

    df = df_1m.copy()

    df = df.set_index(
        "datetime"
    )

    result = df.resample(
        "2min",
        label="left",
        closed="left",
    ).agg(
        {
            "open": "first",
            "high": "max",
            "low": "min",
            "close": "last",
        }
    )

    result = result.dropna()

    result = result.reset_index()

    result = result.sort_values(
        "datetime"
    )

    result = result.drop_duplicates(
        "datetime"
    )

    if len(result) > target_bars:

        result = result.tail(
            target_bars
        )

    result = result.reset_index(
        drop=True
    )

    # Guardar 2M para futuras ejecuciones
    save_cache(
        pair,
        "2min",
        result,
    )

    print(
        f"    2M construidas: "
        f"{len(result):,}"
    )

    return result


# ============================================================
# DESCARGA TIMEFRAME DIRECTO
# ============================================================

def download_direct(
    pair,
    timeframe,
    target_bars,
):

    separator()

    print(
        f"{pair} | {timeframe}"
    )

    df = load_cache(
        pair,
        timeframe,
    )

    if not df.empty:

        print(
            f"    Cache: "
            f"{len(df):,}"
        )

    if len(df) >= target_bars:

        print(
            "    Cache suficiente."
        )

        return df

    if df.empty:

        end_date = None

    else:

        oldest = df["datetime"].min()

        end_date = (
            oldest -
            pd.Timedelta(
                seconds=1
            )
        ).strftime(
            "%Y-%m-%d %H:%M:%S"
        )

    request_number = 0

    while len(df) < target_bars:

        request_number += 1

        print(
            f"    Request "
            f"#{request_number} | "
            f"{len(df):,}/"
            f"{target_bars:,}"
        )

        data = request_time_series(
            pair=pair,
            timeframe=timeframe,
            end_date=end_date,
            outputsize=CHUNK_SIZE,
        )

        if not data:

            print(
                "    Fin de datos."
            )

            break

        values = data.get(
            "values",
            []
        )

        if not values:

            print(
                "    No hay más datos."
            )

            break

        chunk = parse_values(
            values
        )

        if chunk.empty:

            break

        previous_length = len(df)

        if df.empty:

            df = chunk

        else:

            df = pd.concat(
                [
                    df,
                    chunk,
                ],
                ignore_index=True,
            )

            df = df.drop_duplicates(
                "datetime"
            )

            df = df.sort_values(
                "datetime"
            ).reset_index(
                drop=True
            )

        added = (
            len(df) -
            previous_length
        )

        print(
            f"    +{added:,} "
            f"| total "
            f"{len(df):,}"
        )

        if added <= 0:

            break

        save_cache(
            pair,
            timeframe,
            df,
        )

        oldest = df["datetime"].min()

        new_end_date = (
            oldest -
            pd.Timedelta(
                seconds=1
            )
        ).strftime(
            "%Y-%m-%d %H:%M:%S"
        )

        if new_end_date == end_date:

            break

        end_date = new_end_date

        time.sleep(
            0.35
        )

        if len(values) < CHUNK_SIZE:

            print(
                "    Se alcanzó "
                "probablemente el "
                "historial disponible."
            )

            break

    df = df.sort_values(
        "datetime"
    ).reset_index(
        drop=True
    )

    save_cache(
        pair,
        timeframe,
        df,
    )

    print(
        f"    FINAL {timeframe}: "
        f"{len(df):,}"
    )

    return df


# ============================================================
# EMA
# ============================================================

def calculate_ema(
    series,
    period,
):

    return series.ewm(
        span=period,
        adjust=False,
        min_periods=period,
    ).mean()


# ============================================================
# RSI
# ============================================================

def calculate_rsi(
    close,
    period=14,
):

    delta = close.diff()

    gain = delta.clip(
        lower=0
    )

    loss = -delta.clip(
        upper=0
    )

    avg_gain = gain.ewm(
        alpha=1 / period,
        adjust=False,
        min_periods=period,
    ).mean()

    avg_loss = loss.ewm(
        alpha=1 / period,
        adjust=False,
        min_periods=period,
    ).mean()

    rs = (
        avg_gain /
        avg_loss.replace(
            0,
            np.nan,
        )
    )

    return (
        100 -
        (
            100 /
            (1 + rs)
        )
    )


# ============================================================
# ATR
# ============================================================

def calculate_atr(
    df,
    period=14,
):

    high = df["high"]

    low = df["low"]

    close = df["close"]

    previous_close = close.shift(1)

    tr = pd.concat(
        [
            high - low,
            (
                high -
                previous_close
            ).abs(),
            (
                low -
                previous_close
            ).abs(),
        ],
        axis=1,
    ).max(axis=1)

    return tr.ewm(
        alpha=1 / period,
        adjust=False,
        min_periods=period,
    ).mean()


# ============================================================
# ADX
# ============================================================

def calculate_adx(
    df,
    period=14,
):

    high = df["high"]

    low = df["low"]

    close = df["close"]

    up_move = high.diff()

    down_move = -low.diff()

    plus_dm = np.where(
        (
            up_move >
            down_move
        ) &
        (
            up_move > 0
        ),
        up_move,
        0.0,
    )

    minus_dm = np.where(
        (
            down_move >
            up_move
        ) &
        (
            down_move > 0
        ),
        down_move,
        0.0,
    )

    previous_close = close.shift(1)

    tr = pd.concat(
        [
            high - low,
            (
                high -
                previous_close
            ).abs(),
            (
                low -
                previous_close
            ).abs(),
        ],
        axis=1,
    ).max(axis=1)

    atr = tr.ewm(
        alpha=1 / period,
        adjust=False,
        min_periods=period,
    ).mean()

    plus_dm = pd.Series(
        plus_dm,
        index=df.index,
    )

    minus_dm = pd.Series(
        minus_dm,
        index=df.index,
    )

    plus_di = (
        100 *
        plus_dm.ewm(
            alpha=1 / period,
            adjust=False,
            min_periods=period,
        ).mean() /
        atr
    )

    minus_di = (
        100 *
        minus_dm.ewm(
            alpha=1 / period,
            adjust=False,
            min_periods=period,
        ).mean() /
        atr
    )

    denominator = (
        plus_di +
        minus_di
    ).replace(
        0,
        np.nan,
    )

    dx = (
        100 *
        (
            plus_di -
            minus_di
        ).abs() /
        denominator
    )

    return dx.ewm(
        alpha=1 / period,
        adjust=False,
        min_periods=period,
    ).mean()


# ============================================================
# INDICADORES
# ============================================================

def calculate_indicators(
    df,
):

    df = df.copy()

    close = df["close"]

    df["ema20"] = calculate_ema(
        close,
        20,
    )

    df["ema50"] = calculate_ema(
        close,
        50,
    )

    df["ema20_prev"] = (
        df["ema20"]
        .shift(3)
    )

    df["ema_slope"] = (
        df["ema20"] -
        df["ema20_prev"]
    )

    df["rsi"] = calculate_rsi(
        close,
        14,
    )

    ema12 = calculate_ema(
        close,
        12,
    )

    ema26 = calculate_ema(
        close,
        26,
    )

    df["macd"] = (
        ema12 -
        ema26
    )

    df["macd_signal"] = (
        calculate_ema(
            df["macd"],
            9,
        )
    )

    df["macd_hist"] = (
        df["macd"] -
        df["macd_signal"]
    )

    df["atr"] = calculate_atr(
        df,
        14,
    )

    df["adx"] = calculate_adx(
        df,
        14,
    )

    return df


# ============================================================
# PRICE ACTION
# ============================================================

def calculate_price_action(
    df,
):

    df = df.copy()

    high = df["high"]

    low = df["low"]

    close = df["close"]

    open_ = df["open"]

    # --------------------------------------------------------
    # Estructura
    # --------------------------------------------------------

    previous_high = (
        high
        .shift(1)
        .rolling(
            5,
            min_periods=5,
        )
        .max()
    )

    previous_low = (
        low
        .shift(1)
        .rolling(
            5,
            min_periods=5,
        )
        .min()
    )

    df["HH"] = (
        high >
        previous_high
    )

    df["LL"] = (
        low <
        previous_low
    )

    # --------------------------------------------------------
    # BOS
    # --------------------------------------------------------

    recent_high = (
        high
        .shift(1)
        .rolling(
            10,
            min_periods=10,
        )
        .max()
    )

    recent_low = (
        low
        .shift(1)
        .rolling(
            10,
            min_periods=10,
        )
        .min()
    )

    df["BOS_BULL"] = (
        close >
        recent_high
    )

    df["BOS_BEAR"] = (
        close <
        recent_low
    )

    # --------------------------------------------------------
    # CHOCH
    # --------------------------------------------------------

    previous_bull = (
        df["ema20"]
        .shift(1) >
        df["ema50"]
        .shift(1)
    )

    previous_bear = (
        df["ema20"]
        .shift(1) <
        df["ema50"]
        .shift(1)
    )

    df["CHOCH_BULL"] = (
        previous_bear &
        df["BOS_BULL"]
    )

    df["CHOCH_BEAR"] = (
        previous_bull &
        df["BOS_BEAR"]
    )

    # --------------------------------------------------------
    # Velas
    # --------------------------------------------------------

    body = (
        close -
        open_
    ).abs()

    candle_range = (
        high -
        low
    ).replace(
        0,
        np.nan,
    )

    maximum_oc = pd.concat(
        [
            open_,
            close,
        ],
        axis=1,
    ).max(axis=1)

    minimum_oc = pd.concat(
        [
            open_,
            close,
        ],
        axis=1,
    ).min(axis=1)

    upper_wick = (
        high -
        maximum_oc
    )

    lower_wick = (
        minimum_oc -
        low
    )

    df["body_ratio"] = (
        body /
        candle_range
    )

    df["bullish_candle"] = (
        close >
        open_
    )

    df["bearish_candle"] = (
        close <
        open_
    )

    # --------------------------------------------------------
    # Engulfing
    # --------------------------------------------------------

    previous_open = (
        open_.shift(1)
    )

    previous_close = (
        close.shift(1)
    )

    df["bullish_engulf"] = (
        (close > open_) &
        (previous_close < previous_open) &
        (open_ <= previous_close) &
        (close >= previous_open)
    )

    df["bearish_engulf"] = (
        (close < open_) &
        (previous_close > previous_open) &
        (open_ >= previous_close) &
        (close <= previous_open)
    )

    # --------------------------------------------------------
    # Rechazo
    # --------------------------------------------------------

    df["bullish_rejection"] = (
        (lower_wick > body * 1.5) &
        (lower_wick > upper_wick)
    )

    df["bearish_rejection"] = (
        (upper_wick > body * 1.5) &
        (upper_wick > lower_wick)
    )

    # --------------------------------------------------------
    # Impulso
    # --------------------------------------------------------

    df["bullish_impulse"] = (
        (close > open_) &
        (df["body_ratio"] >= 0.60)
    )

    df["bearish_impulse"] = (
        (close < open_) &
        (df["body_ratio"] >= 0.60)
    )

    # --------------------------------------------------------
    # Pullback
    # --------------------------------------------------------

    df["bullish_pullback"] = (
        (df["ema20"] > df["ema50"]) &
        (low <= df["ema20"]) &
        (close > df["ema20"])
    )

    df["bearish_pullback"] = (
        (df["ema20"] < df["ema50"]) &
        (high >= df["ema20"]) &
        (close < df["ema20"])
    )

    # --------------------------------------------------------
    # Soporte
    # --------------------------------------------------------

    df["support"] = (
        low
        .shift(1)
        .rolling(
            20,
            min_periods=10,
        )
        .min()
    )

    # --------------------------------------------------------
    # Resistencia
    # --------------------------------------------------------

    df["resistance"] = (
        high
        .shift(1)
        .rolling(
            20,
            min_periods=10,
        )
        .max()
    )

    df["support_distance"] = (
        close -
        df["support"]
    )

    df["resistance_distance"] = (
        df["resistance"] -
        close
    )

    df["support_too_close"] = (
        df["support_distance"] <
        df["atr"] * 0.75
    )

    df["resistance_too_close"] = (
        df["resistance_distance"] <
        df["atr"] * 0.75
    )

    return df


# ============================================================
# SEÑALES
# ============================================================

def generate_signals(
    df,
):

    df = calculate_indicators(
        df
    )

    df = calculate_price_action(
        df
    )

    score = pd.Series(
        0.0,
        index=df.index,
    )

    # --------------------------------------------------------
    # EMA
    # --------------------------------------------------------

    score += np.where(
        df["ema20"] >
        df["ema50"],
        2.0,
        np.where(
            df["ema20"] <
            df["ema50"],
            -2.0,
            0.0,
        ),
    )

    # --------------------------------------------------------
    # EMA SLOPE
    # --------------------------------------------------------

    score += np.where(
        df["ema_slope"] > 0,
        1.0,
        np.where(
            df["ema_slope"] < 0,
            -1.0,
            0.0,
        ),
    )

    # --------------------------------------------------------
    # RSI
    # --------------------------------------------------------

    score += np.where(
        df["rsi"].between(
            52,
            68,
        ),
        1.0,
        np.where(
            df["rsi"].between(
                32,
                48,
            ),
            -1.0,
            0.0,
        ),
    )

    # Extremos
    score += np.where(
        df["rsi"] > 75,
        -1.0,
        np.where(
            df["rsi"] < 25,
            1.0,
            0.0,
        ),
    )

    # --------------------------------------------------------
    # MACD
    # --------------------------------------------------------

    score += np.where(
        df["macd"] >
        df["macd_signal"],
        1.0,
        np.where(
            df["macd"] <
            df["macd_signal"],
            -1.0,
            0.0,
        ),
    )

    score += np.where(
        df["macd_hist"] > 0,
        0.5,
        np.where(
            df["macd_hist"] < 0,
            -0.5,
            0.0,
        ),
    )

    # --------------------------------------------------------
    # ADX
    # --------------------------------------------------------

    score += np.where(
        (
            df["adx"] >= 20
        ) &
        (
            df["ema20"] >
            df["ema50"]
        ),
        1.0,
        0.0,
    )

    score += np.where(
        (
            df["adx"] >= 20
        ) &
        (
            df["ema20"] <
            df["ema50"]
        ),
        -1.0,
        0.0,
    )

    # --------------------------------------------------------
    # BOS
    # --------------------------------------------------------

    score += np.where(
        df["BOS_BULL"],
        2.5,
        0,
    )

    score += np.where(
        df["BOS_BEAR"],
        -2.5,
        0,
    )

    # --------------------------------------------------------
    # CHOCH
    # --------------------------------------------------------

    score += np.where(
        df["CHOCH_BULL"],
        2.0,
        0,
    )

    score += np.where(
        df["CHOCH_BEAR"],
        -2.0,
        0,
    )

    # --------------------------------------------------------
    # ENGULFING
    # --------------------------------------------------------

    score += np.where(
        df["bullish_engulf"],
        2.0,
        0,
    )

    score += np.where(
        df["bearish_engulf"],
        -2.0,
        0,
    )

    # --------------------------------------------------------
    # REJECTION
    # --------------------------------------------------------

    score += np.where(
        df["bullish_rejection"],
        1.5,
        0,
    )

    score += np.where(
        df["bearish_rejection"],
        -1.5,
        0,
    )

    # --------------------------------------------------------
    # IMPULSE
    # --------------------------------------------------------

    score += np.where(
        df["bullish_impulse"],
        1.0,
        0,
    )

    score += np.where(
        df["bearish_impulse"],
        -1.0,
        0,
    )

    # --------------------------------------------------------
    # PULLBACK
    # --------------------------------------------------------

    score += np.where(
        df["bullish_pullback"],
        1.5,
        0,
    )

    score += np.where(
        df["bearish_pullback"],
        -1.5,
        0,
    )

    # --------------------------------------------------------
    # CUERPO
    # --------------------------------------------------------

    score += np.where(
        (
            df["body_ratio"] >= 0.60
        ) &
        (
            df["bullish_candle"]
        ),
        0.75,
        0,
    )

    score += np.where(
        (
            df["body_ratio"] >= 0.60
        ) &
        (
            df["bearish_candle"]
        ),
        -0.75,
        0,
    )

    # --------------------------------------------------------
    # RESISTENCIA
    # --------------------------------------------------------

    score += np.where(
        (
            df["resistance_too_close"]
        ) &
        (
            score > 0
        ),
        -1.5,
        0,
    )

    # --------------------------------------------------------
    # SOPORTE
    # --------------------------------------------------------

    score += np.where(
        (
            df["support_too_close"]
        ) &
        (
            score < 0
        ),
        1.5,
        0,
    )

    df["score"] = score

    # ========================================================
    # SEÑALES FINALES
    # ========================================================

    bullish = (
        (df["score"] >= 7) &
        (~df["resistance_too_close"])
    )

    bearish = (
        (df["score"] <= -7) &
        (~df["support_too_close"])
    )

    df["signal"] = np.where(
        bullish,
        "ALZA",
        np.where(
            bearish,
            "BAJA",
            "",
        ),
    )

    return df


# ============================================================
# EVALUAR OPERACIONES
# ============================================================

def evaluate_operations(
    df,
    timeframe,
):

    signals = df[
        df["signal"] != ""
    ].copy()

    if signals.empty:

        return pd.DataFrame()

    # --------------------------------------------------------
    # Entrada:
    # siguiente vela del timeframe
    # --------------------------------------------------------

    signals["entry"] = (
        df["open"]
        .shift(-1)
        .loc[
            signals.index
        ]
    )

    signals["entry_time"] = (
        df["datetime"]
        .shift(-1)
        .loc[
            signals.index
        ]
    )

    # --------------------------------------------------------
    # Expiración:
    # cierre de la siguiente vela
    # --------------------------------------------------------

    signals["expiry"] = (
        df["close"]
        .shift(-1)
        .loc[
            signals.index
        ]
    )

    signals["expiry_time"] = (
        df["datetime"]
        .shift(-1)
        .loc[
            signals.index
        ]
    )

    signals = signals.dropna(
        subset=[
            "entry",
            "expiry",
        ]
    )

    if signals.empty:

        return pd.DataFrame()

    # --------------------------------------------------------
    # WIN / LOSS / TIE
    # --------------------------------------------------------

    win = (
        (
            signals["signal"] ==
            "ALZA"
        ) &
        (
            signals["expiry"] >
            signals["entry"]
        )
    ) 
    (
            (
                signals["signal"] ==
                "BAJA"
            ) &
            (
                signals["expiry"] <
                signals["entry"]
            )
        )

    tie = (
        signals["expiry"] ==
        signals["entry"]
    )

    signals["result"] = np.where(
        win,
        "WIN",
        np.where(
            tie,
            "TIE",
            "LOSS",
        ),
    )

    # --------------------------------------------------------
    # Profit
    # --------------------------------------------------------

    signals["profit"] = np.where(
        signals["result"] ==
        "WIN",
        PAYOUT,
        np.where(
            signals["result"] ==
            "LOSS",
            -1.0,
            0.0,
        ),
    )

    signals["equity"] = (
        signals["profit"]
        .cumsum()
    )

    peak = (
        signals["equity"]
        .cummax()
    )

    signals["drawdown"] = (
        signals["equity"] -
        peak
    )

    return signals[
        [
            "datetime",
            "signal",
            "score",
            "entry_time",
            "entry",
            "expiry_time",
            "expiry",
            "result",
            "profit",
            "equity",
            "drawdown",
            "ema20",
            "ema50",
            "rsi",
            "macd",
            "macd_signal",
            "adx",
            "atr",
        ]
    ].reset_index(
        drop=True
    )


# ============================================================
# ESTADÍSTICAS
# ============================================================

def calculate_statistics(
    operations,
    pair,
    timeframe,
    candles,
):

    if operations.empty:

        return {
            "pair": pair,
            "timeframe": timeframe,
            "candles": candles,
            "operations": 0,
            "wins": 0,
            "losses": 0,
            "ties": 0,
            "win_rate": 0,
            "breakeven": round(
                BREAKEVEN * 100,
                2,
            ),
            "profit": 0,
            "max_drawdown": 0,
            "max_loss_streak": 0,
            "status": "NO SIGNALS",
        }

    wins = (
        operations["result"] ==
        "WIN"
    ).sum()

    losses = (
        operations["result"] ==
        "LOSS"
    ).sum()

    ties = (
        operations["result"] ==
        "TIE"
    ).sum()

    decided = (
        wins +
        losses
    )

    if decided:

        win_rate = (
            wins /
            decided *
            100
        )

    else:

        win_rate = 0

    profit = (
        operations["profit"]
        .sum()
    )

    max_drawdown = (
        operations["drawdown"]
        .min()
    )

    # --------------------------------------------------------
    # Racha máxima de pérdidas
    # --------------------------------------------------------

    loss_bool = (
        operations["result"] ==
        "LOSS"
    ).astype(int)

    if not loss_bool.empty:

        groups = (
            loss_bool
            .groupby(
                (
                    loss_bool !=
                    loss_bool.shift()
                ).cumsum()
            )
            .sum()
        )

        max_loss_streak = int(
            groups.max()
        )

    else:

        max_loss_streak = 0

    return {
        "pair": pair,
        "timeframe": timeframe,
        "candles": candles,
        "operations": int(
            len(operations)
        ),
        "wins": int(wins),
        "losses": int(losses),
        "ties": int(ties),
        "win_rate": round(
            win_rate,
            2,
        ),
        "breakeven": round(
            BREAKEVEN * 100,
            2,
        ),
        "profit": round(
            profit,
            2,
        ),
        "max_drawdown": round(
            max_drawdown,
            2,
        ),
        "max_loss_streak": max_loss_streak,
        "status": (
            "PROFITABLE"
            if profit > 0
            else "NEGATIVE"
        ),
    }


# ============================================================
# PREPARAR 1M DE TODOS LOS PARES
# ============================================================

def prepare_base_data(
    pairs,
    target_bars,
):

    print()
    separator()

    print(
        "FASE 1/2 - PREPARANDO DATOS 1 MINUTO"
    )

    separator()

    # --------------------------------------------------------
    # Para obtener 1M de 1,000,000 y 2M de 1,000,000:
    #
    # 2M necesita aproximadamente 2,000,000 velas de 1M.
    #
    # Por eso descargamos el máximo necesario UNA VEZ.
    # --------------------------------------------------------

    required_1m = max(
        target_bars,
        target_bars * 2,
    )

    print(
        f"1M requerido por par: "
        f"{required_1m:,}"
    )

    base_data = {}

    for pair in pairs:

        df = download_1m(
            pair,
            required_1m,
        )

        base_data[pair] = df

        print()

    return base_data


# ============================================================
# PROCESAR COMBINACIÓN
# ============================================================

def process_combination(
    pair,
    timeframe,
    target_bars,
    base_df,
    save_operations=True,
):

    start = time.time()

    try:

        # ----------------------------------------------------
        # 1M
        # ----------------------------------------------------

        if timeframe == "1min":

            df = base_df.copy()

            if len(df) > target_bars:

                df = df.tail(
                    target_bars
                ).reset_index(
                    drop=True
                )

        # ----------------------------------------------------
        # 2M
        # ----------------------------------------------------

        elif timeframe == "2min":

            df = load_cache(
                pair,
                "2min",
            )

            if (
                df.empty or
                len(df) < target_bars
            ):

                df = build_2m_from_1m(
                    pair,
                    base_df,
                    target_bars,
                )

            if len(df) > target_bars:

                df = df.tail(
                    target_bars
                ).reset_index(
                    drop=True
                )

        # ----------------------------------------------------
        # RESTO
        # ----------------------------------------------------

        else:

            df = download_direct(
                pair,
                timeframe,
                target_bars,
            )

            if len(df) > target_bars:

                df = df.tail(
                    target_bars
                ).reset_index(
                    drop=True
                )

        candles = len(df)

        if candles < 100:

            print(
                f"{pair} {timeframe}: "
                f"muy pocas velas "
                f"({candles})"
            )

            return None

        print(
            f"    Calculando "
            f"{pair} {timeframe}: "
            f"{candles:,} velas"
        )

        # ----------------------------------------------------
        # Señales
        # ----------------------------------------------------

        signal_df = generate_signals(
            df
        )

        # ----------------------------------------------------
        # Operaciones
        # ----------------------------------------------------

        operations = evaluate_operations(
            signal_df,
            timeframe,
        )

        # ----------------------------------------------------
        # Guardar operaciones
        # ----------------------------------------------------

        if (
            save_operations and
            not operations.empty
        ):

            output = result_file(
                pair,
                timeframe,
            )

            operations.to_csv(
                output,
                index=False,
            )

        # ----------------------------------------------------
        # Stats
        # ----------------------------------------------------

        stats = calculate_statistics(
            operations,
            pair,
            timeframe,
            candles,
        )

        elapsed = (
            time.time() -
            start
        )

        print(
            f"    RESULTADO -> "
            f"{stats['operations']:,} ops | "
            f"W {stats['wins']:,} | "
            f"L {stats['losses']:,} | "
            f"T {stats['ties']:,} | "
            f"WR {stats['win_rate']:.2f}% | "
            f"Profit {stats['profit']:+.2f} | "
            f"{elapsed:.1f}s"
        )

        return stats

    except Exception as e:

        print()
        print(
            f"ERROR en "
            f"{pair} {timeframe}:"
        )

        print(
            repr(e)
        )

        return None


# ============================================================
# RUN
# ============================================================

def run_backtest(
    pairs,
    timeframes,
    target_bars,
    workers,
    save_operations,
):

    start_total = time.time()

    separator()

    print(
        "TRADING ANALYZER"
    )

    print(
        "BACKTEST MASIVO V6"
    )

    separator()

    print(
        f"Pares: "
        f"{len(pairs)}"
    )

    print(
        f"Temporalidades: "
        f"{len(timeframes)}"
    )

    print(
        f"Objetivo: "
        f"{target_bars:,} velas"
    )

    print(
        f"Payout: "
        f"{PAYOUT:.0%}"
    )

    print(
        f"Break-even: "
        f"{BREAKEVEN * 100:.2f}%"
    )

    print(
        f"Workers: "
        f"{workers}"
    )

    print()

    # ========================================================
    # FASE 1
    # ========================================================
    #
    # SOLO se descarga 1M una vez por par.
    #
    # Esto elimina:
    #
    # 1M -> descarga
    # 2M -> descarga 1M otra vez
    #
    # Ahora:
    #
    # 1M ─┐
    #     ├──> reutilizado
    # 2M ─┘
    #
    # ========================================================

    base_data = prepare_base_data(
        pairs,
        target_bars,
    )

    # ========================================================
    # FASE 2
    # ========================================================

    print()
    separator()

    print(
        "FASE 2/2 - BACKTEST"
    )

    separator()

    tasks = []

    for pair in pairs:

        for timeframe in timeframes:

            tasks.append(
                (
                    pair,
                    timeframe,
                )
            )

    results = []

    completed = 0

    total = len(tasks)

    # --------------------------------------------------------
    # IMPORTANTE:
    #
    # Los datos 1M ya están preparados.
    # No se descargan nuevamente.
    #
    # --------------------------------------------------------

    with ThreadPoolExecutor(
        max_workers=workers
    ) as executor:

        futures = {}

        for pair, timeframe in tasks:

            future = executor.submit(
                process_combination,
                pair,
                timeframe,
                target_bars,
                base_data[pair],
                save_operations,
            )

            futures[future] = (
                pair,
                timeframe,
            )

        for future in as_completed(
            futures
        ):

            pair, timeframe = (
                futures[future]
            )

            completed += 1

            result = future.result()

            if result:

                results.append(
                    result
                )

            print()
            print(
                f"PROGRESO: "
                f"{completed}/{total}"
            )

    # ========================================================
    # RESUMEN
    # ========================================================

    if not results:

        print()
        print(
            "No se obtuvieron resultados."
        )

        return

    summary = pd.DataFrame(
        results
    )

    summary = summary.sort_values(
        [
            "pair",
            "timeframe",
        ]
    )

    summary_file = (
        RESULTS_DIR /
        "BACKTEST_SUMMARY.csv"
    )

    summary.to_csv(
        summary_file,
        index=False,
    )

    # ========================================================
    # TABLA
    # ========================================================

    print()
    separator()

    print(
        "RESUMEN FINAL"
    )

    separator()

    columns = [
        "pair",
        "timeframe",
        "candles",
        "operations",
        "wins",
        "losses",
        "ties",
        "win_rate",
        "profit",
        "max_drawdown",
        "max_loss_streak",
    ]

    print(
        summary[
            columns
        ].to_string(
            index=False
        )
    )

    # ========================================================
    # TOTALES
    # ========================================================

    total_ops = int(
        summary[
            "operations"
        ].sum()
    )

    total_wins = int(
        summary[
            "wins"
        ].sum()
    )

    total_losses = int(
        summary[
            "losses"
        ].sum()
    )

    total_ties = int(
        summary[
            "ties"
        ].sum()
    )

    total_decided = (
        total_wins +
        total_losses
    )

    if total_decided:

        global_wr = (
            total_wins /
            total_decided *
            100
        )

    else:

        global_wr = 0

    total_profit = (
        summary[
            "profit"
        ].sum()
    )

    print()
    separator()

    print(
        "TOTALES"
    )

    separator()

    print(
        f"Operaciones: "
        f"{total_ops:,}"
    )

    print(
        f"Wins: "
        f"{total_wins:,}"
    )

    print(
        f"Losses: "
        f"{total_losses:,}"
    )

    print(
        f"Ties: "
        f"{total_ties:,}"
    )

    print(
        f"Win rate: "
        f"{global_wr:.2f}%"
    )

    print(
        f"Break-even: "
        f"{BREAKEVEN * 100:.2f}%"
    )

    print(
        f"Profit: "
        f"{total_profit:+.2f}"
    )

    elapsed_total = (
        time.time() -
        start_total
    )

    print(
        f"Tiempo total: "
        f"{elapsed_total / 60:.2f} minutos"
    )

    print()
    print(
        "Resumen:"
    )

    print(
        summary_file
    )

    separator()


# ============================================================
# ARGUMENTOS
# ============================================================

def parse_args():

    parser = argparse.ArgumentParser(
        description=(
            "Trading Analyzer "
            "Backtester V6"
        )
    )

    parser.add_argument(
        "--target-bars",
        type=int,
        default=DEFAULT_TARGET_BARS,
    )

    parser.add_argument(
        "--workers",
        type=int,
        default=2,
    )

    parser.add_argument(
        "--pairs",
        nargs="*",
        default=None,
    )

    parser.add_argument(
        "--timeframes",
        nargs="*",
        default=None,
    )

    parser.add_argument(
        "--no-save-operations",
        action="store_true",
    )

    return parser.parse_args()


# ============================================================
# MAIN
# ============================================================

def main():

    args = parse_args()

    pairs = (
        args.pairs
        if args.pairs
        else PAIRS
    )

    timeframes = (
        args.timeframes
        if args.timeframes
        else TIMEFRAMES
    )

    # --------------------------------------------------------
    # Validar pares
    # --------------------------------------------------------

    if not pairs:

        print(
            "No hay pares."
        )

        sys.exit(1)

    # --------------------------------------------------------
    # Validar temporalidades
    # --------------------------------------------------------

    for timeframe in timeframes:

        if timeframe not in TF_MINUTES:

            print(
                f"ERROR: timeframe "
                f"no válido: "
                f"{timeframe}"
            )

            print(
                "Disponibles:"
            )

            print(
                ", ".join(
                    TIMEFRAMES
                )
            )

            sys.exit(1)

    # --------------------------------------------------------
    # Validar target
    # --------------------------------------------------------

    if args.target_bars <= 0:

        print(
            "target-bars debe ser > 0"
        )

        sys.exit(1)

    # --------------------------------------------------------
    # Validar workers
    # --------------------------------------------------------

    if args.workers <= 0:

        print(
            "workers debe ser > 0"
        )

        sys.exit(1)

    run_backtest(
        pairs=pairs,
        timeframes=timeframes,
        target_bars=args.target_bars,
        workers=args.workers,
        save_operations=(
            not args.no_save_operations
        ),
    )


# ============================================================
# START
# ============================================================

if __name__ == "__main__":

    main()