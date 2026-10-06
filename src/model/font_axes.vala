namespace Singularity.Apps.Publish {

    public class FontAxis {
        public string tag;
        public double min;
        public double def;
        public double max;

        public FontAxis (string tag, double min, double def, double max) {
            this.tag = tag;
            this.min = min;
            this.def = def;
            this.max = max;
        }

        public string label () {
            switch (tag) {
                case "wght": return _("Weight");
                case "wdth": return _("Width");
                case "slnt": return _("Slant");
                case "ital": return _("Italic");
                case "opsz": return _("Optical Size");
                case "GRAD": return _("Grade");
                default: return tag;
            }
        }
    }

    public class FontAxes {
        private static Gee.HashMap<string, Gee.ArrayList<FontAxis>>? cache = null;

        private static uint32 u32 (uint8[] d, int at) {
            return ((uint32) d[at] << 24) | ((uint32) d[at + 1] << 16) | ((uint32) d[at + 2] << 8) | d[at + 3];
        }

        private static uint u16 (uint8[] d, int at) {
            return ((uint) d[at] << 8) | d[at + 1];
        }

        private static double fixed (uint8[] d, int at) {
            return ((int32) u32 (d, at)) / 65536.0;
        }

        public static Gee.ArrayList<FontAxis> parse (uint8[] d) {
            var list = new Gee.ArrayList<FontAxis> ();
            if (d.length < 12) return list;
            int base_off = 0;
            if (d[0] == 't' && d[1] == 't' && d[2] == 'c' && d[3] == 'f') {
                if (d.length < 16) return list;
                base_off = (int) u32 (d, 12);
            }
            if (base_off + 12 > d.length) return list;
            int tables = (int) u16 (d, base_off + 4);
            for (int i = 0; i < tables; i++) {
                int rec = base_off + 12 + i * 16;
                if (rec + 16 > d.length) break;
                if (d[rec] != 'f' || d[rec + 1] != 'v' || d[rec + 2] != 'a' || d[rec + 3] != 'r') continue;
                int off = (int) u32 (d, rec + 8);
                if (off + 16 > d.length) break;
                int axes_off = off + (int) u16 (d, off + 4);
                int count = (int) u16 (d, off + 8);
                int size = (int) u16 (d, off + 10);
                for (int a = 0; a < count; a++) {
                    int at = axes_off + a * size;
                    if (at + 20 > d.length) break;
                    var sb = new StringBuilder ();
                    for (int k = 0; k < 4; k++) sb.append_c ((char) d[at + k]);
                    list.add (new FontAxis (sb.str, fixed (d, at + 4), fixed (d, at + 8), fixed (d, at + 12)));
                }
                break;
            }
            return list;
        }

        public static string? file_for (string family) {
            foreach (string f in FontPackager.files_for (family)) {
                try {
                    uint8[] data;
                    FileUtils.get_data (f, out data);
                    if (parse (data).size > 0) return f;
                } catch (Error e) {
                }
            }
            return null;
        }

        public static Gee.ArrayList<FontAxis> for_family (string family) {
            if (cache == null) cache = new Gee.HashMap<string, Gee.ArrayList<FontAxis>> ();
            if (cache.has_key (family)) return cache[family];
            var list = new Gee.ArrayList<FontAxis> ();
            string? file = file_for (family);
            if (file != null) {
                try {
                    uint8[] data;
                    FileUtils.get_data (file, out data);
                    list = parse (data);
                } catch (Error e) {
                }
            }
            cache[family] = list;
            return list;
        }

        public static Gee.HashMap<string, double?> values (string? variations) {
            var map = new Gee.HashMap<string, double?> ();
            if (variations == null) return map;
            foreach (string part in variations.split (",")) {
                string[] kv = part.strip ().split ("=");
                if (kv.length != 2 || kv[0].strip ().length != 4) continue;
                map[kv[0].strip ()] = Units.parse_num (kv[1], 0);
            }
            return map;
        }

        public static string join (Gee.Map<string, double?> map) {
            var keys = new Gee.ArrayList<string> ();
            keys.add_all (map.keys);
            keys.sort ();
            string[] parts = {};
            foreach (string k in keys) parts += "%s=%s".printf (k, XmlOut.num (map[k]));
            return string.joinv (",", parts);
        }

        public static uint8[] build_fvar_font (FontAxis[] axes) {
            var b = new ByteArray ();
            uint8[] head = new uint8[12];
            head[0] = 0;
            head[1] = 1;
            head[5] = 1;
            b.append (head);
            int fvar_off = 12 + 16;
            uint8[] rec = new uint8[16];
            rec[0] = 'f';
            rec[1] = 'v';
            rec[2] = 'a';
            rec[3] = 'r';
            put32 (rec, 8, fvar_off);
            put32 (rec, 12, 16 + axes.length * 20);
            b.append (rec);
            uint8[] fv = new uint8[16];
            fv[1] = 1;
            fv[5] = 16;
            fv[9] = (uint8) axes.length;
            fv[11] = 20;
            b.append (fv);
            foreach (var a in axes) {
                uint8[] ax = new uint8[20];
                for (int k = 0; k < 4; k++) ax[k] = (uint8) a.tag[k];
                put32 (ax, 4, (uint32) (int32) Math.round (a.min * 65536));
                put32 (ax, 8, (uint32) (int32) Math.round (a.def * 65536));
                put32 (ax, 12, (uint32) (int32) Math.round (a.max * 65536));
                b.append (ax);
            }
            return b.steal ();
        }

        private static void put32 (uint8[] d, int at, uint32 v) {
            d[at] = (uint8) (v >> 24);
            d[at + 1] = (uint8) ((v >> 16) & 0xFF);
            d[at + 2] = (uint8) ((v >> 8) & 0xFF);
            d[at + 3] = (uint8) (v & 0xFF);
        }
    }
}
