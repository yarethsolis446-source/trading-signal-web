# ================================================================
# TRADING ANALYZER - BACKTEST MASIVO
# Versión 4.1 - TWELVE DATA + DOTENV + AUTH HEADER
# ================================================================

import os
import sys
import time
import math
import argparse
from pathlib import Path
from datetime import datetime, timedelta, timezone

import requests
import pandas as pd
import numpy as np
from dotenv import load_dotenv


# ================================================================
# CARGAR .ENV
# ================================================================

load_dotenv(override=True)


# ================================================================
# CONFIGURACIÓN
# ================================================================

BASE_URL = "https://api.twelvedata.com/time_series"

DATA_DIR = Path("twelve_data_cache")
RESULTS_DIR = Path("backtest_results")

PAYOUT = 0.90

API_CHUNK = 5000

REQUEST_DELAY = 0.8

MAX_RETRIES = 5

WARMUP = 300


TIMEFRAMES = {
    "1m": 1,
    "2m": 2,
    "5m": 5,
    "15m": 15,
    "30m": 30,
    "1h": 60,
}


DEFAULT_PAIRS = [
    "EURUSD",
    "GBPUSD",
    "USDJPY",
    "USDCHF",
    "AUDUSD",
    "USDCAD",
    "NZDUSD",
]


# ================================================================
# UTILIDADES
# ================================================================

def print_line(char="=", n=90):
    print(char * n)


def normalize_symbol(symbol):
    symbol = symbol.upper().replace("/", "").replace("-", "")

    if len(symbol) != 6:
        raise ValueError(
            f"Símbolo inválido: {symbol}. Ejemplo: EURUSD"
        )

    return symbol[:3] + "/" + symbol[3:]


def safe_float(value):
    try:
        return float(value)
    except Exception:
        return np.nan


def utc_now():
    return datetime.now(timezone.utc)


def dt_to_api(dt):
    return dt.astimezone(timezone.utc).strftime(
        "%Y-%m-%d %H:%M:%S"
    )


def sleep_if_needed():
    time.sleep(REQUEST_DELAY)


# ================================================================
# TWELVE DATA CLIENT
# ================================================================

class TwelveDataClient:

    def __init__(self, api_key):

        self.api_key = api_key.strip() if api_key else ""

        if not self.api_key:
            raise RuntimeError(
                "\nNo se encontró TWELVE_DATA_API_KEY.\n\n"
                "Comprueba que exista el archivo .env:\n\n"
                "TWELVE_DATA_API_KEY=TU_API_KEY\n"
            )

        self.session = requests.Session()

        self.headers = {
            "Authorization": f"apikey {self.api_key}",
            "User-Agent": "TradingAnalyzer-Backtest/4.1",
        }

    # ------------------------------------------------------------
    # REQUEST
    # ------------------------------------------------------------

    def request(self, params):

        params = dict(params)

        last_error = None

        for attempt in range(1, MAX_RETRIES + 1):

            try:

                response = self.session.get(
                    BASE_URL,
                    params=params,
                    headers=self.headers,
                    timeout=45,
                )

                if response.status_code != 200:

                    last_error = (
                        f"HTTP {response.status_code}: "
                        f"{response.text[:500]}"
                    )

                    if response.status_code in (
                        429,
                        500,
                        502,
                        503,
                        504,
                    ):

                        wait = min(
                            10 * attempt,
                            60,
                        )

                        print(
                            f"\n  ⚠ Servidor/rate limit."
                            f" Reintentando en {wait}s..."
                        )

                        time.sleep(wait)

                        continue

                    raise RuntimeError(last_error)

                data = response.json()

                if isinstance(data, dict):

                    if data.get("status") == "error":

                        message = data.get(
                            "message",
                            "Error desconocido",
                        )

                        code = data.get(
                            "code",
                            "",
                        )

                        last_error = (
                            f"Twelve Data error "
                            f"{code}: {message}"
                        )

                        message_lower = message.lower()

                        temporary = any(
                            x in message_lower
                            for x in [
                                "rate",
                                "limit",
                                "too many",
                                "credits",
                                "quota",
                            ]
                        )

                        if temporary:

                            wait = min(
                                10 * attempt,
                                60,
                            )

                            print(
                                f"\n  ⚠ {message}"
                            )

                            print(
                                f"  Reintentando en {wait}s..."
                            )

                            time.sleep(wait)

                            continue

                        raise RuntimeError(
                            last_error
                        )

                return data

            except requests.RequestException as exc:

                last_error = str(exc)

                wait = min(
                    5 * attempt,
                    30,
                )

                print(
                    f"\n  ⚠ Error de conexión: {exc}"
                )

                print(
                    f"  Reintentando en {wait}s..."
                )

                time.sleep(wait)

        raise RuntimeError(
            f"No se pudo completar la petición "
            f"después de {MAX_RETRIES} intentos.\n"
            f"{last_error}"
        )

    # ------------------------------------------------------------
    # TEST DE API
    # ------------------------------------------------------------

    def test_connection(self):

        params = {
            "symbol": "EUR/USD",
        }

        data = self.request_price(params)

        return data

    def request_price(self, params):

        url = "https://api.twelvedata.com/price"

        response = self.session.get(
            url,
            params=params,
            headers=self.headers,
            timeout=30,
        )

        if response.status_code != 200:

            raise RuntimeError(
                f"HTTP {response.status_code}: "
                f"{response.text[:500]}"
            )

        data = response.json()

        if isinstance(data, dict):

            if data.get("status") == "error":

                raise RuntimeError(
                    data.get(
                        "message",
                        "Error de Twelve Data",
                    )
                )

        return data

    # ------------------------------------------------------------
    # CHUNK 1M
    # ------------------------------------------------------------

    def get_1m_chunk(
        self,
        symbol,
        end_dt,
    ):

        params = {
            "symbol": normalize_symbol(symbol),
            "interval": "1min",
            "outputsize": API_CHUNK,
            "end_date": dt_to_api(end_dt),
            "timezone": "UTC",
        }

        data = self.request(params)

        values = data.get(
            "values",
            [],
        )

        if not values:
            return pd.DataFrame()

        rows = []

        for item in values:

            rows.append(
                {
                    "datetime": item.get(
                        "datetime"
                    ),
                    "open": safe_float(
                        item.get("open")
                    ),
                    "high": safe_float(
                        item.get("high")
                    ),
                    "low": safe_float(
                        item.get("low")
                    ),
                    "close": safe_float(
                        item.get("close")
                    ),
                    "volume": safe_float(
                        item.get("volume")
                    ),
                }
            )

        df = pd.DataFrame(rows)

        if df.empty:
            return df

        df["datetime"] = pd.to_datetime(
            df["datetime"],
            utc=True,
            errors="coerce",
        )

        df = df.dropna(
            subset=["datetime"]
        )

        for col in [
            "open",
            "high",
            "low",
            "close",
            "volume",
        ]:

            df[col] = pd.to_numeric(
                df[col],
                errors="coerce",
            )

        df = df.dropna(
            subset=[
                "open",
                "high",
                "low",
                "close",
            ]
        )

        df = df.sort_values(
            "datetime"
        )

        df = df.drop_duplicates(
            subset=["datetime"],
            keep="last",
        )

        return df.reset_index(
            drop=True
        )


