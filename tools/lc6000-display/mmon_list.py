"""Lists every message in a MIDI Monitor .mmon: index, ms since start, endpoint ("To X"/"From X"), hex."""
import plistlib, sys
p = plistlib.load(open(sys.argv[1], 'rb')); a = plistlib.loads(p['messageData']); O = a['$objects']
d = lambda u: O[u.data] if isinstance(u, plistlib.UID) else u
msgs = [d(u) for u in d(a['$top']['root'])['NS.objects']]
t0 = msgs[0]['timeStampInNanos']
for i, m in enumerate(msgs):
    ep = d(m.get('originatingEndpoint')); ep = ep if isinstance(ep, str) else '?'
    status = m.get('statusByte'); data = d(m.get('data', m.get('dataBytes', b'')))
    raw = bytes([status]) + data if status != 0xF0 else b'\xf0' + data + b'\xf7'
    h = raw.hex(' ').upper()
    print(f"{i:4} {(m['timeStampInNanos'] - t0) / 1e6:10.1f} ms  {ep:40} {len(raw):6} B  {h[:66]}{'…' if len(h) > 66 else ''}")
