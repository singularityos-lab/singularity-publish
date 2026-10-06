namespace Singularity.Apps.Publish {

    public class PsKnot {
        public double in_x;
        public double in_y;
        public double x;
        public double y;
        public double out_x;
        public double out_y;
    }

    public class PsSubpath {
        public bool closed = true;
        public Gee.ArrayList<PsKnot> knots = new Gee.ArrayList<PsKnot> ();
    }

    public class PsPath {
        public int id;
        public string name = "";
        public Gee.ArrayList<PsSubpath> subpaths = new Gee.ArrayList<PsSubpath> ();

        public void trace (Cairo.Context cr, double w, double h) {
            foreach (var sp in subpaths) {
                int n = sp.knots.size;
                if (n == 0) continue;
                var first = sp.knots[0];
                cr.move_to (first.x * w, first.y * h);
                for (int i = 1; i <= n; i++) {
                    if (i == n && !sp.closed) break;
                    var a = sp.knots[i - 1];
                    var b = sp.knots[i % n];
                    cr.curve_to (a.out_x * w, a.out_y * h, b.in_x * w, b.in_y * h, b.x * w, b.y * h);
                }
                if (sp.closed) cr.close_path ();
            }
        }
    }

    public class PhotoshopPaths {
        public Gee.ArrayList<PsPath> paths = new Gee.ArrayList<PsPath> ();
        public string clipping = "";

        public PsPath? preferred () {
            if (clipping != "") foreach (var p in paths) if (p.name == clipping) return p;
            return paths.size > 0 ? paths[0] : null;
        }

        private static uint be16 (uint8[] d, int i) {
            return ((uint) d[i] << 8) | d[i + 1];
        }

        private static uint be32 (uint8[] d, int i) {
            return ((uint) d[i] << 24) | ((uint) d[i + 1] << 16) | ((uint) d[i + 2] << 8) | d[i + 3];
        }

        private static double fixed (uint8[] d, int i) {
            int32 v = (int32) be32 (d, i);
            return v / 16777216.0;
        }

        public static PhotoshopPaths? read (uint8[] data) {
            uint8[]? res = null;
            if (data.length > 4 && data[0] == 0xFF && data[1] == 0xD8) res = from_jpeg (data);
            else if (data.length > 26 && data[0] == '8' && data[1] == 'B' && data[2] == 'P' && data[3] == 'S') res = from_psd (data);
            else if (data.length > 8 && ((data[0] == 'I' && data[1] == 'I') || (data[0] == 'M' && data[1] == 'M'))) res = from_tiff (data);
            if (res == null) return null;
            var r = parse_resources (res);
            return r.paths.size > 0 ? r : null;
        }

        private static uint8[]? from_jpeg (uint8[] d) {
            var acc = new ByteArray ();
            int i = 2;
            uint8[] sig = "Photoshop 3.0".data;
            while (i + 4 <= d.length) {
                if (d[i] != 0xFF) {
                    i++;
                    continue;
                }
                uint8 m = d[i + 1];
                if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7) || m == 0xFF) {
                    i += m == 0xFF ? 1 : 2;
                    continue;
                }
                if (m == 0xDA || m == 0xD9) break;
                int len = (int) be16 (d, i + 2);
                int body = i + 4, end = i + 2 + len;
                if (end > d.length) break;
                if (m == 0xED && len > sig.length + 1) {
                    bool match = true;
                    for (int k = 0; k < sig.length; k++) if (d[body + k] != sig[k]) match = false;
                    if (match && d[body + sig.length] == 0) acc.append (d[body + sig.length + 1:end]);
                }
                i = end;
            }
            return acc.len > 0 ? acc.steal () : null;
        }

        private static uint8[]? from_psd (uint8[] d) {
            int i = 26;
            if (i + 4 > d.length) return null;
            int cm = (int) be32 (d, i);
            i += 4 + cm;
            if (i + 4 > d.length) return null;
            int len = (int) be32 (d, i);
            i += 4;
            if (len <= 0 || i + len > d.length) return null;
            return d[i:i + len];
        }

        private static uint8[]? from_tiff (uint8[] d) {
            bool le = d[0] == 'I';
            if (rd16 (d, le, 2) != 42) return null;
            int ifd = (int) rd32 (d, le, 4);
            if (ifd <= 0 || ifd + 2 > d.length) return null;
            int n = (int) rd16 (d, le, ifd);
            for (int k = 0; k < n; k++) {
                int e = ifd + 2 + k * 12;
                if (e + 12 > d.length) break;
                if (rd16 (d, le, e) != 34377) continue;
                uint type = rd16 (d, le, e + 2);
                int count = (int) rd32 (d, le, e + 4);
                if (type != 1 && type != 7) return null;
                int off = count <= 4 ? e + 8 : (int) rd32 (d, le, e + 8);
                if (off < 0 || off + count > d.length) return null;
                return d[off:off + count];
            }
            return null;
        }

        private static uint rd16 (uint8[] d, bool le, int at) {
            return le ? (uint) d[at] | ((uint) d[at + 1] << 8) : be16 (d, at);
        }

        private static uint rd32 (uint8[] d, bool le, int at) {
            return le ? (uint) d[at] | ((uint) d[at + 1] << 8) | ((uint) d[at + 2] << 16) | ((uint) d[at + 3] << 24) : be32 (d, at);
        }

        public static PhotoshopPaths parse_resources (uint8[] d) {
            var r = new PhotoshopPaths ();
            int i = 0;
            while (i + 12 <= d.length) {
                if (d[i] != '8' || d[i + 1] != 'B' || d[i + 2] != 'I' || d[i + 3] != 'M') break;
                int id = (int) be16 (d, i + 4);
                int nlen = d[i + 6];
                string name = pascal (d, i + 6);
                int p = i + 6 + 1 + nlen;
                if (((1 + nlen) & 1) == 1) p++;
                if (p + 4 > d.length) break;
                int size = (int) be32 (d, p);
                int body = p + 4;
                if (size < 0 || body + size > d.length) break;
                if (id >= 2000 && id <= 2997) {
                    var path = parse_path (d[body:body + size]);
                    if (path != null) {
                        path.id = id;
                        path.name = name;
                        r.paths.add (path);
                    }
                } else if (id == 2999 && size > 0) {
                    r.clipping = pascal (d, body);
                }
                i = body + size + (size & 1);
            }
            return r;
        }

        private static string pascal (uint8[] d, int at) {
            int n = d[at];
            if (at + 1 + n > d.length) return "";
            var sb = new StringBuilder ();
            for (int k = 0; k < n; k++) sb.append_c ((char) d[at + 1 + k]);
            string s = sb.str;
            if (!s.validate ()) s = s.make_valid ();
            return s;
        }

        private static PsPath? parse_path (uint8[] d) {
            var path = new PsPath ();
            PsSubpath? cur = null;
            for (int i = 0; i + 26 <= d.length; i += 26) {
                uint sel = be16 (d, i);
                switch (sel) {
                    case 0:
                    case 3:
                        cur = new PsSubpath ();
                        cur.closed = sel == 0;
                        path.subpaths.add (cur);
                        break;
                    case 1:
                    case 2:
                    case 4:
                    case 5:
                        if (cur == null) break;
                        var k = new PsKnot ();
                        k.in_y = fixed (d, i + 2);
                        k.in_x = fixed (d, i + 6);
                        k.y = fixed (d, i + 10);
                        k.x = fixed (d, i + 14);
                        k.out_y = fixed (d, i + 18);
                        k.out_x = fixed (d, i + 22);
                        cur.knots.add (k);
                        break;
                    default:
                        break;
                }
            }
            int total = 0;
            foreach (var sp in path.subpaths) total += sp.knots.size;
            return total >= 2 ? path : null;
        }

        public static uint8[] encode_path (Gee.List<double?> xy, bool closed) {
            var b = new ByteArray ();
            uint8[] rec = new uint8[26];
            put16 (rec, 0, 6);
            b.append (rec);
            rec = new uint8[26];
            put16 (rec, 0, closed ? 0 : 3);
            put16 (rec, 2, xy.size / 2);
            b.append (rec);
            for (int i = 0; i + 1 < xy.size; i += 2) {
                rec = new uint8[26];
                put16 (rec, 0, closed ? 2 : 5);
                for (int k = 0; k < 3; k++) {
                    put32 (rec, 2 + k * 8, (uint32) (int32) Math.round (xy[i + 1] * 16777216.0));
                    put32 (rec, 6 + k * 8, (uint32) (int32) Math.round (xy[i] * 16777216.0));
                }
                b.append (rec);
            }
            return b.steal ();
        }

        public static uint8[] resource_block (int id, string name, uint8[] body) {
            var b = new ByteArray ();
            b.append ("8BIM".data);
            b.append ({ (uint8) (id >> 8), (uint8) (id & 0xFF) });
            b.append ({ (uint8) name.length });
            b.append (name.data);
            if (((1 + name.length) & 1) == 1) b.append ({ 0 });
            uint8[] sz = new uint8[4];
            put32 (sz, 0, body.length);
            b.append (sz);
            b.append (body);
            if ((body.length & 1) == 1) b.append ({ 0 });
            return b.steal ();
        }

        public static uint8[] with_jpeg_resources (uint8[] jpeg, uint8[] resources) {
            var b = new ByteArray ();
            b.append (jpeg[0:2]);
            var seg = new ByteArray ();
            seg.append ("Photoshop 3.0".data);
            seg.append ({ 0 });
            seg.append (resources);
            int len = (int) seg.len + 2;
            b.append ({ 0xFF, 0xED, (uint8) (len >> 8), (uint8) (len & 0xFF) });
            b.append (seg.data);
            b.append (jpeg[2:jpeg.length]);
            return b.steal ();
        }

        private static void put16 (uint8[] d, int at, uint v) {
            d[at] = (uint8) (v >> 8);
            d[at + 1] = (uint8) (v & 0xFF);
        }

        private static void put32 (uint8[] d, int at, uint32 v) {
            d[at] = (uint8) (v >> 24);
            d[at + 1] = (uint8) ((v >> 16) & 0xFF);
            d[at + 2] = (uint8) ((v >> 8) & 0xFF);
            d[at + 3] = (uint8) (v & 0xFF);
        }
    }
}