# ================================================================
# DESCARGA HISTÓRICA
# ================================================================

def download_1m_history(
    client,
    symbol,
    required_bars,
    force=False,
):

    DATA_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    symbol_clean = (
        symbol
        .replace("/", "")
        .upper()
    )

    cache_file = (
        DATA_DIR
        / f"{symbol_clean}_1m.csv"
    )

    print()
    print("=" * 80)
    print(
        f"DESCARGANDO HISTÓRICO 1M: {symbol}"
    )
    print("=" * 80)

    cached = pd.DataFrame()

    # ------------------------------------------------------------
    # CACHE
    # ------------------------------------------------------------

    if cache_file.exists() and not force:

        print(
            f"Cache encontrado: {cache_file}"
        )

        try:

            cached = pd.read_csv(
                cache_file,
                parse_dates=[
                    "datetime"
                ],
            )

            cached["datetime"] = (
                pd.to_datetime(
                    cached["datetime"],
                    utc=True,
                    errors="coerce",
                )
            )

            cached = cached.dropna(
                subset=["datetime"]
            )

            cached = (
                cached
                .sort_values("datetime")
                .drop_duplicates(
                    subset=["datetime"]
                )
                .reset_index(drop=True)
            )

            print(
                f"Velas en cache: "
                f"{len(cached):,}"
            )

        except Exception as exc:

            print(
                f"⚠ Cache inválido: {exc}"
            )

            cached = pd.DataFrame()

    # ------------------------------------------------------------
    # CACHE SUFICIENTE
    # ------------------------------------------------------------

    if len(cached) >= required_bars:

        print(
            f"✓ Cache suficiente: "
            f"{len(cached):,} velas"
        )

        return (
            cached
            .tail(required_bars)
            .reset_index(drop=True)
        )

    # ------------------------------------------------------------
    # PUNTO INICIAL
    # ------------------------------------------------------------

    if not cached.empty:

        oldest_cached = (
            cached["datetime"].min()
        )

        end_dt = (
            oldest_cached
            - timedelta(minutes=1)
        )

        all_parts = [cached]

        print(
            "Continuando desde el cache..."
        )

    else:

        end_dt = utc_now()

        all_parts = []

        print(
            "No existe cache. "
            "Descarga desde el presente "
            "hacia atrás."
        )

    needed = (
        required_bars
        - len(cached)
    )

    chunks_needed = math.ceil(
        needed / API_CHUNK
    )

    print(
        f"Objetivo total: "
        f"{required_bars:,} velas"
    )

    print(
        f"Faltan aproximadamente: "
        f"{needed:,}"
    )

    print(
        f"Requests aproximados: "
        f"{chunks_needed:,}"
    )

    print()

    downloaded = len(cached)

    request_number = 0

    while downloaded < required_bars:

        request_number += 1

        print(
            f"[{request_number}] "
            f"Descargando hasta "
            f"{end_dt.strftime('%Y-%m-%d %H:%M')} UTC..."
        )

        df = client.get_1m_chunk(
            symbol,
            end_dt,
        )

        sleep_if_needed()

        if df.empty:

            print(
                "\n⚠ Twelve Data "
                "no devolvió más datos."
            )

            break

        print(
            f"    Recibidas: "
            f"{len(df):,}"
        )

        oldest = df["datetime"].min()

        newest = df["datetime"].max()

        print(
            f"    Rango: "
            f"{oldest} -> {newest}"
        )

        all_parts.append(df)

        combined_temp = pd.concat(
            all_parts,
            ignore_index=True,
        )

        combined_temp = (
            combined_temp
            .drop_duplicates(
                subset=["datetime"],
                keep="last",
            )
        )

        combined_temp = (
            combined_temp
            .sort_values("datetime")
            .reset_index(drop=True)
        )

        downloaded = len(
            combined_temp
        )

        print(
            f"    Total acumulado: "
            f"{downloaded:,}/"
            f"{required_bars:,}"
        )

        # --------------------------------------------------------
        # SEGURIDAD CONTRA LOOP
        # --------------------------------------------------------

        if oldest >= end_dt:

            print(
                "⚠ La API no retrocedió. "
                "Se detiene."
            )

            break

        end_dt = (
            oldest
            - timedelta(minutes=1)
        )

        # --------------------------------------------------------
        # CACHE PARCIAL
        # --------------------------------------------------------

        try:

            combined_temp.to_csv(
                cache_file,
                index=False,
            )

            print(
                "    ✓ Cache actualizado"
            )

        except Exception as exc:

            print(
                f"    ⚠ No se pudo guardar "
                f"cache: {exc}"
            )

        print()

    # ------------------------------------------------------------
    # COMBINAR
    # ------------------------------------------------------------

    if not all_parts:

        raise RuntimeError(
            f"No se pudieron descargar "
            f"datos para {symbol}."
        )

    df = pd.concat(
        all_parts,
        ignore_index=True,
    )

    df = (
        df
        .drop_duplicates(
            subset=["datetime"],
            keep="last",
        )
        .sort_values("datetime")
        .reset_index(drop=True)
    )

    # ------------------------------------------------------------
    # GUARDAR
    # ------------------------------------------------------------

    df.to_csv(
        cache_file,
        index=False,
    )

    print()
    print(
        f"✓ HISTÓRICO FINAL: "
        f"{len(df):,} velas 1M"
    )

    print(
        f"Primer dato: "
        f"{df['datetime'].min()}"
    )

    print(
        f"Último dato:  "
        f"{df['datetime'].max()}"
    )

    if len(df) < required_bars:

        print()

        print(
            f"⚠ ATENCIÓN: se solicitaron "
            f"{required_bars:,} velas, "
            f"pero solo hay "
            f"{len(df):,}."
        )

    return (
        df
        .tail(required_bars)
        .reset_index(drop=True)
    )


