namespace Singularity.Apps.Publish {

    public struct Rgba {
        public double r;
        public double g;
        public double b;
        public double a;

        public Rgba (double r, double g, double b, double a = 1) {
            this.r = r;
            this.g = g;
            this.b = b;
            this.a = a;
        }

        public string to_hex () {
            return "#%02x%02x%02x".printf ((int) Math.round (r.clamp (0, 1) * 255), (int) Math.round (g.clamp (0, 1) * 255), (int) Math.round (b.clamp (0, 1) * 255));
        }

        public static bool parse_hex (string s, out Rgba c) {
            c = Rgba (0, 0, 0, 1);
            string h = s.strip ();
            if (h.has_prefix ("#")) h = h.substring (1);
            if (h.length == 3) h = "%c%c%c%c%c%c".printf (h[0], h[0], h[1], h[1], h[2], h[2]);
            if (h.length != 6 && h.length != 8) return false;
            uint64 v;
            if (!uint64.try_parse (h, out v, null, 16)) return false;
            if (h.length == 8) {
                c = Rgba (((v >> 24) & 0xff) / 255.0, ((v >> 16) & 0xff) / 255.0, ((v >> 8) & 0xff) / 255.0, (v & 0xff) / 255.0);
            } else {
                c = Rgba (((v >> 16) & 0xff) / 255.0, ((v >> 8) & 0xff) / 255.0, (v & 0xff) / 255.0, 1);
            }
            return true;
        }

        public Rgba mix (Rgba o, double t) {
            return Rgba (r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t, a + (o.a - a) * t);
        }
    }

    public enum ColorModel {
        RGB,
        CMYK;

        public string to_string () {
            return this == CMYK ? "cmyk" : "rgb";
        }

        public static ColorModel parse (string s) {
            return s == "cmyk" ? CMYK : RGB;
        }
    }

    public class ColorMath {
        public static Rgba cmyk_to_rgb (double c, double m, double y, double k) {
            double r = (1 - c) * (1 - k);
            double g = (1 - m) * (1 - k);
            double b = (1 - y) * (1 - k);
            double rich = c * m * y * k;
            r -= rich * 0.08;
            g -= rich * 0.08;
            b -= rich * 0.08;
            double cm = c * m * (1 - k);
            b += cm * 0.12;
            double my = m * y * (1 - k);
            r -= my * 0.02;
            return Rgba (r.clamp (0, 1), g.clamp (0, 1), b.clamp (0, 1), 1);
        }

        public static void rgb_to_cmyk (double r, double g, double b, out double c, out double m, out double y, out double k) {
            k = 1 - double.max (r, double.max (g, b));
            if (k >= 0.9999) {
                c = m = y = 0;
                k = 1;
                return;
            }
            c = (1 - r - k) / (1 - k);
            m = (1 - g - k) / (1 - k);
            y = (1 - b - k) / (1 - k);
        }

        public static Rgba tint (Rgba c, double pct) {
            double t = (pct / 100).clamp (0, 1);
            return Rgba (1 - (1 - c.r) * t, 1 - (1 - c.g) * t, 1 - (1 - c.b) * t, c.a);
        }
    }

    public class Swatch {
        public string name;
        public string group = "";
        public string tint_of = "";
        public double tint = 100;
        public ColorModel model = ColorModel.RGB;
        public bool spot = false;
        public double r;
        public double g;
        public double b;
        public double c;
        public double m;
        public double y;
        public double k;

        public Swatch.rgb (string name, double r, double g, double b) {
            this.name = name;
            model = ColorModel.RGB;
            this.r = r;
            this.g = g;
            this.b = b;
            ColorMath.rgb_to_cmyk (r, g, b, out c, out m, out y, out k);
        }

        public Swatch.hex (string name, string hex) {
            this.name = name;
            Rgba v;
            Rgba.parse_hex (hex, out v);
            r = v.r;
            g = v.g;
            b = v.b;
            ColorMath.rgb_to_cmyk (r, g, b, out c, out m, out y, out k);
        }

        public Swatch.cmyk (string name, double c, double m, double y, double k, bool spot = false) {
            this.name = name;
            model = ColorModel.CMYK;
            this.spot = spot;
            this.c = c;
            this.m = m;
            this.y = y;
            this.k = k;
            var v = ColorMath.cmyk_to_rgb (c, m, y, k);
            r = v.r;
            g = v.g;
            b = v.b;
        }

        public Rgba rgba () {
            if (model == ColorModel.CMYK) return ColorMath.cmyk_to_rgb (c, m, y, k);
            return Rgba (r, g, b, 1);
        }

        public Swatch clone () {
            var s = new Swatch.rgb (name, r, g, b);
            s.model = model;
            s.spot = spot;
            s.c = c;
            s.m = m;
            s.y = y;
            s.k = k;
            s.group = group;
            s.tint_of = tint_of;
            s.tint = tint;
            return s;
        }

        public string describe () {
            if (tint_of != "") return _("%d%% of %s").printf ((int) Math.round (tint), tint_of);
            if (model == ColorModel.CMYK) {
                return "C%d M%d Y%d K%d".printf ((int) Math.round (c * 100), (int) Math.round (m * 100), (int) Math.round (y * 100), (int) Math.round (k * 100));
            }
            return "R%d G%d B%d".printf ((int) Math.round (r * 255), (int) Math.round (g * 255), (int) Math.round (b * 255));
        }
    }

    public class ColorRef {
        public const string NONE = "";
        public const string PAPER = "swatch:Paper";
        public const string BLACK = "swatch:Black";

        public static string swatch (string name, double tint = 100) {
            if (tint >= 99.99) return "swatch:" + name;
            return "swatch:%s@%s".printf (name, XmlOut.num (Math.round (tint)));
        }

        public static bool is_swatch (string spec) {
            return spec.has_prefix ("swatch:");
        }

        public static string swatch_name (string spec) {
            if (!spec.has_prefix ("swatch:")) return "";
            string n = spec.substring (7);
            int at = n.last_index_of ("@");
            return at >= 0 ? n.substring (0, at) : n;
        }

        public static double tint_of (string spec) {
            if (!spec.has_prefix ("swatch:")) return 100;
            int at = spec.last_index_of ("@");
            if (at < 0) return 100;
            return Units.parse_num (spec.substring (at + 1), 100);
        }

        public static string with_tint (string spec, double tint) {
            if (!is_swatch (spec)) return spec;
            return swatch (swatch_name (spec), tint);
        }
    }
}
