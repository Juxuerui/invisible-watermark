#!/usr/bin/env python3
"""离线签发隐形水印授权码。

用法:
  ./Keys/issue_license.py <设备码> [--days N | --permanent | --expire YYYY-MM-DD]
  ./Keys/issue_license.py <设备码> --verify      # 只校验已有授权码
  ./Keys/issue_license.py --device               # 查看本机设备码（macOS）

设备码格式形如 AB2CD-EF3GH-IJK4L-MN5OP（Base32 分组，5 位一组）。
授权码格式：<base32(13 字节载荷)>.<base32(DER 签名)>

载荷布局:
  [0]     版本，固定 0x01
  [1..4]  到期时间，Unix 秒，大端；0xFFFFFFFF 表示永久
  [5..12] SHA-256(设备标识) 的前 8 字节

签名: ECDSA P-256 / SHA-256，覆盖全部 13 字节载荷。
"""
import argparse
import base64
import datetime as dt
import hashlib
import pathlib
import sys

try:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
except ImportError:
    sys.exit("需要 cryptography 库：python3 -m pip install --user cryptography")

ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
PERMANENT = 0xFFFFFFFF
HERE = pathlib.Path(__file__).resolve().parent
PRIVATE_KEY = HERE / "license_private_pkcs8.pem"
PUBLIC_KEY = HERE / "license_public.pem"


def base32_decode(text: str) -> bytes:
    out = bytearray()
    buf = bits = 0
    for ch in text.upper():
        idx = ALPHABET.find(ch)
        if idx < 0:
            continue
        buf = (buf << 5) | idx
        bits += 5
        if bits >= 8:
            out.append((buf >> (bits - 8)) & 0xFF)
            bits -= 8
    return bytes(out)


def base32_encode(data: bytes) -> str:
    out = []
    buf = bits = 0
    for byte in data:
        buf = (buf << 8) | byte
        bits += 8
        while bits >= 5:
            out.append(ALPHABET[(buf >> (bits - 5)) & 31])
            bits -= 5
    if bits:
        out.append(ALPHABET[(buf << (5 - bits)) & 31])
    return "".join(out)


def group(value: str, size: int = 5) -> str:
    return "-".join(value[i:i + size] for i in range(0, len(value), size))


def load_private():
    if not PRIVATE_KEY.exists():
        sys.exit(f"找不到私钥: {PRIVATE_KEY}")
    return serialization.load_pem_private_key(PRIVATE_KEY.read_bytes(), password=None)


def issue(device_code: str, expire_sec: int) -> str:
    fingerprint = base32_decode(device_code.replace("-", "").replace(" ", ""))
    if len(fingerprint) != 8:
        sys.exit(f"设备码无效：解出 {len(fingerprint)} 字节，应为 8 字节。检查是否复制完整。")

    payload = bytes([1]) + expire_sec.to_bytes(4, "big") + fingerprint
    assert len(payload) == 13

    key = load_private()
    signature = key.sign(payload, ec.ECDSA(hashes.SHA256()))
    return f"{base32_encode(payload)}.{base32_encode(signature)}"


def verify(license_text: str) -> tuple[bool, str]:
    cleaned = license_text.strip().upper().replace("-", "").replace("\n", "").replace(" ", "")
    if "." not in cleaned:
        return False, "格式错误（应为 设备段.签名段）"
    head, tail = cleaned.split(".", 1)
    payload = base32_decode(head)
    signature = base32_decode(tail)
    if len(payload) != 13:
        return False, f"载荷长度错误（{len(payload)} 字节，应为 13）"

    public = serialization.load_pem_public_key(PUBLIC_KEY.read_bytes())
    try:
        public.verify(signature, payload, ec.ECDSA(hashes.SHA256()))
    except Exception:
        return False, "签名校验失败（签名错误或密钥不匹配）"

    expire = int.from_bytes(payload[1:5], "big")
    fingerprint = payload[5:13]
    bound = group(base32_encode(fingerprint))
    if expire == PERMANENT:
        return True, f"校验通过 · 永久 · 绑定设备 {bound}"
    expiry = dt.datetime.fromtimestamp(expire)
    if expiry < dt.datetime.now():
        return False, f"授权已过期（{expiry:%Y-%m-%d}）· 绑定设备 {bound}"
    return True, f"校验通过 · 到期 {expiry:%Y-%m-%d} · 绑定设备 {bound}"


def main() -> None:
    parser = argparse.ArgumentParser(description="签发/校验隐形水印授权码")
    parser.add_argument("device_code", nargs="?", help="设备码，如 AB2CD-EF3GH-IJK4L-MN5OP")
    parser.add_argument("--days", type=int, help="有效天数（默认 365）")
    parser.add_argument("--permanent", action="store_true", help="永久授权")
    parser.add_argument("--expire", help="指定到期日 YYYY-MM-DD")
    parser.add_argument("--verify", metavar="LICENSE", help="校验一个授权码")
    parser.add_argument("--checksum", action="store_true",
                        help="打印公钥 SHA-256，便于与应用核对")
    args = parser.parse_args()

    if args.checksum:
        digest = hashlib.sha256(PUBLIC_KEY.read_bytes()).hexdigest()
        print(f"公钥 SHA-256: {digest}")
        print("应用内 License.publicKeyBase64 应与该公钥一致。")
        return

    if args.verify:
        ok, message = verify(args.verify)
        print(("✓ " if ok else "✗ ") + message)
        sys.exit(0 if ok else 1)

    if not args.device_code:
        parser.error("请提供设备码（在授权工具 App 中复制）")

    if args.permanent:
        expire = PERMANENT
    elif args.expire:
        date = dt.datetime.strptime(args.expire, "%Y-%m-%d")
        expire = int(date.replace(hour=23, minute=59, second=59).timestamp())
    else:
        days = args.days if args.days is not None else 365
        expire = int((dt.datetime.now() + dt.timedelta(days=days)).timestamp())

    license_text = issue(args.device_code, expire)
    print(license_text)
    print()
    ok, message = verify(license_text)
    print(("✓ 自检: " if ok else "✗ 自检失败: ") + message)


if __name__ == "__main__":
    main()