# ================================================================
# AGREGACIÓN
# ================================================================

def aggregate_minutes(
    df,
    minutes,
):

    if minutes == 1:

        return (
            df.copy()
            .reset_index(drop=True)
        )

    x = df.copy()

    x = x.set_index(
        "datetime"
    )

    rule = f"{minutes}min"

    agg = (
        x.resample(
            rule,
            label="left",
            closed="left",
        )
        .agg(
            {
                "open": "first",
                "high": "max",
                "low": "min",
                "close": "last",
                "volume": "sum",
            }
        )
        .dropna(
            subset=[
                "open",
                "high",
                "low",
                "close",
            ]
        )
        .reset_index()
    )

    return agg


# ================================================================
# INDICADORES
# ================================================================

def ema(
    series,
    period,
):

    return series.ewm(
        span=period,
        adjust=False,
        min_periods=period,
    ).mean()


def rma(
    series,
    period,
):

    return series.ewm(
        alpha=1 / period,
        adjust=False,
        min_periods=period,
    ).mean()


def rsi(
    series,
    period=14,
):

    delta = series.diff()

    gain = delta.clip(
        lower=0
    )

    loss = -delta.clip(
        upper=0
    )

    avg_gain = rma(
        gain,
        period,
    )

    avg_loss = rma(
        loss,
        period,
    )

    rs = (
        avg_gain
        / avg_loss.replace(
            0,
            np.nan,
        )
    )

    result = (
        100
        - (
            100
            / (1 + rs)
        )
    )

    result = result.where(
        avg_loss != 0,
        100,
    )

    result = result.where(
        avg_gain != 0,
        0,
    )

    both_zero = (
        (avg_gain == 0)
        & (avg_loss == 0)
    )

    result = result.where(
        ~both_zero,
        50,
    )

    return result


def macd(series):

    fast = ema(
        series,
        12,
    )

    slow = ema(
        series,
        26,
    )

    macd_line = (
        fast - slow
    )

    signal = ema(
        macd_line,
        9,
    )

    histogram = (
        macd_line - signal
    )

    return (
        macd_line,
        signal,
        histogram,
    )


def atr(
    df,
    period=14,
):

    high = df["high"]

    low = df["low"]

    close = df["close"]

    previous_close = close.shift(1)

    tr1 = high - low

    tr2 = (
        high - previous_close
    ).abs()

    tr3 = (
        low - previous_close
    ).abs()

    tr = pd.concat(
        [
            tr1,
            tr2,
            tr3,
        ],
        axis=1,
    ).max(axis=1)

    return rma(
        tr,
        period,
    )


def adx(
    df,
    period=14,
):

    high = df["high"]

    low = df["low"]

    close = df["close"]

    up_move = high.diff()

    down_move = -low.diff()

    plus_dm = pd.Series(
        np.where(
            (
                (up_move > down_move)
                & (up_move > 0)
            ),
            up_move,
            0.0,
        ),
        index=df.index,
    )

    minus_dm = pd.Series(
        np.where(
            (
                (down_move > up_move)
                & (down_move > 0)
            ),
            down_move,
            0.0,
        ),
        index=df.index,
    )

    prev_close = close.shift(1)

    tr = pd.concat(
        [
            high - low,
            (
                high - prev_close
            ).abs(),
            (
                low - prev_close
            ).abs(),
        ],
        axis=1,
    ).max(axis=1)

    atr_value = rma(
        tr,
        period,
    )

    plus_di = (
        100
        * rma(
            plus_dm,
            period,
        )
        / atr_value
    )

    minus_di = (
        100
        * rma(
            minus_dm,
            period,
        )
        / atr_value
    )

    denominator = (
        plus_di + minus_di
    ).replace(
        0,
        np.nan,
    )

    dx = (
        100
        * (
            plus_di
            - minus_di
        ).abs()
        / denominator
    )

    return rma(
        dx,
        period,
    )


# ================================================================
# INDICADORES COMPLETOS
# ================================================================

def calculate_indicators(df):

    df = df.copy()

    close = df["close"]

    df["ema20"] = ema(
        close,
        20,
    )

    df["ema50"] = ema(
        close,
        50,
    )

    df["ema20_prev"] = (
        df["ema20"].shift(3)
    )

    df["ema_slope"] = (
        df["ema20"]
        - df["ema20_prev"]
    )

    df["rsi"] = rsi(
        close,
        14,
    )

    (
        df["macd"],
        df["macd_signal"],
        df["macd_hist"],
    ) = macd(close)

    df["adx"] = adx(
        df,
        14,
    )

    df["atr"] = atr(
        df,
        14,
    )

    return df


# ================================================================
# PRICE ACTION
# ================================================================

def candle_body_ratio(row):

    candle_range = (
        row["high"]
        - row["low"]
    )

    if candle_range <= 0:

        return 0.0

    return abs(
        row["close"]
        - row["open"]
    ) / candle_range


def is_bullish(row):

    return (
        row["close"]
        > row["open"]
    )


def is_bearish(row):

    return (
        row["close"]
        < row["open"]
    )


def bullish_engulfing(
    prev,
    cur,
):

    return (
        is_bearish(prev)
        and is_bullish(cur)
        and cur["open"]
        <= prev["close"]
        and cur["close"]
        >= prev["open"]
    )


def bearish_engulfing(
    prev,
    cur,
):

    return (
        is_bullish(prev)
        and is_bearish(cur)
        and cur["open"]
        >= prev["close"]
        and cur["close"]
        <= prev["open"]
    )


def bullish_rejection(row):

    body = abs(
        row["close"]
        - row["open"]
    )

    lower_wick = (
        min(
            row["open"],
            row["close"],
        )
        - row["low"]
    )

    upper_wick = (
        row["high"]
        - max(
            row["open"],
            row["close"],
        )
    )

    return (
        lower_wick > body * 1.5
        and lower_wick > upper_wick
    )


def bearish_rejection(row):

    body = abs(
        row["close"]
        - row["open"]
    )

    upper_wick = (
        row["high"]
        - max(
            row["open"],
            row["close"],
        )
    )

    lower_wick = (
        min(
            row["open"],
            row["close"],
        )
        - row["low"]
    )

    return (
        upper_wick > body * 1.5
        and upper_wick > lower_wick
    )


# ================================================================
# ESTRUCTURA
# ================================================================

