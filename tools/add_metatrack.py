"""Add a Motion Photo 1.0 'application/motionphoto-image-meta' metadata track to a QuickTime MOV.

Spec: https://developer.android.com/media/platform/motion-photo-format
Descriptors follow ISO/IEC 14496-1:2010 clause 8 (expandable size, big-endian payloads).
Purely additive: existing chunk offsets are untouched because moov is the last top-level box,
so the new sample is appended in its own mdat between the original mdat and moov.
"""
import struct, sys

MIME = b'application/motionphoto-image-meta'

# --- ISO/IEC 14496-1 expandable descriptors -------------------------------
def expandable(n):
    if n < 0x80:
        return bytes([n])
    out = bytearray()
    while True:
        out.insert(0, n & 0x7F)
        n >>= 7
        if not n:
            break
    for i in range(len(out) - 1):
        out[i] |= 0x80
    return bytes(out)

def desc(tag, payload):
    return bytes([tag]) + expandable(len(payload)) + payload

def build_descriptor(presentation_ts_us, is_stabilized=False, model_version=0, score=0.0):
    frame_score = desc(0xC3, struct.pack('>fq', score, presentation_ts_us))
    track_score = desc(0xC2, struct.pack('>I', 0))            # numScoredFrames = 0
    score_d     = desc(0xC1, struct.pack('>I', model_version) + frame_score + track_score)
    flag_byte   = bytes([0x80 if is_stabilized else 0x00])    # bit(1), MSB-first
    flag_d      = desc(0xC4, desc(0xC5, flag_byte) + desc(0xC5, flag_byte))
    return desc(0xC0, score_d + flag_d)

# --- box helpers ----------------------------------------------------------
def box(typ, payload):
    return struct.pack('>I', 8 + len(payload)) + typ + payload

def parse(d, start, end):
    off = start
    while off < end - 7:
        sz = struct.unpack('>I', d[off:off+4])[0]
        typ = d[off+4:off+8]
        hdr = 8
        if sz == 1:
            sz = struct.unpack('>Q', d[off+8:off+16])[0]; hdr = 16
        elif sz == 0:
            sz = end - off
        if sz < hdr:
            break
        yield typ, off, sz, hdr
        off += sz

def children(d, off, sz, hdr):
    return list(parse(d, off + hdr, off + sz))

def rebuild(d, off, sz, hdr, replace):
    """Rebuild a container box bottom-up, substituting boxes named in `replace`.

    `replace` maps box type -> bytes (a complete replacement box) or a callable
    taking the original bytes and returning bytes. Recurses only into the
    containers on the stbl path, so nothing else is disturbed.
    """
    NEST = {b'trak': b'mdia', b'mdia': b'minf', b'minf': b'stbl'}
    out = bytearray()
    for typ, c_off, c_sz, c_hdr in children(d, off, sz, hdr):
        original = d[c_off:c_off + c_sz]
        if typ in replace:
            r = replace[typ]
            out += r(original) if callable(r) else r
        elif typ == NEST.get(d[off+4:off+8]):
            out += rebuild(d, c_off, c_sz, c_hdr, replace)
        else:
            out += original
    return box(d[off+4:off+8], bytes(out))

def main(src, dst, ts_us, stabilized):
    d = open(src, 'rb').read()

    tops = list(parse(d, 0, len(d)))
    moov = next((t for t in tops if t[0] == b'moov'), None)
    if not moov or moov[1] + moov[2] != len(d):
        sys.exit('expected moov to be the last top-level box')
    _, moov_off, moov_sz, moov_hdr = moov

    mvhd = next(((o, s, h) for t, o, s, h in children(d, moov_off, moov_sz, moov_hdr) if t == b'mvhd'), None)
    m_off, m_sz, m_hdr = mvhd
    new_id = struct.unpack('>I', d[m_off + m_sz - 4:m_off + m_sz])[0]

    # smallest 'meta'-handler trak as the structural template
    template = None
    for typ, off, sz, hdr in children(d, moov_off, moov_sz, moov_hdr):
        if typ != b'trak':
            continue
        mdia = next(((o, s, h) for t, o, s, h in children(d, off, sz, hdr) if t == b'mdia'), None)
        if not mdia:
            continue
        hdlr = next(((o, s, h) for t, o, s, h in children(d, *mdia) if t == b'hdlr'), None)
        if hdlr and d[hdlr[0] + 16:hdlr[0] + 20] == b'meta':
            if template is None or sz < template[1]:
                template = (off, sz, hdr)
    if not template:
        sys.exit('no metadata track to use as template')
    t_off, t_sz, t_hdr = template

    sample = build_descriptor(ts_us, is_stabilized=stabilized)
    sample_off = moov_off + 8              # inside the appended mdat
    new_mdat = box(b'mdat', sample)

    mett = box(b'mett', b'\x00'*6 + struct.pack('>H', 1) + b'\x00' + MIME + b'\x00')
    replace = {
        b'stsd': box(b'stsd', struct.pack('>II', 0, 1) + mett),
        b'stsz': box(b'stsz', struct.pack('>III', 0, len(sample), 1) + struct.pack('>I', len(sample))),
        b'stco': box(b'stco', struct.pack('>II', 0, 1) + struct.pack('>I', sample_off)),
        b'stts': box(b'stts', struct.pack('>II', 0, 1) + struct.pack('>II', 1, 1)),
        b'tkhd': lambda orig: orig[:20] + struct.pack('>I', new_id) + orig[24:],
    }
    trak = rebuild(d, t_off, t_sz, t_hdr, replace)

    # every box must declare its true length
    def audit(b, off=0, end=None, depth=0):
        end = len(b) if end is None else end
        for typ, o, s, h in parse(b, off, end):
            if o + s > end:
                sys.exit(f'box {typ} overruns parent at {o}')
            if typ in (b'trak', b'mdia', b'minf', b'stbl', b'dinf', b'gmhd'):
                audit(b, o + h, o + s, depth + 1)
    audit(trak)
    if struct.unpack('>I', trak[:4])[0] != len(trak):
        sys.exit('trak size mismatch')

    kids = bytearray()
    for typ, off, sz, hdr in children(d, moov_off, moov_sz, moov_hdr):
        chunk = bytearray(d[off:off + sz])
        if typ == b'mvhd':
            chunk[-4:] = struct.pack('>I', new_id + 1)
        kids += chunk
    kids += trak
    new_moov = box(b'moov', bytes(kids))

    out = d[:moov_off] + new_mdat + new_moov
    open(dst, 'wb').write(out)
    print(f'template trak     : offset {t_off}, {t_sz} bytes -> new trak {len(trak)} bytes')
    print(f'new track_ID      : {new_id}')
    print(f'descriptor sample : {len(sample)} bytes at file offset {sample_off}')
    print(f'wrote {dst}: {len(out)} bytes (source {len(d)}, delta +{len(out)-len(d)})')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]), stabilized=False)
