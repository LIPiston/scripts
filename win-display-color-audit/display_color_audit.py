#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""win-display-color-audit — 一站式 Windows 显示器色彩链路体检。

回答三个问题：
  1. 这台机器现在真正生效的 ICC 配置文件是哪一个？（不是"装了什么"，而是"谁在用"）
  2. 面板真实的色域 / 白点 / gamma 是多少？（从 EDID + 出厂 ICC 里内嵌的实测数据推）
  3. 色彩管理到底有没有在工作？（GPU gamma ramp、MHC2 硬件校准、Windows ACM/HDR 状态）

只用 Python 标准库（ctypes + winreg + struct），无需装任何东西。
用法：
    python display_color_audit.py            # 人类可读报告
    python display_color_audit.py --json     # 结构化输出
    python display_color_audit.py --no-scan  # 跳过扫描 spool 里全部配置文件
"""

import argparse
import ctypes
import glob
import json
import math
import os
import struct
import sys
from ctypes import POINTER, byref, sizeof, Structure, c_ubyte, c_void_p, c_wchar
from ctypes import wintypes

try:
    import winreg
except ImportError:  # 非 Windows
    winreg = None

SPOOL_DIR = os.path.join(os.environ.get('SystemRoot', r'C:\Windows'),
                         'System32', 'spool', 'drivers', 'color')
MONITOR_CLASS_GUID = '{4d36e96e-e325-11ce-bfc1-08002be10318}'

ICC_TAG_NAMES = {
    b'desc': 'profileDescription', b'dmnd': 'deviceMfgDesc', b'dmdd': 'deviceModelDesc',
    b'cprt': 'copyright', b'wtpt': 'mediaWhitePoint', b'bkpt': 'mediaBlackPoint',
    b'rXYZ': 'redColorant', b'gXYZ': 'greenColorant', b'bXYZ': 'blueColorant',
    b'rTRC': 'redTRC', b'gTRC': 'greenTRC', b'bTRC': 'blueTRC', b'kTRC': 'grayTRC',
    b'chad': 'chromaticAdaptation', b'lumi': 'luminance', b'vcgt': 'videoCardGamma',
    b'A2B0': 'AToB0', b'B2A0': 'BToA0', b'MHC2': 'MS_HardwareCalibration',
    b'meta': 'metadata', b'CxF ': 'CxF_measurement', b'cicp': 'cicp',
}


# ----------------------------------------------------------------------------
# 基础：标准色域数据
# ----------------------------------------------------------------------------
STD_GAMUTS = {
    'sRGB / Rec.709':      {'R': (0.640, 0.330), 'G': (0.300, 0.600), 'B': (0.150, 0.060), 'W': (0.3127, 0.3290)},
    'Display P3 / DCI-P3': {'R': (0.680, 0.320), 'G': (0.265, 0.690), 'B': (0.150, 0.060), 'W': (0.3127, 0.3290)},
    'Adobe RGB (1998)':    {'R': (0.640, 0.330), 'G': (0.210, 0.710), 'B': (0.150, 0.060), 'W': (0.3127, 0.3290)},
    'Rec.2020':            {'R': (0.708, 0.292), 'G': (0.170, 0.797), 'B': (0.131, 0.046), 'W': (0.3127, 0.3290)},
    'DCI-P3 影院白 (P3-DCI)': {'R': (0.680, 0.320), 'G': (0.265, 0.690), 'B': (0.150, 0.060), 'W': (0.314, 0.351)},
    'NTSC (1953)':         {'R': (0.670, 0.330), 'G': (0.210, 0.710), 'B': (0.140, 0.080), 'W': (0.310, 0.316)},
}


def tri_area(t):
    (x1, y1), (x2, y2), (x3, y3) = t
    return abs((x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)) / 2.0


def xy_of(v):
    s = v[0] + v[1] + v[2]
    if abs(s) < 1e-12:
        return (float('nan'), float('nan'))
    return (v[0] / s, v[1] / s)


def cct_of(wxy):
    x, y = wxy
    if not (y > 0.1858) or math.isnan(x):
        return float('nan')
    n = (x - 0.3320) / (y - 0.1858)
    return -449 * n ** 3 + 3525 * n ** 2 - 6823.3 * n + 5520.33


# ----------------------------------------------------------------------------
# ICC / ICM 解析
# ----------------------------------------------------------------------------
def _s15f16(b):
    return struct.unpack('>i', b)[0] / 65536.0


def icc_tags(data):
    if len(data) < 132:
        return {}
    n = struct.unpack('>I', data[128:132])[0]
    out = {}
    for i in range(n):
        off = 132 + i * 12
        if off + 12 > len(data):
            break
        sig, o, sz = struct.unpack('>4sII', data[off:off + 12])
        out[sig] = (o, sz)
    return out


def icc_matrix(data, blob):
    return [_s15f16(blob[8 + 4 * i:12 + 4 * i]) for i in range(9)]


def mat_rows(v):
    return [v[0:3], v[3:6], v[6:9]]


def mat_inv(m):
    a, b, c = m[0]
    d, e, f = m[1]
    g, h, i = m[2]
    A = (e * i - f * h)
    B = -(d * i - f * g)
    C = (d * h - e * g)
    det = a * A + b * B + c * C
    if abs(det) < 1e-12:
        return None
    return [[A / det, -(b * i - c * h) / det, (b * f - c * e) / det],
            [B / det, (a * i - c * g) / det, -(a * f - c * d) / det],
            [C / det, -(a * h - b * g) / det, (a * e - b * d) / det]]


def mat_vec(m, v):
    return [sum(m[r][j] * v[j] for j in range(3)) for r in range(3)]


def icc_trc_summary(blob):
    sig = blob[:4]
    if sig == b'curv':
        n = struct.unpack('>I', blob[8:12])[0]
        if n == 0:
            return {'type': 'identity', 'gamma': 1.0}
        if n == 1:
            return {'type': 'power', 'gamma': struct.unpack('>H', blob[12:14])[0] / 256.0}
        tab = struct.unpack('>%dH' % n, blob[12:12 + n * 2])
        # 拟合纯幂 gamma（对数最小二乘，避开暗部量化噪声）
        num = den = 0.0
        for i in range(n // 20, n):
            u = i / (n - 1.0)
            y = tab[i] / 65535.0
            if u > 1e-4 and y > 1e-6:
                num += math.log(u) * math.log(y)
                den += math.log(u) ** 2
        return {'type': 'table', 'entries': n, 'gamma': num / den if den else float('nan'),
                'max_out': tab[-1] / 65535.0, 'min_out': tab[0] / 65535.0}
    if sig == b'para':
        ft = struct.unpack('>H', blob[8:10])[0]
        ps = [_s15f16(blob[12 + 4 * i:16 + 4 * i]) for i in range((len(blob) - 12) // 4)]
        return {'type': 'parametric', 'func_type': ft, 'params': [round(p, 6) for p in ps],
                'gamma': ps[0] if ps else float('nan')}
    return {'type': sig.decode('latin-1', 'replace')}


def icc_text(blob):
    sig = blob[:4]
    try:
        if sig == b'mluc':
            cnt, rec = struct.unpack('>II', blob[8:16])
            out = []
            for i in range(min(cnt, 4)):
                b0 = 16 + i * rec
                lang, ctry, ln, off = struct.unpack('>4s4sII', blob[b0:b0 + 16])
                out.append(blob[off:off + ln].decode('utf-16-be', 'replace').rstrip('\x00'))
            return ' | '.join(out)
        if sig in (b'desc', b'targ'):
            typ = struct.unpack('>I', blob[8:12])[0]
            if typ == 0:
                n = struct.unpack('>I', blob[12:16])[0]
                return blob[16:16 + n].split(b'\x00')[0].decode('latin-1', 'replace')
            if typ == 1:
                n = struct.unpack('>I', blob[12:16])[0]
                return blob[16:16 + n * 2].decode('utf-16-be', 'replace').rstrip('\x00')
        if sig == b'text':
            return blob[8:].split(b'\x00')[0].decode('latin-1', 'replace')
    except Exception:
        pass
    return ''


def icc_vcgt(blob):
    """返回 GPU gamma ramp (vcgt) 的关键信息。

    vcgt 的 count/channels 字段被不同厂商写反过，这里两种布局都试，
    并只接受"单调、起点≈0、终点≈1"的合理曲线；否则明确标记无法识别。
    """
    out = {'size': len(blob)}
    try:
        typ = struct.unpack('>I', blob[8:12])[0]
        a, b = struct.unpack('>HH', blob[12:16])
        out.update({'type': typ, 'fields': [a, b]})
        candidates = [('count=a,channels=b', a, b), ('channels=a,count=b', b, a)]
        best = None
        for label, count, chans in candidates:
            if count < 2 or chans not in (1, 3):
                continue
            for nbytes, kind in ((1, '8bit'), (2, '16bit')):
                need = 16 + count * chans * nbytes
                if len(blob) < need:
                    continue
                body = blob[16:]
                scale = 255.0 if nbytes == 1 else 65535.0
                curves = []
                bad = False
                for c in range(chans):
                    vals = []
                    for i in range(count):
                        off = (c * count + i) * nbytes
                        vals.append((body[off] if nbytes == 1
                                     else struct.unpack('>H', body[off:off + 2])[0]) / scale)
                    if any(vals[i + 1] < vals[i] - 1e-6 for i in range(len(vals) - 1)):
                        bad = True
                    curves.append(vals)
                if bad:
                    continue
                dev = max(abs(curves[c][i] - i / (count - 1.0))
                          for c in range(chans) for i in range(count))
                cand = {'layout': label, 'encoding': kind, 'count': count,
                        'channels': chans, 'max_dev_from_identity': round(dev, 5),
                        'is_identity': dev < 0.01}
                if best is None or dev < best['max_dev_from_identity']:
                    best = cand
        if best:
            out.update(best)
        else:
            out['layout_recognized'] = False
    except Exception as e:
        out['error'] = str(e)
    return out


def cxf_creation_date(data, tags):
    """把 ICC 里内嵌的 X-Rite CxF(ZXML) 解出来，取创建时间。"""
    import zlib
    import re
    if b'CxF ' not in tags:
        return None
    o, sz = tags[b'CxF ']
    blob = data[o:o + sz]
    for skip in (0, 4, 8, 12):
        try:
            x = zlib.decompress(blob[skip:])
        except Exception:
            continue
        s = x.decode('utf-8', 'replace')
        m = re.search(r'<cc:CreationDate>([^<]+)</cc:CreationDate>', s)
        dates = re.findall(r'<cc:CreationDate>([^<]+)</cc:CreationDate>', s)
        n_obj = len(re.findall(r'<cc:Object\b', s))
        return {'creation_date': m.group(1) if m else None,
                'objects': n_obj, 'distinct_dates': sorted(set(dates))[:3],
                'xml_chars': len(s)}
    return None


def cxf_measurements(data, tags):
    """从内嵌 CxF 里抓实测 XYZ（去白点后算 xy），返回最亮白点和最饱和三原色。"""
    import zlib
    import re
    if b'CxF ' not in tags:
        return None
    o, sz = tags[b'CxF ']
    blob = data[o:o + sz]
    xml = None
    for skip in (0, 4, 8, 12):
        try:
            xml = zlib.decompress(blob[skip:]).decode('utf-8', 'replace')
            break
        except Exception:
            continue
    if not xml:
        return None
    objs = re.findall(r'<cc:Object\b([^>]*)>(.*?)</cc:Object>', xml, re.S)
    xyz = []
    for attrs, body in objs:
        t = re.search(r'<cc:X>([-\d.eE+]+)</cc:X>\s*<cc:Y>([-\d.eE+]+)</cc:Y>\s*<cc:Z>([-\d.eE+]+)</cc:Z>', body)
        if t:
            v = [float(g) for g in t.groups()]
            if v[1] > 0:
                xyz.append(v)
    if not xyz:
        return None
    white = max(xyz, key=lambda v: v[1])
    wxy = xy_of(white)
    # 最饱和的三个点当作实测原色（按远离白点排序）
    sat = sorted(xyz, key=lambda v: -((xy_of(v)[0] - wxy[0]) ** 2 + (xy_of(v)[1] - wxy[1]) ** 2))
    prim = []
    for v in sat:
        c = xy_of(v)
        if all(abs(c[0] - p[0]) + abs(c[1] - p[1]) > 0.02 for p in prim):
            prim.append(c)
        if len(prim) == 3:
            break
    return {'patches': len(xyz), 'white_Y_nits': white[1], 'white_xy': wxy,
            'top_chromatic_xy': [list(p) for p in sat[:6]],
            'candidate_primaries': [list(p) for p in prim]}


def parse_icc(path):
    try:
        with open(path, 'rb') as f:
            data = f.read()
    except OSError:
        return None
    if len(data) < 132:
        return None
    tags = icc_tags(data)
    ver = '%d.%d.%d' % (data[8], data[9] >> 4, data[9] & 0xF)
    info = {
        'path': path,
        'basename': os.path.basename(path),
        'size': len(data),
        'version': ver,
        'class': data[12:16].decode('latin-1', 'replace').strip('\x00'),
        'space': data[16:20].decode('latin-1', 'replace').strip('\x00'),
        'pcs': data[20:24].decode('latin-1', 'replace').strip('\x00'),
        'cmm': data[4:8].decode('latin-1', 'replace').strip('\x00'),
        'creator': data[80:84].decode('latin-1', 'replace').strip('\x00'),
        'tags': sorted(t.decode('latin-1', 'replace').strip() for t in tags),
    }
    # 文本
    for t, key in ((b'desc', 'description'), (b'cprt', 'copyright')):
        if t in tags:
            o, sz = tags[t]
            info[key] = icc_text(data[o:o + sz])
    # chad + 原色（native = 用 chad 逆矩阵把 D50 适配值还原）
    native = None
    if b'chad' in tags:
        o, sz = tags[b'chad']
        chad = mat_rows(icc_matrix(data, data[o:o + sz]))
        inv = mat_inv(chad)
        info['chromatic_adaptation'] = [[round(v, 6) for v in row] for row in chad]
        native = inv
    def unadapt(v):
        return mat_vec(native, v) if native else v
    prim = {}
    for tg, key in ((b'rXYZ', 'R'), (b'gXYZ', 'G'), (b'bXYZ', 'B')):
        if tg in tags:
            o, sz = tags[tg]
            v = [_s15f16(data[o + 8 + 4 * i:o + 12 + 4 * i]) for i in range(3)]
            prim[key] = xy_of(unadapt(v))
    if len(prim) == 3:
        info['primaries_xy'] = {k: [round(v[0], 5), round(v[1], 5)] for k, v in prim.items()}
        info['gamut_area_xy'] = round(tri_area([prim['R'], prim['G'], prim['B']]), 6)
        info['coverage_vs_standard'] = {}
        for name, g in STD_GAMUTS.items():
            ref = [g['R'], g['G'], g['B']]
            info['coverage_vs_standard'][name] = {
                'area_ratio': round(tri_area([prim['R'], prim['G'], prim['B']]) / tri_area(ref), 4),
                'max_primary_dev': round(max(
                    abs(prim[k][0] - g[k][0]) + abs(prim[k][1] - g[k][1]) for k in 'RGB'), 5),
            }
    if b'wtpt' in tags:
        o, sz = tags[b'wtpt']
        v = [_s15f16(data[o + 8 + 4 * i:o + 12 + 4 * i]) for i in range(3)]
        w = xy_of(unadapt(v))
        info['white_point_xy'] = [round(w[0], 5), round(w[1], 5)]
        info['white_point_cct'] = round(cct_of(w)) if not math.isnan(cct_of(w)) else None
    if b'lumi' in tags:
        o, sz = tags[b'lumi']
        info['luminance_tag_nits'] = round(_s15f16(data[o + 12:o + 16]), 3)
    for tg, key in ((b'rTRC', 'redTRC'), (b'gTRC', 'greenTRC'), (b'bTRC', 'blueTRC')):
        if tg in tags:
            o, sz = tags[tg]
            s = icc_trc_summary(data[o:o + sz])
            if 'gamma' in s and s['gamma']:
                s['gamma'] = round(s['gamma'], 4)
            info[key] = s
    if b'vcgt' in tags:
        o, sz = tags[b'vcgt']
        info['videoCardGamma'] = icc_vcgt(data[o:o + sz])
    cxf = cxf_creation_date(data, tags)
    if cxf:
        info['embedded_measurement'] = cxf
        m = cxf_measurements(data, tags)
        if m:
            info['embedded_measurement']['white_Y_nits'] = round(m['white_Y_nits'], 2)
            info['embedded_measurement']['white_xy'] = [round(m['white_xy'][0], 5), round(m['white_xy'][1], 5)]
            info['embedded_measurement']['white_cct'] = round(cct_of(m['white_xy']))
            info['embedded_measurement']['brightest_chromatic_patches'] = [
                [round(p[0], 5), round(p[1], 5)] for p in m['top_chromatic_xy']]
    info['has_MHC2'] = b'MHC2' in tags
    return info


# ----------------------------------------------------------------------------
# EDID
# ----------------------------------------------------------------------------
def pnp_id(v):
    return ''.join(chr(64 + ((v >> s) & 0x1F)) for s in (10, 5, 0))


def parse_edid(d):
    if len(d) < 128 or d[:8] != b'\x00\xff\xff\xff\xff\xff\xff\x00':
        return None
    out = {'bytes': len(d), 'mfg': pnp_id(struct.unpack('>H', d[8:10])[0]),
           'product_code': '0x%04X' % struct.unpack('<H', d[10:12])[0],
           'year': 1990 + d[17], 'edid_version': '%d.%d' % (d[18], d[19]),
           'panel_size_mm': (d[21], d[22]), 'edid_gamma': round((d[23] + 100) / 100.0, 2),
           'extensions': d[126], 'checksum_ok': sum(d[:128]) % 256 == 0}
    rx = (d[27] << 2) | (d[25] >> 6 & 3); ry = (d[28] << 2) | (d[25] >> 4 & 3)
    gx = (d[29] << 2) | (d[25] >> 2 & 3); gy = (d[30] << 2) | (d[25] & 3)
    bx = (d[31] << 2) | (d[26] >> 6 & 3); by = (d[32] << 2) | (d[26] >> 4 & 3)
    wx = (d[33] << 2) | (d[26] >> 2 & 3); wy = (d[34] << 2) | (d[26] & 3)
    ch = {'R': (rx / 1024.0, ry / 1024.0), 'G': (gx / 1024.0, gy / 1024.0),
          'B': (bx / 1024.0, by / 1024.0), 'W': (wx / 1024.0, wy / 1024.0)}
    out['chroma_xy'] = {k: [round(v[0], 4), round(v[1], 4)] for k, v in ch.items()}
    out['gamut_area_xy'] = round(tri_area([ch['R'], ch['G'], ch['B']]), 6)
    out['white_cct'] = round(cct_of(ch['W']))
    out['closest_standard'] = min(
        STD_GAMUTS, key=lambda n: max(abs(ch[k][0] - STD_GAMUTS[n][k][0]) + abs(ch[k][1] - STD_GAMUTS[n][k][1])
                                      for k in 'RGB'))
    for i in range(4):
        o = 54 + i * 18
        if d[o] == 0 and d[o + 1] == 0:
            tag = d[o + 3]
            txt = d[o + 5:o + 18].split(b'\x0a')[0].split(b'\x00')[0].decode('latin-1', 'replace').strip()
            if tag == 0xFC:
                out['monitor_name'] = txt
            elif tag == 0xFD and len(d) >= o + 18:
                out['range_limits'] = {'v_min': d[o + 5], 'v_max': d[o + 6],
                                       'h_min_khz': d[o + 7], 'h_max_khz': d[o + 8],
                                       'max_pixel_clock_mhz': d[o + 9] * 10}
    # CTA-861 扩展块：HDR 静态元数据 / 色彩学
    for e in range(min(out['extensions'], (len(d) - 128) // 128)):
        ext = d[128 + e * 128:256 + e * 128]
        if ext[0] != 0x02:
            continue
        i = 4
        end = ext[2] if 4 < ext[2] <= 127 else 127
        while i < end:
            tag = ext[i] >> 5
            ln = ext[i] & 0x1F
            if ln == 0:
                break
            payload = ext[i + 1:i + 1 + ln]
            if tag == 7 and payload:
                et = payload[0]
                body = payload[1:]
                if et == 0x05 and body:
                    names = ['xvYCC601', 'xvYCC709', 'sYCC601', 'opYCC601', 'opRGB/AdobeRGB',
                             'BT2020cYCC', 'BT2020YCC', 'BT2020RGB']
                    out['colorimetry'] = [n for k, n in enumerate(names) if body[0] >> k & 1]
                elif et == 0x06 and body:
                    def lum(code):
                        return None if code == 0 else 50 * 2 ** ((code - 1) / 32.0)
                    eotf = body[0]
                    mx = lum(body[2]) if len(body) > 2 else None
                    out['hdr_static_metadata'] = {
                        'eotf': [n for k, n in enumerate(['SDR', 'HDR', 'PQ(ST2084)', 'HLG']) if eotf >> k & 1],
                        'max_luminance_nits': round(mx, 1) if mx else None,
                        'avg_luminance_nits': round(lum(body[3]), 1) if len(body) > 3 and lum(body[3]) else None,
                        'min_luminance_nits': round(mx * (body[4] / 255.0) ** 2 / 100.0, 4)
                        if len(body) > 4 and body[4] and mx else None,
                    }
            i += 1 + ln
    return out


def enum_edids():
    """从注册表 Enum\\DISPLAY 读所有历史 EDID。"""
    if winreg is None:
        return []
    out = []
    base = r'SYSTEM\CurrentControlSet\Enum\DISPLAY'
    try:
        root = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, base)
    except OSError:
        return out
    i = 0
    while True:
        try:
            mfg = winreg.EnumKey(root, i)
        except OSError:
            break
        i += 1
        try:
            k1 = winreg.OpenKey(root, mfg)
        except OSError:
            continue
        j = 0
        while True:
            try:
                inst = winreg.EnumKey(k1, j)
            except OSError:
                break
            j += 1
            try:
                dp = winreg.OpenKey(k1, inst + r'\Device Parameters')
                edid, _ = winreg.QueryValueEx(dp, 'EDID')
            except OSError:
                continue
            p = parse_edid(bytes(edid))
            if p:
                p['instance_path'] = 'DISPLAY\\%s\\%s' % (mfg, inst)
                out.append(p)
    return out


# ----------------------------------------------------------------------------
# Win32: 当前生效的 ICC / gamma ramp / ACM 状态
# ----------------------------------------------------------------------------
class LUID(Structure):
    _fields_ = [('LowPart', wintypes.DWORD), ('HighPart', wintypes.LONG)]


class DIH(Structure):
    _fields_ = [('type', wintypes.UINT), ('size', wintypes.UINT), ('adapterId', LUID), ('id', wintypes.UINT)]


class ADV_COLOR(Structure):
    _fields_ = [('header', DIH), ('value', wintypes.UINT), ('colorEncoding', wintypes.UINT),
                ('bitsPerColorChannel', wintypes.UINT)]


class DISPLAY_DEVICE(Structure):
    _fields_ = [('cb', wintypes.DWORD), ('DeviceName', c_wchar * 32), ('DeviceString', c_wchar * 128),
                ('StateFlags', wintypes.DWORD), ('DeviceID', c_wchar * 128), ('DeviceKey', c_wchar * 128)]


def win_display_state():
    """返回每个适配器/显示器的 GDI 名称、当前 ICC、gamma ramp 状态。"""
    if sys.platform != 'win32':
        return []
    user32 = ctypes.WinDLL('user32', use_last_error=True)
    gdi32 = ctypes.WinDLL('gdi32', use_last_error=True)
    mscms = ctypes.WinDLL('mscms', use_last_error=True)
    user32.EnumDisplayDevicesW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD,
                                           POINTER(DISPLAY_DEVICE), wintypes.DWORD]
    gdi32.CreateDCW.argtypes = [wintypes.LPCWSTR] * 3 + [c_void_p]
    gdi32.CreateDCW.restype = wintypes.HDC
    gdi32.DeleteDC.argtypes = [wintypes.HDC]
    gdi32.GetICMProfileW.argtypes = [wintypes.HDC, POINTER(wintypes.DWORD), ctypes.c_wchar_p]
    gdi32.GetICMProfileW.restype = wintypes.BOOL
    gdi32.GetDeviceGammaRamp.argtypes = [wintypes.HDC, POINTER(wintypes.USHORT)]
    gdi32.GetDeviceGammaRamp.restype = wintypes.BOOL
    user32.GetDisplayConfigBufferSizes.argtypes = [wintypes.UINT, POINTER(wintypes.UINT), POINTER(wintypes.UINT)]
    user32.DisplayConfigGetDeviceInfo.argtypes = [c_void_p]
    mscms.WcsGetDefaultColorProfile.argtypes = [wintypes.DWORD, wintypes.LPCWSTR, wintypes.DWORD,
                                                wintypes.DWORD, wintypes.DWORD, wintypes.DWORD,
                                                ctypes.c_wchar_p]
    mscms.WcsGetDefaultColorProfile.restype = wintypes.BOOL

    out = []
    dd = DISPLAY_DEVICE()
    dd.cb = sizeof(dd)
    idx = 0
    while user32.EnumDisplayDevicesW(None, idx, byref(dd), 0):
        entry = {'adapter': dd.DeviceName, 'adapter_name': dd.DeviceString,
                 'attached': bool(dd.StateFlags & 0x1), 'primary': bool(dd.StateFlags & 0x4),
                 'monitors': []}
        mj = DISPLAY_DEVICE()
        mj.cb = sizeof(mj)
        j = 0
        while user32.EnumDisplayDevicesW(dd.DeviceName, j, byref(mj), 0):
            entry['monitors'].append({'name': mj.DeviceString, 'device_id': mj.DeviceID,
                                      'device_key': mj.DeviceKey})
            mj = DISPLAY_DEVICE(); mj.cb = sizeof(mj); j += 1
        # 该适配器当前使用的 ICC + gamma 曲线
        hdc = gdi32.CreateDCW('DISPLAY', dd.DeviceName, None, None)
        if hdc:
            sz = wintypes.DWORD(0)
            gdi32.GetICMProfileW(hdc, byref(sz), None)
            buf = ctypes.create_unicode_buffer(sz.value if sz.value else 1)
            ok = gdi32.GetICMProfileW(hdc, byref(sz), buf)
            entry['active_icc'] = buf.value if ok and buf.value else None
            ramp = (wintypes.USHORT * 768)()
            if gdi32.GetDeviceGammaRamp(hdc, ramp):
                ident = all(abs(ramp[c * 256 + k] - round(k * 65535 / 255)) <= 8
                            for c in range(3) for k in range(256))
                entry['gamma_ramp'] = {
                    'identity': ident,
                    'max_dev_from_identity_lsb': max(
                        abs(ramp[c * 256 + k] - round(k * 65535 / 255))
                        for c in range(3) for k in range(256)),
                }
            else:
                entry['gamma_ramp'] = None
            gdi32.DeleteDC(hdc)
        out.append(entry)
        dd = DISPLAY_DEVICE(); dd.cb = sizeof(dd); idx += 1
    # 高级颜色（HDR/ACM）状态
    np = wintypes.UINT(0); nm = wintypes.UINT(0)
    user32.GetDisplayConfigBufferSizes(2, byref(np), byref(nm))
    if np.value:
        try:
            import ctypes as _c
            paths = (_c.c_ubyte * (np.value * 96))()
            modes = (_c.c_ubyte * (max(nm.value, 1) * 80))()
            rc = user32.QueryDisplayConfig(2, byref(np), paths, byref(nm), modes, None)
        except Exception:
            rc = -1
    return out


def registry_color_state():
    """ACM / HDR / SDR 白电平 / 每显示器配置关联。"""
    if winreg is None:
        return {}
    res = {}
    # GraphicsDrivers\MonitorDataStore —— 每个显示器（按 EDID 指纹命名的键）的高级颜色状态
    md = r'SYSTEM\CurrentControlSet\Control\GraphicsDrivers\MonitorDataStore'
    res['monitor_data_store'] = {}
    try:
        root = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, md)
        i = 0
        while True:
            try:
                sub = winreg.EnumKey(root, i)
            except OSError:
                break
            i += 1
            d = {}
            try:
                k = winreg.OpenKey(root, sub)
                j = 0
                while True:
                    try:
                        name, val, _ = winreg.EnumValue(k, j)
                    except OSError:
                        break
                    j += 1
                    d[name] = val
            except OSError:
                pass
            if d:
                res['monitor_data_store'][sub] = d
    except OSError:
        pass
    # 用户级 profile 关联
    pa = r'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM\ProfileAssociations\Display'
    res['per_user_associations'] = {}
    try:
        k = winreg.OpenKey(winreg.HKEY_CURRENT_USER, pa + '\\' + MONITOR_CLASS_GUID)
        i = 0
        while True:
            try:
                sub = winreg.EnumKey(k, i)
            except OSError:
                break
            i += 1
            try:
                sk = winreg.OpenKey(k, sub)
                d = {}
                j = 0
                while True:
                    try:
                        name, val, _ = winreg.EnumValue(sk, j)
                    except OSError:
                        break
                    j += 1
                    d[name] = val
                res['per_user_associations'][sub] = d
            except OSError:
                pass
    except OSError:
        pass
    # 校准加载器是否开启
    try:
        k = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                           r'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM\Calibration')
        enabled, _ = winreg.QueryValueEx(k, 'CalibrationManagementEnabled')
        res['calibration_loader_enabled'] = bool(enabled)
    except OSError:
        pass
    # 系统级 profile 关联
    res['system_associations'] = {}
    try:
        k = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                           r'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM\ProfileAssociations\Display')
        i = 0
        while True:
            try:
                sub = winreg.EnumKey(k, i)
            except OSError:
                break
            i += 1
            sub_key = winreg.OpenKey(k, sub)
            d = {}
            j = 0
            while True:
                try:
                    name, val, _ = winreg.EnumValue(sub_key, j)
                except OSError:
                    break
                j += 1
                d[name] = val
            res['system_associations'][sub] = d
    except OSError:
        pass
    return res


def coverage(dst_xy, src_xy, n=260):
    """xy 平面蒙特卡洛：src 色域被 dst 包含的比例。"""
    xs = [p[0] for p in src_xy]
    ys = [p[1] for p in src_xy]
    x0, x1 = min(xs) - 0.005, max(xs) + 0.005
    y0, y1 = min(ys) - 0.005, max(ys) + 0.005

    def inside(p, tri):
        x, y = p
        s = []
        for i in range(3):
            ax, ay = tri[i]
            bx, by = tri[(i + 1) % 3]
            s.append((bx - ax) * (y - ay) - (by - ay) * (x - ax))
        return all(v >= 0 for v in s) or all(v <= 0 for v in s)

    hit = tot = 0
    for i in range(n):
        for j in range(n):
            p = (x0 + (x1 - x0) * (i + 0.5) / n, y0 + (y1 - y0) * (j + 0.5) / n)
            if inside(p, src_xy):
                tot += 1
                if inside(p, dst_xy):
                    hit += 1
    return hit / tot if tot else float('nan')


def main():
    ap = argparse.ArgumentParser(description='Windows 显示器色彩链路体检')
    ap.add_argument('--json', action='store_true', help='输出 JSON')
    ap.add_argument('--no-scan', action='store_true', help='不扫描 spool 里全部 ICC')
    args = ap.parse_args()

    report = {'spool_dir': SPOOL_DIR, 'platform': sys.platform}

    # 1) 显示器与 EDID
    edids = enum_edids()
    seen = set()
    uniq = []
    for e in edids:
        key = (e['mfg'], e['product_code'], tuple(map(tuple, e['chroma_xy'].values())))
        if key not in seen:
            seen.add(key)
            uniq.append(e)
    report['edid_panels'] = uniq

    # 2) 当前生效状态
    report['adapters'] = win_display_state()
    report['registry'] = registry_color_state()

    # 3) 已安装配置文件清单
    if not args.no_scan:
        profs = []
        for p in sorted(glob.glob(os.path.join(SPOOL_DIR, '*'))):
            if os.path.isfile(p) and os.path.getsize(p) > 132 and not p.lower().endswith(('.cdmp', '.gmmp', '.camp')):
                pi = parse_icc(p)
                if pi:
                    profs.append(pi)
        report['installed_profiles'] = profs

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0

    # ---------------- 人类可读报告 ----------------
    W = 92
    print('=' * W)
    print('Windows 显示器色彩链路体检  (win-display-color-audit)')
    print('=' * W)

    print('\n【1】面板 (EDID) —— 屏幕自己声明的能力')
    for e in uniq:
        print('  %s %s   制造年 %s   EDID %s  gamma %.2f  尺寸 %sx%s mm' % (
            e['mfg'], e.get('monitor_name', '?'), e['year'], e['edid_version'],
            e['edid_gamma'], e['panel_size_mm'][0], e['panel_size_mm'][1]))
        c = e['chroma_xy']
        print('      原色  R=(%.4f,%.4f)  G=(%.4f,%.4f)  B=(%.4f,%.4f)   白点 (%.4f,%.4f) ≈ %dK'
              % (c['R'][0], c['R'][1], c['G'][0], c['G'][1], c['B'][0], c['B'][1],
                 c['W'][0], c['W'][1], e['white_cct']))
        print('      色域面积(未归一 xy) = %.6f  → 最接近 %s' % (e['gamut_area_xy'], e['closest_standard']))
        for nm, g in STD_GAMUTS.items():
            if nm in ('sRGB / Rec.709', 'Display P3 / DCI-P3', 'Adobe RGB (1998)', 'Rec.2020'):
                ratio = e['gamut_area_xy'] / tri_area([g['R'], g['G'], g['B']])
                print('        面积比 vs %-22s %5.1f%%' % (nm, ratio * 100))
        if e.get('hdr_static_metadata'):
            h = e['hdr_static_metadata']
            print('      HDR 元数据: EOTF=%s  峰值 %.0f nits  典型 %.0f nits  黑 %.4f nits'
                  % (h['eotf'], h['max_luminance_nits'] or 0, h['avg_luminance_nits'] or 0,
                     h['min_luminance_nits'] or 0))
        if e.get('colorimetry'):
            print('      CTA 色彩学声明: %s' % ', '.join(e['colorimetry']))
        if e.get('range_limits'):
            r = e['range_limits']
            print('      行/帧范围: %d-%d Hz, %d-%d kHz, 最大像素时钟 %d MHz'
                  % (r['v_min'], r['v_max'], r['h_min_khz'], r['h_max_khz'], r['max_pixel_clock_mhz']))

    print('\n【2】当前实际生效的配置 —— 注意：这跟"装了哪些"是两件事')
    for a in report['adapters']:
        if not a['attached']:
            continue
        print('  %s  (%s)%s' % (a['adapter'], a['adapter_name'], '  [主显示器]' if a['primary'] else ''))
        for m in a['monitors']:
            print('      挂载显示器 : %s' % m['name'])
            print('      设备 ID    : %s' % m['device_id'])
        print('      ► 交给色彩管理应用用的 ICC : %s' % (a.get('active_icc') or '(无 → 按 sRGB 处理)'))
        gr = a.get('gamma_ramp')
        if gr:
            if gr['identity']:
                print('      ► GPU gamma ramp : 单位曲线（没有任何校准 LUT 被加载）')
            else:
                print('      ► GPU gamma ramp : 已加载校准曲线，最大偏离 %d/65535' % gr['max_dev_from_identity_lsb'])
        else:
            print('      ► GPU gamma ramp : 读取失败')
    reg = report['registry']
    print('  校准加载器 (ICM\\Calibration) : %s'
          % ('已启用' if reg.get('calibration_loader_enabled') else '未启用'))
    for key, d in (reg.get('monitor_data_store') or {}).items():
        if 'AutoColorManagementSupported' in d or 'HDREnabled' in d:
            print('  高级颜色状态 [%s] : ACM 支持=%s  ACM 已启用=%s  HDR=%s  SDR白电平=%s'
                  % (key,
                     d.get('AutoColorManagementSupported'),
                     d.get('AutoColorManagementEnabled'),
                     d.get('HDREnabled'), d.get('SDRWhiteLevel')))
    for sub, d in (reg.get('per_user_associations') or {}).items():
        icm = d.get('ICMProfile')
        if isinstance(icm, (list, tuple)):
            icm = ''.join(chr(c) if isinstance(c, int) else c for c in icm).strip('\x00 ')
        print('  用户级关联 [显示器类实例 %s] : %s' % (sub, icm))
    for sub, d in (reg.get('system_associations') or {}).items():
        icm = d.get('ICMProfile')
        if isinstance(icm, (list, tuple)):
            icm = ''.join(chr(c) if isinstance(c, int) else c for c in icm).strip('\x00 ')
        print('  系统级关联 [%s] : %s' % (sub, icm))

    if not args.no_scan:
        print('\n【3】已安装的显示配置文件清单（%s）' % SPOOL_DIR)
        print('  %-30s %-8s %-9s %-30s %-9s %s' % ('文件名', '版本', 'gamma', '原色 R/G/B (xy)', '白点', '实测?'))
        profs = report['installed_profiles']
        base = None
        for p in profs:
            if p['basename'] == 'DisplayP3.icm':
                base = p
        for p in profs:
            g = (p.get('redTRC') or {}).get('gamma')
            prim = p.get('primaries_xy')
            ps = ('%.3f,%.3f / %.3f,%.3f / %.3f,%.3f' % (prim['R'][0], prim['R'][1], prim['G'][0], prim['G'][1],
                                                         prim['B'][0], prim['B'][1])) if prim else '-'
            wp = p.get('white_point_xy')
            wps = '%.4f,%.4f %sK' % (wp[0], wp[1], p.get('white_point_cct')) if wp else '-'
            mx = p.get('embedded_measurement')
            mxs = ('CxF %d块 @%s' % (mx['objects'], (mx.get('creation_date') or '?')[:10])) if mx else '否'
            print('  %-30s %-8s %-9s %-30s %-22s %s'
                  % (p['basename'], p['version'], ('%.4f' % g) if g else '-', ps, wps, mxs))
        print('\n  用上表可以判断：哪种配置文件是"这台机器实测出来的"，哪种是"标称套用的"。')
        # 面板实测 vs 标准
        if uniq:
            e = uniq[0]
            panel = [tuple(e['chroma_xy'][k]) for k in 'RGB']
            print('\n  面板 EDID 原色 vs 标准色域的覆盖（xy 面积法）：')
            print('    %-24s' % '标准 →', end='')
            names = ['sRGB / Rec.709', 'Display P3 / DCI-P3', 'Adobe RGB (1998)', 'Rec.2020']
            for n in names:
                print('%-22s' % n, end='')
            print()
            print('    %-24s' % '面板覆盖:', end='')
            for n in names:
                g = STD_GAMUTS[n]
                print('%-22s' % ('%.1f%%' % (coverage(panel, [g['R'], g['G'], g['B']]) * 100)), end='')
            print()

    print('\n【4】结论怎么读')
    print('  · "交给应用用的 ICC" 才是真正生效的那个；它显示的是 mscms/GDI 当前返回给色彩管理软件的配置文件。')
    print('  · gamma ramp = 单位曲线 → 没有加载任何 VCGT 校准；若你刚用校色仪生成过 profile，说明它没被加载。')
    print('  · ACM 支持=1 而已启用=0 → Windows 没有对桌面/非色彩管理应用做 sRGB 收敛，广色域屏会偏艳。')
    print('  · 只有"实测"（内嵌 CxF 测量数据）的 profile 才描述你这块屏；纯标称 profile 只是把标准色域套上去。')
    return 0


if __name__ == '__main__':
    sys.exit(main())