def calculate_structure(df):

    df = df.copy()

    n = len(df)

    structure = [
        "NEUTRAL"
    ] * n

    bos = [
        False
    ] * n

    choch = [
        False
    ] * n

    swing_high = np.full(
        n,
        np.nan,
    )

    swing_low = np.full(
        n,
        np.nan,
    )

    # ------------------------------------------------------------
    # SWINGS
    # ------------------------------------------------------------

    for i in range(
        2,
        n - 2,
    ):

        h = df["high"].iloc[i]

        l = df["low"].iloc[i]

        left_h = max(
            df["high"].iloc[i - 2],
            df["high"].iloc[i - 1],
        )

        right_h = max(
            df["high"].iloc[i + 1],
            df["high"].iloc[i + 2],
        )

        left_l = min(
            df["low"].iloc[i - 2],
            df["low"].iloc[i - 1],
        )

        right_l = min(
            df["low"].iloc[i + 1],
            df["low"].iloc[i + 2],
        )

        if (
            h > left_h
            and h > right_h
        ):

            swing_high[i] = h

        if (
            l < left_l
            and l < right_l
        ):

            swing_low[i] = l

    # ------------------------------------------------------------
    # ESTRUCTURA
    # ------------------------------------------------------------

    last_high = np.nan

    last_low = np.nan

    previous_structure = "NEUTRAL"

    for i in range(n):

        if not np.isnan(
            swing_high[i]
        ):

            last_high = (
                swing_high[i]
            )

        if not np.isnan(
            swing_low[i]
        ):

            last_low = (
                swing_low[i]
            )

        close = (
            df["close"].iloc[i]
        )

        if (
            not np.isnan(last_high)
            and not np.isnan(last_low)
        ):

            if close > last_high:

                structure[i] = "BULLISH"

                bos[i] = True

                if (
                    previous_structure
                    == "BEARISH"
                ):

                    choch[i] = True

            elif close < last_low:

                structure[i] = "BEARISH"

                bos[i] = True

                if (
                    previous_structure
                    == "BULLISH"
                ):

                    choch[i] = True

            else:

                structure[i] = (
                    previous_structure
                )

        previous_structure = (
            structure[i]
        )

    df["structure"] = structure

    df["bos"] = bos

    df["choch"] = choch

    return df


# ================================================================
# PRICE ACTION COMPLETO
# ================================================================

def calculate_price_action(df):

    df = calculate_structure(df)

    n = len(df)

    df["engulfing"] = False
    df["rejection"] = False
    df["impulse"] = False
    df["pullback"] = False
    df["body_ratio"] = 0.0

    body_col = df.columns.get_loc(
        "body_ratio"
    )

    engulf_col = df.columns.get_loc(
        "engulfing"
    )

    rejection_col = df.columns.get_loc(
        "rejection"
    )

    impulse_col = df.columns.get_loc(
        "impulse"
    )

    pullback_col = df.columns.get_loc(
        "pullback"
    )

    for i in range(
        1,
        n,
    ):

        prev = df.iloc[
            i - 1
        ]

        cur = df.iloc[i]

        ratio = candle_body_ratio(
            cur
        )

        engulf = (
            bullish_engulfing(
                prev,
                cur,
            )
            or bearish_engulfing(
                prev,
                cur,
            )
        )

        rejection = (
            bullish_rejection(cur)
            or bearish_rejection(cur)
        )

        impulse = False

        if not pd.isna(
            cur["atr"]
        ):

            candle_range = (
                cur["high"]
                - cur["low"]
            )

            impulse = (
                ratio >= 0.60
                and candle_range
                >= cur["atr"] * 1.0
            )

        # --------------------------------------------------------
        # PULLBACK
        # --------------------------------------------------------

        pullback = False

        if (
            not pd.isna(
                cur["ema20"]
            )
            and not pd.isna(
                cur["atr"]
            )
            and cur["atr"] > 0
        ):

            distance = abs(
                cur["close"]
                - cur["ema20"]
            )

            near_ema = (
                distance
                <= cur["atr"] * 0.50
            )

            bullish_pb = (
                cur["structure"]
                == "BULLISH"
                and is_bullish(cur)
            )

            bearish_pb = (
                cur["structure"]
                == "BEARISH"
                and is_bearish(cur)
            )

            pullback = (
                near_ema
                and (
                    bullish_pb
                    or bearish_pb
                )
            )

        df.iloc[
            i,
            body_col,
        ] = ratio

        df.iloc[
            i,
            engulf_col,
        ] = engulf

        df.iloc[
            i,
            rejection_col,
        ] = rejection

        df.iloc[
            i,
            impulse_col,
        ] = impulse

        df.iloc[
            i,
            pullback_col,
        ] = pullback

    return df


# ================================================================
# SOPORTE / RESISTENCIA
# ================================================================

def nearest_levels(
    df,
    index,
):

    row = df.iloc[index]

    price = row["close"]

    atr_value = row["atr"]

    if (
        pd.isna(atr_value)
        or atr_value <= 0
    ):

        return (
            np.nan,
            np.nan,
        )

    start = max(
        0,
        index - 100,
    )

    history = df.iloc[
        start:index
    ]

    if history.empty:

        return (
            np.nan,
            np.nan,
        )

    resistance = (
        history["high"].max()
    )

    support = (
        history["low"].min()
    )

    return (
        support,
        resistance,
    )


# ================================================================
# GENERADOR DE SEÑAL
# ================================================================

