#!/usr/bin/env python3
"""Read/modify/write Steam's binary shortcuts.vdf.

Format: 0x00 = nested map, 0x01 = string, 0x02 = int32 LE, 0x08 = end of map.
Idempotent: an entry whose Exe matches is updated in place rather than duplicated.
"""
import binascii, os, struct, sys

MAP, STR, INT, END = 0x00, 0x01, 0x02, 0x08


def _parse_map(buf, i):
    out = {}
    while True:
        if i >= len(buf):
            return out, i
        t = buf[i]; i += 1
        if t == END:
            return out, i
        j = buf.index(b'\x00', i); key = buf[i:j].decode('utf-8', 'replace'); i = j + 1
        if t == MAP:
            out[key], i = _parse_map(buf, i)
        elif t == STR:
            j = buf.index(b'\x00', i); out[key] = buf[i:j].decode('utf-8', 'replace'); i = j + 1
        elif t == INT:
            out[key] = struct.unpack('<i', buf[i:i + 4])[0]; i += 4
        else:
            raise ValueError('unknown vdf type 0x%02x at %d' % (t, i - 1))


def _emit(obj):
    out = bytearray()
    for k, v in obj.items():
        kb = k.encode('utf-8') + b'\x00'
        if isinstance(v, dict):
            out += bytes([MAP]) + kb + _emit(v) + bytes([END])
        elif isinstance(v, bool):
            out += bytes([INT]) + kb + struct.pack('<i', int(v))
        elif isinstance(v, int):
            out += bytes([INT]) + kb + struct.pack('<i', v)
        else:
            out += bytes([STR]) + kb + str(v).encode('utf-8') + b'\x00'
    return bytes(out)


def load(path):
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return {}
    buf = open(path, 'rb').read()
    i = 0
    if buf[0] == MAP:
        j = buf.index(b'\x00', 1)          # skip the "shortcuts" key
        i = j + 1
    shortcuts, _ = _parse_map(buf, i)
    return shortcuts


def save(path, shortcuts):
    body = bytes([MAP]) + b'shortcuts\x00' + _emit(shortcuts) + bytes([END]) + bytes([END])
    tmp = path + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(body)
    os.replace(tmp, path)


def appid_for(exe, appname):
    """Steam's non-Steam-game appid: crc32(exe+appname) with the high bit set."""
    return binascii.crc32((exe + appname).encode('utf-8')) | 0x80000000


def upsert(path, appname, exe, startdir, icon=''):
    # Steam stores Exe and StartDir QUOTED, and derives the appid from the
    # quoted string. Writing them bare yields a different appid, so Steam sees
    # a different app and orphans its playtime, artwork and per-app settings —
    # and any path containing a space fails to launch.
    if not (exe.startswith('"') and exe.endswith('"')):
        exe = '"%s"' % exe
    if not (startdir.startswith('"') and startdir.endswith('"')):
        startdir = '"%s"' % startdir
    shortcuts = load(path)
    entry = {
        'appid': struct.unpack('<i', struct.pack('<I', appid_for(exe, appname)))[0],
        'AppName': appname, 'Exe': exe, 'StartDir': startdir, 'icon': icon,
        'ShortcutPath': '', 'LaunchOptions': '', 'IsHidden': 0,
        'AllowDesktopConfig': 1, 'AllowOverlay': 1, 'OpenVR': 0, 'Devkit': 0,
        'DevkitGameID': '', 'DevkitOverrideAppID': 0, 'LastPlayTime': 0,
        'FlatpakAppID': '', 'tags': {},
    }
    for k, v in list(shortcuts.items()):
        if not isinstance(v, dict):
            continue
        # Steam has written both "Exe" and "exe" over the years; match either,
        # or a second run creates a duplicate shortcut instead of updating.
        low = {kk.lower(): vv for kk, vv in v.items()}
        if str(low.get('exe', '')).strip('"') == exe.strip('"'):
            entry['LastPlayTime'] = low.get('lastplaytime', 0)
            entry['tags'] = low.get('tags', {})
            shortcuts[k] = entry
            save(path, shortcuts)
            return 'updated', entry['appid']
    idx = str(max([int(k) for k in shortcuts if k.isdigit()] or [-1]) + 1)
    shortcuts[idx] = entry
    save(path, shortcuts)
    return 'added', entry['appid']


if __name__ == '__main__':
    action = sys.argv[1]
    if action == 'upsert':
        what, appid = upsert(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
        print('%s %s' % (what, appid & 0xFFFFFFFF))
    elif action == 'list':
        for k, v in sorted(load(sys.argv[2]).items()):
            if isinstance(v, dict):
                low = {kk.lower(): vv for kk, vv in v.items()}
                print(k, '|', low.get('appname'), '|', low.get('exe'))
