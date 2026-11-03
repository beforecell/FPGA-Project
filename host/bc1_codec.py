"""Original opaque BC1 RGB encoder and bit-exact integer decoder.

RGB arrays use channel order RGB. 4x4 blocks are independent and occupy
8 bytes: LE RGB565 color0, LE RGB565 color1, LE 32-bit 2-bit selectors.
Color0 is strictly greater than color1 so every block uses four opaque colors.
The integer decoder follows the Khronos S3TC endpoint expansion and floor /3.
"""
from __future__ import annotations

import math
import numpy as np

WIDTH, HEIGHT = 640, 480
BLOCK_W, BLOCK_H = 4, 4
FRAME_BYTES = WIDTH * HEIGHT // 2
FRAME_SECTORS = FRAME_BYTES // 512


def rgb_to_565(rgb: np.ndarray) -> np.ndarray:
    a = np.asarray(rgb, dtype=np.uint32)
    return ((((a[..., 0] * 31 + 127) // 255) << 11)
            | (((a[..., 1] * 63 + 127) // 255) << 5)
            | ((a[..., 2] * 31 + 127) // 255)).astype(np.uint16)


def unpack_565(packed: np.ndarray) -> np.ndarray:
    a = np.asarray(packed, dtype=np.uint32)
    r, g, b = a >> 11, (a >> 5) & 63, a & 31
    return np.stack(((r << 3) | (r >> 2), (g << 2) | (g >> 4),
                     (b << 3) | (b >> 2)), axis=-1).astype(np.uint8)


def palette(c0: np.ndarray, c1: np.ndarray) -> np.ndarray:
    a, b = unpack_565(c0).astype(np.uint16), unpack_565(c1).astype(np.uint16)
    return np.stack((a, b, (2 * a + b) // 3, (a + 2 * b) // 3), axis=1).astype(np.uint8)


def ordered_endpoints(c0: np.ndarray, c1: np.ndarray):
    a, b = np.maximum(c0, c1), np.minimum(c0, c1)
    equal = a == b
    # Strict c0>c1 selects opaque BC1. Every RGB565 constant still has an
    # exact endpoint in the palette, including pure black and white.
    a = np.where(equal & (a == 0), 1, a).astype(np.uint16)
    b = np.where(equal & (b != 0), b - 1, b).astype(np.uint16)
    return a, b


def encode_frame(rgb: np.ndarray, iterations: int = 4) -> bytes:
    a = np.asarray(rgb)
    if a.shape != (HEIGHT, WIDTH, 3) or a.dtype != np.uint8:
        raise ValueError("expected RGB uint8 shape (480,640,3)")
    blocks = a.reshape(HEIGHT // 4, 4, WIDTH // 4, 4, 3)
    blocks = blocks.transpose(0, 2, 1, 3, 4).reshape(-1, 16, 3).astype(np.float32)
    centered = blocks - blocks.mean(axis=1, keepdims=True)
    variance = (centered * centered).sum(axis=1)
    axis = np.eye(3, dtype=np.float32)[variance.argmax(axis=1)]
    for _ in range(3):
        projected = (centered * axis[:, None, :]).sum(axis=2)
        axis = (centered * projected[..., None]).sum(axis=1)
        axis /= np.maximum(np.linalg.norm(axis, axis=1, keepdims=True), 1e-12)
    projection = (blocks * axis[:, None, :]).sum(axis=2)
    index = np.arange(len(blocks))
    c0 = blocks[index, projection.argmax(axis=1)]
    c1 = blocks[index, projection.argmin(axis=1)]
    coefficient = np.array([1.0, 0.0, 2/3, 1/3], dtype=np.float32)
    best_error = np.full(len(blocks), np.inf, dtype=np.float64)
    best0 = np.zeros(len(blocks), np.uint16)
    best1 = np.zeros(len(blocks), np.uint16)
    for _ in range(iterations):
        p0, p1 = ordered_endpoints(rgb_to_565(np.clip(np.rint(c0), 0, 255).astype(np.uint8)),
                                   rgb_to_565(np.clip(np.rint(c1), 0, 255).astype(np.uint8)))
        colors = palette(p0, p1).astype(np.float32)
        distance = ((blocks[:, :, None, :] - colors[:, None, :, :]) ** 2).sum(axis=3)
        codes = distance.argmin(axis=2)
        error = np.take_along_axis(distance,codes[...,None],axis=2).sum(axis=(1,2))
        better = error < best_error
        best0, best1 = np.where(better,p0,best0), np.where(better,p1,best1)
        best_error = np.minimum(error,best_error)
        u = coefficient[codes]
        v = 1 - u
        uu, uv, vv = (u*u).sum(axis=1), (u*v).sum(axis=1), (v*v).sum(axis=1)
        det = uu * vv - uv * uv
        up, vp = (u[..., None] * blocks).sum(axis=1), (v[..., None] * blocks).sum(axis=1)
        divisor = np.maximum(det, 1e-8)[:, None]
        candidate0 = (vv[:, None] * up - uv[:, None] * vp) / divisor
        candidate1 = (uu[:, None] * vp - uv[:, None] * up) / divisor
        c0 = np.where((det > 1e-4)[:, None], candidate0, unpack_565(p0))
        c1 = np.where((det > 1e-4)[:, None], candidate1, unpack_565(p1))
    p0, p1 = ordered_endpoints(rgb_to_565(np.clip(np.rint(c0), 0, 255).astype(np.uint8)),
                               rgb_to_565(np.clip(np.rint(c1), 0, 255).astype(np.uint8)))
    colors = palette(p0, p1).astype(np.int32)
    blocks_i = blocks.astype(np.int32)
    distance = ((blocks_i[:, :, None, :] - colors[:, None, :, :]) ** 2).sum(axis=3)
    error = distance.min(axis=2).sum(axis=1)
    better = error < best_error
    p0, p1 = np.where(better,p0,best0), np.where(better,p1,best1)
    colors = palette(p0,p1).astype(np.int32)
    distance = ((blocks_i[:, :, None, :] - colors[:, None, :, :]) ** 2).sum(axis=3)
    codes = distance.argmin(axis=2).astype(np.uint32)
    selectors = (codes << (2 * np.arange(16, dtype=np.uint32))).sum(axis=1, dtype=np.uint32)
    words = np.empty((len(blocks), 2), dtype='<u4')
    words[:, 0] = p0.astype(np.uint32) | (p1.astype(np.uint32) << 16)
    words[:, 1] = selectors
    return words.tobytes()


def decode_frame(payload: bytes) -> np.ndarray:
    if len(payload) != FRAME_BYTES:
        raise ValueError(f"expected {FRAME_BYTES} payload bytes")
    words = np.frombuffer(payload, dtype='<u4').reshape(-1, 2)
    colors = palette((words[:, 0] & 65535).astype(np.uint16), (words[:, 0] >> 16).astype(np.uint16))
    codes = (words[:, 1, None] >> (2 * np.arange(16, dtype=np.uint32))) & 3
    blocks = colors[np.arange(len(words))[:, None], codes]
    return blocks.reshape(HEIGHT // 4, WIDTH // 4, 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(HEIGHT, WIDTH, 3)


def decode_565(payload: bytes) -> np.ndarray:
    rgb = decode_frame(payload).astype(np.uint16)
    # Scanout/history truncation matches RTL; this is distinct from encoder
    # endpoint rounding to nearest RGB565 levels.
    return ((rgb[..., 0] >> 3) << 11) | ((rgb[..., 1] >> 2) << 5) | (rgb[..., 2] >> 3)


def psnr(reference: np.ndarray, decoded: np.ndarray) -> float:
    mse = float(np.mean((reference.astype(np.float64) - decoded.astype(np.float64)) ** 2))
    return math.inf if mse == 0 else 10 * math.log10(255 * 255 / mse)


def decode_pixel(word0: int, word1: int, x: int, y: int) -> tuple[int, int, int]:
    c0, c1 = word0 & 65535, word0 >> 16
    rgb0 = [((c0 >> 11) << 3) | (c0 >> 13), (((c0 >> 5) & 63) << 2) | ((c0 >> 9) & 3), ((c0 & 31) << 3) | ((c0 >> 2) & 7)]
    rgb1 = [((c1 >> 11) << 3) | (c1 >> 13), (((c1 >> 5) & 63) << 2) | ((c1 >> 9) & 3), ((c1 & 31) << 3) | ((c1 >> 2) & 7)]
    code = (word1 >> (2 * ((y & 3) * 4 + (x & 3)))) & 3
    if code == 0:
        return tuple(rgb0)
    if code == 1:
        return tuple(rgb1)
    if code == 2:
        return tuple((2*a+b)//3 for a, b in zip(rgb0, rgb1))
    return tuple((a+2*b)//3 for a, b in zip(rgb0, rgb1))