def generate_signal(
    df,
    i,
):

    if i < 60:

        return None

    row = df.iloc[i]

    required = [
        "ema20",
        "ema50",
        "rsi",
        "macd",
        "macd_signal",
        "macd_hist",
        "adx",
        "atr",
    ]

    for col in required:

        if pd.isna(row[col]):

            return None

    bull_score = 0.0

    bear_score = 0.0

    reasons_bull = []

    reasons_bear = []

    # ------------------------------------------------------------
    # EMA TREND
    # ------------------------------------------------------------

    if row["ema20"] > row["ema50"]:

        bull_score += 2

        reasons_bull.append(
            "EMA20 > EMA50"
        )

    elif row["ema20"] < row["ema50"]:

        bear_score += 2

        reasons_bear.append(
            "EMA20 < EMA50"
        )

    # ------------------------------------------------------------
    # EMA SLOPE
    # ------------------------------------------------------------

    if row["ema_slope"] > 0:

        bull_score += 1

        reasons_bull.append(
            "Pendiente EMA20 alcista"
        )

    elif row["ema_slope"] < 0:

        bear_score += 1

        reasons_bear.append(
            "Pendiente EMA20 bajista"
        )

    # ------------------------------------------------------------
    # RSI
    # ------------------------------------------------------------

    r = row["rsi"]

    if 52 <= r <= 68:

        bull_score += 1

        reasons_bull.append(
            f"RSI alcista ({r:.1f})"
        )

    elif 32 <= r <= 48:

        bear_score += 1

        reasons_bear.append(
            f"RSI bajista ({r:.1f})"
        )

    if r > 75:

        bull_score -= 0.75

    if r < 25:

        bear_score -= 0.75

    # ------------------------------------------------------------
    # MACD
    # ------------------------------------------------------------

    if (
        row["macd"]
        > row["macd_signal"]
    ):

        bull_score += 1

        reasons_bull.append(
            "MACD alcista"
        )

    elif (
        row["macd"]
        < row["macd_signal"]
    ):

        bear_score += 1

        reasons_bear.append(
            "MACD bajista"
        )

    if row["macd_hist"] > 0:

        bull_score += 0.5

    elif row["macd_hist"] < 0:

        bear_score += 0.5

    # ------------------------------------------------------------
    # ADX
    # ------------------------------------------------------------

    adx_value = row["adx"]

    if adx_value >= 20:

        if bull_score > bear_score:

            bull_score += 1

            reasons_bull.append(
                f"ADX fuerte ({adx_value:.1f})"
            )

        elif bear_score > bull_score:

            bear_score += 1

            reasons_bear.append(
                f"ADX fuerte ({adx_value:.1f})"
            )

    else:

        bull_score -= 0.25

        bear_score -= 0.25

    # ------------------------------------------------------------
    # ESTRUCTURA
    # ------------------------------------------------------------

    structure = row["structure"]

    if structure == "BULLISH":

        bull_score += 2

        reasons_bull.append(
            "Estructura HH + HL"
        )

    elif structure == "BEARISH":

        bear_score += 2

        reasons_bear.append(
            "Estructura LH + LL"
        )

    # ------------------------------------------------------------
    # BOS
    # ------------------------------------------------------------

    if bool(row["bos"]):

        if structure == "BULLISH":

            bull_score += 2.5

            reasons_bull.append(
                "BOS alcista"
            )

        elif structure == "BEARISH":

            bear_score += 2.5

            reasons_bear.append(
                "BOS bajista"
            )

    # ------------------------------------------------------------
    # CHOCH
    # ------------------------------------------------------------

    if bool(row["choch"]):

        if structure == "BULLISH":

            bull_score += 2

            reasons_bull.append(
                "CHOCH alcista"
            )

        elif structure == "BEARISH":

            bear_score += 2

            reasons_bear.append(
                "CHOCH bajista"
            )

    # ------------------------------------------------------------
    # ENGULFING
    # ------------------------------------------------------------

    if bool(row["engulfing"]):

        if is_bullish(row):

            bull_score += 2

            reasons_bull.append(
                "Engulfing alcista"
            )

        elif is_bearish(row):

            bear_score += 2

            reasons_bear.append(
                "Engulfing bajista"
            )

    # ------------------------------------------------------------
    # RECHAZO
    # ------------------------------------------------------------

    if bool(row["rejection"]):

        if is_bullish(row):

            bull_score += 1.5

            reasons_bull.append(
                "Rechazo alcista"
            )

        elif is_bearish(row):

            bear_score += 1.5

            reasons_bear.append(
                "Rechazo bajista"
            )

    # ------------------------------------------------------------
    # IMPULSO
    # ------------------------------------------------------------

    if bool(row["impulse"]):

        if is_bullish(row):

            bull_score += 1

            reasons_bull.append(
                "Impulso alcista"
            )

        elif is_bearish(row):

            bear_score += 1

            reasons_bear.append(
                "Impulso bajista"
            )

    # ------------------------------------------------------------
    # PULLBACK
    # ------------------------------------------------------------

    if bool(row["pullback"]):

        if structure == "BULLISH":

            bull_score += 1.5

            reasons_bull.append(
                "Pullback alcista"
            )

        elif structure == "BEARISH":

            bear_score += 1.5

            reasons_bear.append(
                "Pullback bajista"
            )

    # ------------------------------------------------------------
    # SOPORTE / RESISTENCIA
    # ------------------------------------------------------------

    support, resistance = nearest_levels(
        df,
        i,
    )

    support_too_close = False

    resistance_too_close = False

    if not pd.isna(support):

        support_too_close = (
            abs(
                row["close"]
                - support
            )
            < row["atr"] * 0.75
        )

    if not pd.isna(resistance):

        resistance_too_close = (
            abs(
                resistance
                - row["close"]
            )
            < row["atr"] * 0.75
        )

    if support_too_close:

        bull_score -= 1

    if resistance_too_close:

        bear_score -= 1

    # ------------------------------------------------------------
    # CUERPO DE VELA
    # ------------------------------------------------------------

    body_ratio = row[
        "body_ratio"
    ]

    if body_ratio >= 0.60:

        if is_bullish(row):

            bull_score += 0.75

            reasons_bull.append(
                "Cuerpo de vela fuerte"
            )

        elif is_bearish(row):

            bear_score += 0.75

            reasons_bear.append(
                "Cuerpo de vela fuerte"
            )

    # ------------------------------------------------------------
    # CONFLICTO
    # ------------------------------------------------------------

    trend_bull = (
        row["ema20"]
        > row["ema50"]
    )

    trend_bear = (
        row["ema20"]
        < row["ema50"]
    )

    conflict_bull = (
        trend_bear
        and structure == "BULLISH"
        and bull_score < 8
    )

    conflict_bear = (
        trend_bull
        and structure == "BEARISH"
        and bear_score < 8
    )

    if conflict_bull:

        bull_score -= 2

    if conflict_bear:

        bear_score -= 2

    # ------------------------------------------------------------
    # DECISIÓN
    # ------------------------------------------------------------

    difference = (
        bull_score
        - bear_score
    )

    action = "ESPERAR"

    direction = ""

    reasons = []

    if (
        bull_score >= 7
        and difference >= 2
        and not resistance_too_close
        and not conflict_bull
    ):

        action = "ALZA"

        direction = "CALL"

        reasons = reasons_bull

    elif (
        bear_score >= 7
        and difference <= -2
        and not support_too_close
        and not conflict_bear
    ):

        action = "BAJA"

        direction = "PUT"

        reasons = reasons_bear

    else:

        if (
            bull_score
            >= bear_score
        ):

            reasons = reasons_bull

        else:

            reasons = reasons_bear

    confidence = (
        max(
            bull_score,
            bear_score,
        )
        / 12.0
        * 100
    )

    confidence = max(
        0,
        min(
            100,
            confidence,
        ),
    )

    return {
        "action": action,
        "direction": direction,
        "bull_score": bull_score,
        "bear_score": bear_score,
        "difference": difference,
        "confidence": confidence,
        "reasons": " | ".join(
            reasons[:8]
        ),
        "price": row["close"],
        "ema20": row["ema20"],
        "ema50": row["ema50"],
        "rsi": row["rsi"],
        "macd": row["macd"],
        "macd_signal": row[
            "macd_signal"
        ],
        "adx": row["adx"],
        "atr": row["atr"],
        "structure": structure,
        "bos": bool(row["bos"]),
        "choch": bool(row["choch"]),
        "engulfing": bool(
            row["engulfing"]
        ),
        "rejection": bool(
            row["rejection"]
        ),
        "impulse": bool(
            row["impulse"]
        ),
        "pullback": bool(
            row["pullback"]
        ),
        "support": support,
        "resistance": resistance,
        "support_too_close": (
            support_too_close
        ),
        "resistance_too_close": (
            resistance_too_close
        ),
    }


