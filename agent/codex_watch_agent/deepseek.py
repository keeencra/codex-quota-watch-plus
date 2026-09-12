"""Read DeepSeek API balance; credentials never leave the Mac except to DeepSeek."""
from __future__ import annotations

import asyncio
import os
import re
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path

import httpx
from pydantic import BaseModel, Field

KEY_PATH = Path.home() / 'Library/Application Support/CodexQuotaWatch/deepseek-api-key'
BALANCE_URL = 'https://api.deepseek.com/user/balance'


class BalanceInfo(BaseModel):
    currency: str
    total_balance: str
    granted_balance: str
    topped_up_balance: str


class DeepSeekBalance(BaseModel):
    status: str = 'not_configured'
    updated_at: str | None = None
    is_available: bool | None = None
    balance_infos: list[BalanceInfo] = Field(default_factory=list)
    error: str | None = None


def read_key() -> str:
    key = os.getenv('DEEPSEEK_API_KEY', '').strip()
    if not key:
        try:
            key = KEY_PATH.read_text().strip()
        except FileNotFoundError:
            return ''
    if key and (len(key) > 512 or not key.isascii() or any(c.isspace() for c in key)):
        raise ValueError('Invalid key format')
    return key


def parse_balance(payload: object) -> DeepSeekBalance:
    if not isinstance(payload, dict) or type(payload.get('is_available')) is not bool:
        raise ValueError('Invalid balance response')
    rows = payload.get('balance_infos')
    if not isinstance(rows, list) or not rows or len(rows) > 2:
        raise ValueError('Missing balance information')
    balances = []
    currencies = set()
    for row in rows:
        if not isinstance(row, dict) or row.get('currency') not in {'CNY', 'USD'} or row['currency'] in currencies:
            raise ValueError('Invalid currency')
        currencies.add(row['currency'])
        amounts = {}
        for name in ('total_balance', 'granted_balance', 'topped_up_balance'):
            value = row.get(name)
            if not isinstance(value, str) or len(value) > 40 or not re.fullmatch(r'[+-]?[0-9]+(?:\.[0-9]{1,12})?', value):
                raise ValueError('Invalid amount')
            number = Decimal(value)
            if not number.is_finite() or abs(number) > Decimal('1e15') or number.as_tuple().exponent < -12:
                raise ValueError('Invalid amount')
            amounts[name] = format(number, 'f')
        balances.append(BalanceInfo(currency=row['currency'], **amounts))
    return DeepSeekBalance(status='ok', updated_at=datetime.now(timezone.utc).isoformat(),
                          is_available=payload['is_available'], balance_infos=balances)


async def get_deepseek_balance() -> DeepSeekBalance:
    try:
        key = read_key()
    except (OSError, ValueError):
        return DeepSeekBalance(status='error', error='Mac 上的 DeepSeek 密钥无法读取，请重新配置。')
    if not key:
        return DeepSeekBalance()
    try:
        # A hard deadline also bounds slow streaming; never follow redirects with the key.
        async def fetch():
            async with httpx.AsyncClient(timeout=5, follow_redirects=False, trust_env=False) as client:
                response = await client.get(BALANCE_URL, headers={'Authorization': 'Bearer ' + key})
                response.raise_for_status()
                return parse_balance(response.json())
        return await asyncio.wait_for(fetch(), timeout=6)
    except httpx.HTTPStatusError as exc:
        message = ('API Key 无效或无权读取余额，请在 Mac 重新配置。'
                   if exc.response.status_code in (401, 403) else 'DeepSeek 服务暂不可用，请稍后刷新。')
    except (httpx.HTTPError, TimeoutError):
        message = '无法连接 DeepSeek，请稍后刷新。'
    except (ValueError, InvalidOperation):
        message = 'DeepSeek 余额响应异常，请稍后刷新。'
    # Do not expose upstream bodies, request headers, keys, or exception strings.
    return DeepSeekBalance(status='error', error=message)
