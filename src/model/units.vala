namespace Singularity.Apps.Publish {

    public errordomain FormatError {
        INVALID,
        UNSUPPORTED
    }

    public struct Rect {
        public double x;
        public double y;
        public double w;
        public double h;

        public Rect (double x, double y, double w, double h) {
            this.x = x;
            this.y = y;
            this.w = w;
            this.h = h;
        }

        public double x2 () {
            return x + w;
        }

        public double y2 () {
            return y + h;
        }

        public bool contains (double px, double py) {
            return px >= x && px <= x + w && py >= y && py <= y + h;
        }

        public bool intersects (Rect o) {
            return x < o.x + o.w && o.x < x + w && y < o.y + o.h && o.y < y + h;
        }

        public Rect union (Rect o) {
            double nx = double.min (x, o.x), ny = double.min (y, o.y);
            return Rect (nx, ny, double.max (x + w, o.x + o.w) - nx, double.max (y + h, o.y + o.h) - ny);
        }

        public Rect inset (double d) {
            return Rect (x + d, y + d, w - 2 * d, h - 2 * d);
        }

        public bool inside (Rect o) {
            return x >= o.x - 0.01 && y >= o.y - 0.01 && x + w <= o.x + o.w + 0.01 && y + h <= o.y + o.h + 0.01;
        }
    }

    public class Bin {
        public static string head (uint8[] d, int max) {
            int n = int.min (d.length, max);
            var sb = new StringBuilder.sized (n + 1);
            for (int i = 0; i < n; i++) {
                uint8 c = d[i];
                sb.append_c (c >= 32 && c < 127 ? (char) c : ' ');
            }
            return sb.str;
        }
    }

    public class Units {
        public const double PT_PER_MM = 72.0 / 25.4;
        public const double PT_PER_IN = 72.0;
        public const double PT_PER_PICA = 12.0;
        public const double PT_PER_PX = 0.75;

        public static double factor (string unit) {
            switch (unit) {
                case "mm": return PT_PER_MM;
                case "cm": return PT_PER_MM * 10;
                case "in": return PT_PER_IN;
                case "pc": return PT_PER_PICA;
                case "px": return PT_PER_PX;
                default: return 1;
            }
        }

        public static double to_unit (double pt, string unit) {
            return pt / factor (unit);
        }

        public static double from_unit (double v, string unit) {
            return v * factor (unit);
        }

        public static string label (string unit) {
            switch (unit) {
                case "mm": return _("Millimeters");
                case "cm": return _("Centimeters");
                case "in": return _("Inches");
                case "pc": return _("Picas");
                case "px": return _("Pixels");
                default: return _("Points");
            }
        }

        public static string[] all () {
            return { "mm", "cm", "in", "pt", "pc", "px" };
        }

        public static string format (double pt, string unit) {
            double v = to_unit (pt, unit);
            string s = XmlOut.num (Math.round (v * 100) / 100);
            return "%s %s".printf (s, unit);
        }

        public static double parse_length (string text, string default_unit) {
            string t = text.strip ().down ().replace (",", ".");
            string unit = default_unit;
            foreach (string u in new string[] { "mm", "cm", "in", "pt", "pc", "px" }) {
                if (t.has_suffix (u)) {
                    unit = u;
                    t = t.substring (0, t.length - u.length).strip ();
                    break;
                }
            }
            if (t.has_suffix ("\"")) {
                unit = "in";
                t = t.substring (0, t.length - 1);
            }
            double v;
            if (!double.try_parse (t, out v)) return double.NAN;
            return from_unit (v, unit);
        }

        public static double parse_num (string? s, double fallback) {
            if (s == null) return fallback;
            double v;
            if (double.try_parse (s.strip (), out v)) return v;
            return fallback;
        }
    }

    public class PageSize {
        public string id;
        public string name;
        public string category;
        public double width;
        public double height;

        public PageSize (string id, string name, string category, double width, double height) {
            this.id = id;
            this.name = name;
            this.category = category;
            this.width = width;
            this.height = height;
        }

        private static Gee.ArrayList<PageSize>? list = null;

        private static PageSize mm (string id, string name, string cat, double w, double h) {
            return new PageSize (id, name, cat, w * Units.PT_PER_MM, h * Units.PT_PER_MM);
        }

        private static PageSize inch (string id, string name, string cat, double w, double h) {
            return new PageSize (id, name, cat, w * 72, h * 72);
        }

        public static Gee.ArrayList<PageSize> all () {
            if (list != null) return list;
            list = new Gee.ArrayList<PageSize> ();
            string paper = _("Paper");
            list.add (mm ("a3", "A3", paper, 297, 420));
            list.add (mm ("a4", "A4", paper, 210, 297));
            list.add (mm ("a5", "A5", paper, 148, 210));
            list.add (mm ("a6", "A6", paper, 105, 148));
            list.add (mm ("b5", "B5", paper, 176, 250));
            list.add (inch ("letter", _("US Letter"), paper, 8.5, 11));
            list.add (inch ("legal", _("US Legal"), paper, 8.5, 14));
            list.add (inch ("tabloid", _("Tabloid"), paper, 11, 17));
            string cards = _("Cards");
            list.add (mm ("card-eu", _("Business Card (85 × 55 mm)"), cards, 85, 55));
            list.add (inch ("card-us", _("Business Card (3.5 × 2 in)"), cards, 3.5, 2));
            list.add (mm ("postcard-a6", _("Postcard (A6)"), cards, 148, 105));
            list.add (inch ("postcard-us", _("Postcard (6 × 4 in)"), cards, 6, 4));
            list.add (mm ("greeting-a5", _("Folded Card (A5 folded)"), cards, 148, 210));
            list.add (mm ("dl-card", _("Invitation (DL)"), cards, 99, 210));
            string large = _("Posters and Banners");
            list.add (mm ("a2", _("Poster A2"), large, 420, 594));
            list.add (mm ("a1", _("Poster A1"), large, 594, 841));
            list.add (inch ("poster-18x24", _("Poster (18 × 24 in)"), large, 18, 24));
            list.add (inch ("poster-24x36", _("Poster (24 × 36 in)"), large, 24, 36));
            list.add (mm ("rollup", _("Roll-up Banner (850 × 2000 mm)"), large, 850, 2000));
            list.add (inch ("banner-2x6", _("Banner (6 × 2 ft)"), large, 72, 24));
            string env = _("Envelopes");
            list.add (mm ("env-dl", _("Envelope DL"), env, 220, 110));
            list.add (mm ("env-c5", _("Envelope C5"), env, 229, 162));
            list.add (mm ("env-c6", _("Envelope C6"), env, 162, 114));
            list.add (inch ("env-10", _("Envelope #10"), env, 9.5, 4.125));
            return list;
        }

        public static PageSize? find (string id) {
            foreach (var p in all ()) if (p.id == id) return p;
            return null;
        }

        public static PageSize? match (double w, double h) {
            foreach (var p in all ()) {
                if ((Math.fabs (p.width - w) < 1 && Math.fabs (p.height - h) < 1) || (Math.fabs (p.width - h) < 1 && Math.fabs (p.height - w) < 1)) return p;
            }
            return null;
        }
    }
}