# ================================================================
# BACKTEST
# ================================================================

def run_backtest(
    base_1m,
    timeframe_name,
    max_bars,
    payout=PAYOUT,
):

    minutes = TIMEFRAMES[
        timeframe_name
    ]

    print()
    print("-" * 80)
    print(
        f"BACKTEST {timeframe_name}"
    )
    print("-" * 80)

    # ------------------------------------------------------------
    # AGREGAR
    # ------------------------------------------------------------

    tf = aggregate_minutes(
        base_1m,
        minutes,
    )

    if len(tf) < 100:

        print(
            f"⚠ No hay suficientes "
            f"velas para {timeframe_name}"
        )

        return None

    # ------------------------------------------------------------
    # INDICADORES
    # ------------------------------------------------------------

    print(
        f"Calculando indicadores "
        f"({len(tf):,} velas)..."
    )

    tf = calculate_indicators(
        tf
    )

    tf = calculate_price_action(
        tf
    )

    # ------------------------------------------------------------
    # DATOS 1M
    # ------------------------------------------------------------

    one_minute = (
        base_1m.copy()
        .set_index("datetime")
        .sort_index()
    )

    # ------------------------------------------------------------
    # RANGO
    # ------------------------------------------------------------

    valid_start = 60

    if len(tf) <= (
        valid_start + 1
    ):

        return None

    end_index = (
        len(tf) - 1
    )

    start_index = max(
        valid_start,
        end_index - max_bars,
    )

    trades = []

    checked = 0

    signals = 0

    wins = 0

    losses = 0

    ties = 0

    # ------------------------------------------------------------
    # RECORRER
    # ------------------------------------------------------------

    for i in range(
        start_index,
        end_index,
    ):

        checked += 1

        signal = generate_signal(
            tf,
            i,
        )

        if signal is None:
            continue

        if (
            signal["action"]
            == "ESPERAR"
        ):

            continue

        signals += 1

        analysis_time = (
            tf["datetime"].iloc[i]
        )

        # --------------------------------------------------------
        # ENTRADA
        #
        # La señal se genera después
        # del cierre del timeframe.
        #
        # Entrada = siguiente apertura 1M.
        # --------------------------------------------------------

        entry_time = (
            analysis_time
            + pd.Timedelta(
                minutes=minutes
            )
        )

        if (
            entry_time
            not in one_minute.index
        ):

            future_entries = (
                one_minute.loc[
                    one_minute.index
                    >= entry_time
                ]
            )

            if future_entries.empty:

                continue

            entry_time = (
                future_entries
                .index[0]
            )

        entry_row = (
            one_minute.loc[
                entry_time
            ]
        )

        entry_price = float(
            entry_row["open"]
        )

        # --------------------------------------------------------
        # EXPIRACIÓN
        #
        # 5M:
        #
        # Entrada 10:05
        # Expira 10:09 cierre 1M
        #
        # 15M:
        # Entrada 10:15
        # Expira 10:29 cierre 1M
        # --------------------------------------------------------

        expiry_time = (
            entry_time
            + pd.Timedelta(
                minutes=minutes - 1
            )
        )

        future_expiry = (
            one_minute.loc[
                one_minute.index
                >= expiry_time
            ]
        )

        if future_expiry.empty:

            continue

        actual_expiry_time = (
            future_expiry.index[0]
        )

        expiry_price = float(
            future_expiry.iloc[0][
                "close"
            ]
        )

        direction = signal[
            "direction"
        ]

        # --------------------------------------------------------
        # RESULTADO
        # --------------------------------------------------------

        if direction == "CALL":

            if (
                expiry_price
                > entry_price
            ):

                result = "WIN"

            elif (
                expiry_price
                < entry_price
            ):

                result = "LOSS"

            else:

                result = "TIE"

        else:

            if (
                expiry_price
                < entry_price
            ):

                result = "WIN"

            elif (
                expiry_price
                > entry_price
            ):

                result = "LOSS"

            else:

                result = "TIE"

        # --------------------------------------------------------
        # PROFIT
        # --------------------------------------------------------

        if result == "WIN":

            wins += 1

            profit = payout

        elif result == "LOSS":

            losses += 1

            profit = -1.0

        else:

            ties += 1

            profit = 0.0

        trades.append(
            {
                "analysis_time":
                    analysis_time,
                "entry_time":
                    entry_time,
                "expiry_time":
                    actual_expiry_time,
                "direction":
                    direction,
                "action":
                    signal["action"],
                "entry_price":
                    entry_price,
                "expiry_price":
                    expiry_price,
                "result":
                    result,
                "profit_units":
                    profit,
                "bull_score":
                    signal["bull_score"],
                "bear_score":
                    signal["bear_score"],
                "score_difference":
                    signal["difference"],
                "confidence":
                    signal["confidence"],
                "ema20":
                    signal["ema20"],
                "ema50":
                    signal["ema50"],
                "rsi":
                    signal["rsi"],
                "macd":
                    signal["macd"],
                "macd_signal":
                    signal["macd_signal"],
                "adx":
                    signal["adx"],
                "atr":
                    signal["atr"],
                "structure":
                    signal["structure"],
                "bos":
                    signal["bos"],
                "choch":
                    signal["choch"],
                "engulfing":
                    signal["engulfing"],
                "rejection":
                    signal["rejection"],
                "impulse":
                    signal["impulse"],
                "pullback":
                    signal["pullback"],
                "support":
                    signal["support"],
                "resistance":
                    signal["resistance"],
                "reasons":
                    signal["reasons"],
            }
        )

        if signals % 250 == 0:

            print(
                f"  Señales procesadas: "
                f"{signals:,} | "
                f"W: {wins:,} | "
                f"L: {losses:,} | "
                f"T: {ties:,}"
            )

    # ------------------------------------------------------------
    # SIN OPERACIONES
    # ------------------------------------------------------------

    if not trades:

        print(
            "⚠ No se generaron operaciones."
        )

        return None

    result_df = pd.DataFrame(
        trades
    )

    total = len(
        result_df
    )

    wins = int(
        (
            result_df["result"]
            == "WIN"
        ).sum()
    )

    losses = int(
        (
            result_df["result"]
            == "LOSS"
        ).sum()
    )

    ties = int(
        (
            result_df["result"]
            == "TIE"
        ).sum()
    )

    decided = (
        wins + losses
    )

    win_rate = (
        wins / decided * 100
        if decided > 0
        else 0
    )

    total_profit = (
        result_df[
            "profit_units"
        ].sum()
    )

    wins_profit = (
        result_df.loc[
            result_df["result"]
            == "WIN",
            "profit_units",
        ].sum()
    )

    losses_profit = (
        result_df.loc[
            result_df["result"]
            == "LOSS",
            "profit_units",
        ].sum()
    )

    # ------------------------------------------------------------
    # EQUITY
    # ------------------------------------------------------------

    equity = (
        result_df[
            "profit_units"
        ].cumsum()
    )

    peak = equity.cummax()

    drawdown = (
        equity - peak
    )

    max_drawdown = (
        drawdown.min()
    )

    # ------------------------------------------------------------
    # RACHAS
    # ------------------------------------------------------------

    max_win_streak = 0

    max_loss_streak = 0

    current_win = 0

    current_loss = 0

    for result in result_df[
        "result"
    ]:

        if result == "WIN":

            current_win += 1

            current_loss = 0

            max_win_streak = max(
                max_win_streak,
                current_win,
            )

        elif result == "LOSS":

            current_loss += 1

            current_win = 0

            max_loss_streak = max(
                max_loss_streak,
                current_loss,
            )

        else:

            current_win = 0
            current_loss = 0

    # ------------------------------------------------------------
    # MOVIMIENTO PRECIO
    # ------------------------------------------------------------

    first_price = float(
        result_df[
            "entry_price"
        ].iloc[0]
    )

    last_price = float(
        result_df[
            "expiry_price"
        ].iloc[-1]
    )

    price_change = (
        (
            last_price
            - first_price
        )
        / first_price
        * 100
        if first_price != 0
        else 0
    )

    # ------------------------------------------------------------
    # BREAK EVEN
    # ------------------------------------------------------------

    breakeven = (
        1
        / (1 + payout)
        * 100
    )

    # ------------------------------------------------------------
    # RESULTADO
    # ------------------------------------------------------------

    print()
    print("=" * 80)
    print(
        f"RESULTADO {timeframe_name}"
    )
    print("=" * 80)

    print(
        f"Operaciones:       {total:,}"
    )

    print(
        f"WIN:               {wins:,}"
    )

    print(
        f"LOSS:              {losses:,}"
    )

    print(
        f"TIE:               {ties:,}"
    )

    print(
        f"Win Rate:          {win_rate:.2f}%"
    )

    print(
        f"Break-even "
        f"{payout*100:.0f}%:   "
        f"{breakeven:.2f}%"
    )

    print(
        f"Resultado unidades: "
        f"{total_profit:+.2f}"
    )

    print(
        f"Ganancias:          "
        f"{wins_profit:+.2f}"
    )

    print(
        f"Pérdidas:           "
        f"{losses_profit:+.2f}"
    )

    print(
        f"Max Drawdown:       "
        f"{max_drawdown:.2f}"
    )

    print(
        f"Racha WIN máxima:   "
        f"{max_win_streak}"
    )

    print(
        f"Racha LOSS máxima:  "
        f"{max_loss_streak}"
    )

    print(
        f"Movimiento precio:  "
        f"{price_change:+.2f}%"
    )

    return {
        "timeframe":
            timeframe_name,
        "operations":
            total,
        "wins":
            wins,
        "losses":
            losses,
        "ties":
            ties,
        "win_rate":
            win_rate,
        "breakeven":
            breakeven,
        "profit_units":
            total_profit,
        "wins_profit":
            wins_profit,
        "losses_profit":
            losses_profit,
        "max_drawdown":
            max_drawdown,
        "max_win_streak":
            max_win_streak,
        "max_loss_streak":
            max_loss_streak,
        "price_change_pct":
            price_change,
        "trades":
            result_df,
    }


