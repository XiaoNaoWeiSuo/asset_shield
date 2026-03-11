import os
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / 'example'
CFG = EXAMPLE / 'shield_config.yaml'
RAW_DIR = EXAMPLE / 'assets' / 'raw_bench'
ENC_DIR = EXAMPLE / 'assets' / 'encrypted'
GEN_CFG = EXAMPLE / 'lib' / 'generated' / 'asset_shield_config.dart'

CHUNK_SIZES = [64 * 1024, 256 * 1024, 1024 * 1024]
COMPRESSIONS = ['none', 'zstd']

BENCH_ITER = 30

KEY_RE = re.compile(r"assetShieldKeyBase64\s*=\s*'([^']+)'")
YAML_KEY_RE = re.compile(r'^key:\s*"?([^"\n]+)"?$', re.MULTILINE)


def run(cmd, cwd=None):
    print(f'\n$ {" ".join(cmd)} (cwd={cwd or ROOT})')
    subprocess.check_call(cmd, cwd=cwd or ROOT)


def read_key():
    if GEN_CFG.exists():
        m = KEY_RE.search(GEN_CFG.read_text())
        if m:
            return m.group(1)
    if CFG.exists():
        m = YAML_KEY_RE.search(CFG.read_text())
        if m:
            return m.group(1).strip()
    raise RuntimeError('Key not found in generated config or shield_config.yaml')


def write_config(key_base64, compression, chunk_size):
    content = f'''# Auto-generated for benchmark\nraw_assets_dir: assets/raw_bench\n\n# Encrypted assets output directory\nencrypted_assets_dir: assets/encrypted\n\n# Generated config output for runtime\nconfig_output: lib/generated/asset_shield_config.dart\n\n# Compression algorithm: zstd | none\ncompression: {compression}\n\n# Compression level (Zstd) - higher is smaller but slower\ncompression_level: 3\n\n# Chunk size for crypto (bytes)\nchunk_size: {chunk_size}\n\n# Crypto workers (-1 = auto, 0/1 = single-thread)\ncrypto_workers: -1\n\n# Zstd workers (-1 = auto, 0/1 = single-thread)\nzstd_workers: -1\n\n# Extensions to encrypt. Empty list means encrypt all files.\nextensions: []\n\n# Base64 key (32 bytes for AES-256-GCM)\nkey: "{key_base64}"\n\n# Emit key constant into generated config\nemit_key: true\n'''
    CFG.write_text(content)


def ensure_bench_assets():
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    comp_file = RAW_DIR / 'compressible.bin'
    rand_file = RAW_DIR / 'random.bin'

    comp_size = 32 * 1024 * 1024
    rand_size = 32 * 1024 * 1024

    if not comp_file.exists() or comp_file.stat().st_size != comp_size:
        print(f'Generating {comp_file} ({comp_size} bytes)')
        with comp_file.open('wb') as f:
            chunk = b'A' * (1024 * 1024)
            for _ in range(comp_size // len(chunk)):
                f.write(chunk)

    if not rand_file.exists() or rand_file.stat().st_size != rand_size:
        print(f'Generating {rand_file} ({rand_size} bytes)')
        import random
        rng = random.Random(0)
        with rand_file.open('wb') as f:
            for _ in range(rand_size // (1024 * 1024)):
                data = bytearray(1024 * 1024)
                for i in range(len(data)):
                    data[i] = rng.randrange(0, 256)
                f.write(data)


def parse_throughput(output_text):
    # returns list of (label, throughput)
    results = []
    for line in output_text.splitlines():
        if 'throughput:' in line:
            value = float(line.split('throughput:')[1].strip().split()[0])
            results.append(value)
    return results


def bench_one(compression, chunk_size):
    if ENC_DIR.exists():
        shutil.rmtree(ENC_DIR)

    run(['dart', 'run', 'asset_shield', 'encrypt'], cwd=EXAMPLE)

    proc = subprocess.run(
        ['dart', 'run', 'tool/bench_decrypt.dart', str(BENCH_ITER)],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    print(proc.stdout)
    throughputs = parse_throughput(proc.stdout)
    return throughputs


def main():
    if not CFG.exists():
        raise RuntimeError('example/shield_config.yaml not found')

    backup = CFG.read_text()
    try:
        ensure_bench_assets()
        key = read_key()

        results = []
        for compression in COMPRESSIONS:
            for chunk_size in CHUNK_SIZES:
                write_config(key, compression, chunk_size)
                throughputs = bench_one(compression, chunk_size)
                results.append((compression, chunk_size, throughputs))

        print('\nSummary (MiB/s):')
        for compression, chunk_size, thr in results:
            t1 = thr[0] if len(thr) > 0 else None
            t2 = thr[1] if len(thr) > 1 else None
            print(f'  compression={compression:4} chunk={chunk_size:7} : single={t1:.2f} auto={t2:.2f}')
    finally:
        CFG.write_text(backup)


if __name__ == '__main__':
    main()
