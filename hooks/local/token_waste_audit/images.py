import base64
import binascii
import hashlib
import math
import struct


def image_dimensions(prefix):
    if (len(prefix) >= 24 and prefix[:8] == b"\x89PNG\r\n\x1a\n"
            and prefix[12:16] == b"IHDR"):
        return struct.unpack(">II", prefix[16:24])
    if prefix[:2] != b"\xff\xd8":
        return None
    pos = 2
    while pos < len(prefix):
        if prefix[pos] != 0xFF:
            return None
        while pos < len(prefix) and prefix[pos] == 0xFF:
            pos += 1
        if pos >= len(prefix):
            return None
        marker = prefix[pos]
        pos += 1
        if marker in (0xD9, 0xDA):
            return None
        if marker == 0x01 or 0xD0 <= marker <= 0xD8:
            continue
        if pos + 2 > len(prefix):
            return None
        length = int.from_bytes(prefix[pos:pos + 2], "big")
        if length < 2 or pos + length > len(prefix):
            return None
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            if length < 7:
                return None
            height, width = struct.unpack(">HH", prefix[pos + 3:pos + 7])
            return width, height
        pos += length
    return None


def image_metadata(block):
    source = block.get("source")
    data = source.get("data") if isinstance(source, dict) else None
    dimensions = None
    digest = None
    if isinstance(data, str) and source.get("type") == "base64":
        data = "".join(data.split())
        try:
            prefix = base64.b64decode(data[:262144], validate=True)
            dimensions = image_dimensions(prefix)
            hashed = hashlib.sha256()
            for offset in range(0, len(data), 65536):
                hashed.update(base64.b64decode(data[offset:offset + 65536], validate=True))
            digest = hashed.hexdigest()
        except (ValueError, binascii.Error):
            dimensions = None
    tokens = 1600
    if dimensions and all(dimensions):
        width, height = dimensions
        scale = min(1, 1568 / max(width, height))
        tokens = math.ceil(width * height * scale * scale / 750)
    else:
        dimensions = None
    return {"digest": digest, "dimensions": dimensions, "tokens": tokens}


def result_images(content):
    if not isinstance(content, list):
        return []
    return [image_metadata(block) for block in content
            if isinstance(block, dict) and block.get("type") == "image"]