# ================================================================
# BACKTEST POR PAR
# ================================================================

def backtest_pair(
    client,
    pair,
    max_bars,
    force_download=False,
):

    print()
    print("#" * 90)
    print(
        f"# PREPARANDO {pair}"
    )
    print("#" * 90)

    largest_tf = max(
        TIMEFRAMES.values()
    )

    required_1m = (
        max_bars
        * largest_tf
        + WARMUP
        + largest_tf
        + 10
    )

    print(
        f"Minutos 1M requeridos: "
        f"{required_1m:,}"
    )

    approx_days = (
        required_1m / 1440
    )

    print(
        f"Tiempo calendario aproximado: "
        f"{approx_days:.1f} días"
    )

    try:

        base = download_1m_history(
            client=client,
            symbol=pair,
            required_bars=required_1m,
            force=force_download,
        )

    except Exception as exc:

        print()

        print(
            f"❌ ERROR descargando {pair}:"
        )

        print(exc)

        return []

    if len(base) < 500:

        print(
            "❌ Muy pocos datos para "
            "hacer backtest."
        )

        return []

    all_summaries = []

    for timeframe in TIMEFRAMES:

        try:

            result = run_backtest(
                base_1m=base,
                timeframe_name=timeframe,
                max_bars=max_bars,
            )

            if result is None:

                continue

            RESULTS_DIR.mkdir(
                parents=True,
                exist_ok=True,
            )

            operations_file = (
                RESULTS_DIR
                / f"{pair}_{timeframe}_operations.csv"
            )

            result[
                "trades"
            ].to_csv(
                operations_file,
                index=False,
            )

            summary = {
                "pair":
                    pair,
                "timeframe":
                    timeframe,
                "operations":
                    result["operations"],
                "wins":
                    result["wins"],
                "losses":
                    result["losses"],
                "ties":
                    result["ties"],
                "win_rate":
                    result["win_rate"],
                "breakeven":
                    result["breakeven"],
                "profit_units":
                    result["profit_units"],
                "max_drawdown":
                    result["max_drawdown"],
                "max_win_streak":
                    result["max_win_streak"],
                "max_loss_streak":
                    result["max_loss_streak"],
                "price_change_pct":
                    result["price_change_pct"],
            }

            all_summaries.append(
                summary
            )

            print(
                f"✓ Operaciones guardadas: "
                f"{operations_file}"
            )

        except Exception as exc:

            print()

            print(
                f"❌ Error en "
                f"{pair} {timeframe}: "
                f"{exc}"
            )

    return all_summaries


