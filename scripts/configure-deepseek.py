#!/usr/bin/env python3
"""Enter a DeepSeek API key locally without echoing it or committing it."""
import getpass
import os
import sys
from pathlib import Path
import tempfile


def main():
    directory = Path.home() / 'Library/Application Support/CodexQuotaWatch'
    print('配置 DeepSeek 余额查询。密钥仅存于本机，不会显示在屏幕或写入项目。')
    if not sys.stdin.isatty():
        raise SystemExit('请在本机终端交互运行，避免密钥出现在日志中。')
    key = getpass.getpass('粘贴 DeepSeek API Key 后按回车（输入不显示）：').strip()
    if not key or len(key) > 512 or not key.isascii() or any(c.isspace() for c in key):
        raise SystemExit('密钥为空或格式不正确，未保存。')
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temp = tempfile.mkstemp(prefix='.deepseek-', dir=directory)
    try:
        with os.fdopen(fd, 'w') as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(key + '\n')
        os.replace(temp, directory / 'deepseek-api-key')
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    print('已保存。回到 Codex 告诉我“已保存”，继续验证并安装。')


if __name__ == '__main__':
    main()