# ================================================================
# MAIN
# ================================================================

def main():

    parser = argparse.ArgumentParser(
        description=(
            "Trading Analyzer - "
            "Backtest masivo con Twelve Data"
        )
    )

    parser.add_argument(
        "--pairs",
        nargs="+",
        default=DEFAULT_PAIRS,
        help=(
            "Pares Forex. "
            "Ejemplo: EURUSD GBPUSD"
        ),
    )

    parser.add_argument(
        "--max-bars",
        type=int,
        default=10000,
        help=(
            "Cantidad de velas por timeframe. "
            "Default: 10000"
        ),
    )

    parser.add_argument(
        "--payout",
        type=float,
        default=0.90,
        help=(
            "Payout decimal. "
            "Ejemplo: 0.90"
        ),
    )

    parser.add_argument(
        "--force-download",
        action="store_true",
        help=(
            "Ignorar cache y descargar "
            "nuevamente"
        ),
    )

    args = parser.parse_args()

    global PAYOUT

    PAYOUT = args.payout

    # ------------------------------------------------------------
    # API KEY
    # ------------------------------------------------------------

    api_key = os.getenv(
        "TWELVE_DATA_API_KEY"
    )

    if not api_key:

        print()
        print("=" * 80)
        print(
            "❌ FALTA API KEY"
        )
        print("=" * 80)
        print()

        print(
            "No se encontró "
            "TWELVE_DATA_API_KEY."
        )

        print()

        print(
            "Comprueba que exista:"
        )

        print(
            "  .env"
        )

        print()

        print(
            "Y que contenga:"
        )

        print(
            "  TWELVE_DATA_API_KEY=TU_API_KEY"
        )

        print()

        sys.exit(1)

    # ------------------------------------------------------------
    # DIRECTORIOS
    # ------------------------------------------------------------

    DATA_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    RESULTS_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    # ------------------------------------------------------------
    # CABECERA
    # ------------------------------------------------------------

    print()

    print("=" * 90)

    print(
        "TRADING ANALYZER - BACKTEST MASIVO"
    )

    print(
        "Versión: 4.1-TWELVE-DATA"
    )

    print("=" * 90)

    print(
        f"Pares:       "
        f"{len(args.pairs)}"
    )

    print(
        "Timeframes:  "
        + ", ".join(
            TIMEFRAMES.keys()
        )
    )

    print(
        f"Objetivo:    "
        f"{args.max_bars:,} "
        f"velas por timeframe"
    )

    print(
        "Fuente:      Twelve Data"
    )

    print(
        "Datos:       1M -> TF"
    )

    print(
        "Entrada:     siguiente apertura 1M"
    )

    print(
        "Payout:      "
        f"{PAYOUT*100:.0f}%"
    )

    print(
        "Break-even:  "
        f"{1/(1+PAYOUT)*100:.2f}%"
    )

    print("=" * 90)

    # ------------------------------------------------------------
    # CLIENTE
    # ------------------------------------------------------------

    client = TwelveDataClient(
        api_key
    )

    # ------------------------------------------------------------
    # COMPROBAR CONEXIÓN
    # ------------------------------------------------------------

    print()

    print(
        "Comprobando conexión "
        "con Twelve Data..."
    )

    try:

        test = client.request_price(
            {
                "symbol": "EUR/USD"
            }
        )

        print(
            "✓ Twelve Data respondió correctamente."
        )

        if isinstance(test, dict):

            price = test.get(
                "price"
            )

            if price is not None:

                print(
                    f"✓ EUR/USD actual: "
                    f"{price}"
                )

    except Exception as exc:

        print()

        print(
            "❌ No se pudo validar "
            "la API de Twelve Data."
        )

        print(exc)

        sys.exit(1)

    # ------------------------------------------------------------
    # RESULTADOS
    # ------------------------------------------------------------

    all_results = []

    for pair in args.pairs:

        pair = (
            pair
            .upper()
            .replace("/", "")
            .replace("-", "")
        )

        results = backtest_pair(
            client=client,
            pair=pair,
            max_bars=args.max_bars,
            force_download=(
                args.force_download
            ),
        )

        all_results.extend(
            results
        )

    # ------------------------------------------------------------
    # RESUMEN GLOBAL
    # ------------------------------------------------------------

    print()
    print()

    print("#" * 100)

    print(
        "# RESUMEN GLOBAL"
    )

    print("#" * 100)

    if not all_results:

        print(
            "No se generaron resultados."
        )

        return

    summary_df = pd.DataFrame(
        all_results
    )

    summary_file = (
        RESULTS_DIR
        / "BACKTEST_SUMMARY.csv"
    )

    summary_df.to_csv(
        summary_file,
        index=False,
    )

    # ------------------------------------------------------------
    # TABLA
    # ------------------------------------------------------------

    display_columns = [
        "pair",
        "timeframe",
        "operations",
        "wins",
        "losses",
        "ties",
        "win_rate",
        "profit_units",
        "max_drawdown",
        "max_loss_streak",
    ]

    display = summary_df[
        display_columns
    ].copy()

    display["win_rate"] = (
        display["win_rate"]
        .map(
            lambda x:
                f"{x:.2f}%"
        )
    )

    display["profit_units"] = (
        display["profit_units"]
        .map(
            lambda x:
                f"{x:+.2f}"
        )
    )

    display["max_drawdown"] = (
        display["max_drawdown"]
        .map(
            lambda x:
                f"{x:.2f}"
        )
    )

    print()

    print(
        display.to_string(
            index=False
        )
    )

    print()

    print(
        "✓ Resumen guardado en:"
    )

    print(
        f"  {summary_file}"
    )

    print()

    print(
        "✓ Archivos individuales:"
    )

    print(
        f"  {RESULTS_DIR.resolve()}"
    )

    print()

    print("=" * 100)

    print(
        "BACKTEST FINALIZADO"
    )

    print("=" * 100)


# ================================================================
# EJECUTAR
# ================================================================

if __name__ == "__main__":

    main()