namespace Singularity.Apps.Publish {

    public abstract class PathSink {
        public abstract void move_to (double x, double y);
        public abstract void line_to (double x, double y);
        public abstract void curve_to (double x1, double y1, double x2, double y2, double x, double y);
        public abstract void close_path ();
    }

    public class CairoSink : PathSink {
        private unowned Cairo.Context cr;

        public CairoSink (Cairo.Context cr) {
            this.cr = cr;
        }

        public override void move_to (double x, double y) {
            cr.move_to (x, y);
        }

        public override void line_to (double x, double y) {
            cr.line_to (x, y);
        }

        public override void curve_to (double x1, double y1, double x2, double y2, double x, double y) {
            cr.curve_to (x1, y1, x2, y2, x, y);
        }

        public override void close_path () {
            cr.close_path ();
        }
    }

    public class FlatSink : PathSink {
        public Gee.ArrayList<Point?> points = new Gee.ArrayList<Point?> ();
        private double cx = 0;
        private double cy = 0;

        public override void move_to (double x, double y) {
            points.add (Point (x, y));
            cx = x;
            cy = y;
        }

        public override void line_to (double x, double y) {
            points.add (Point (x, y));
            cx = x;
            cy = y;
        }

        public override void curve_to (double x1, double y1, double x2, double y2, double x, double y) {
            int n = 12;
            for (int i = 1; i <= n; i++) {
                double t = i / (double) n, u = 1 - t;
                points.add (Point (u * u * u * cx + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x, u * u * u * cy + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y));
            }
            cx = x;
            cy = y;
        }

        public override void close_path () {
        }
    }

    public class SvgPath {
        private static bool is_num_start (unichar c) {
            return c.isdigit () || c == '-' || c == '+' || c == '.';
        }

        public static Gee.ArrayList<string> tokens (string d) {
            var list = new Gee.ArrayList<string> ();
            var cur = new StringBuilder ();
            int i = 0;
            unichar c;
            bool has_dot = false, has_exp = false;
            while (d.get_next_char (ref i, out c)) {
                if (c.isalpha () && c != 'e' && c != 'E') {
                    if (cur.len > 0) list.add (cur.str);
                    cur.truncate (0);
                    list.add (c.to_string ());
                    has_dot = has_exp = false;
                } else if (c == ',' || c.isspace ()) {
                    if (cur.len > 0) list.add (cur.str);
                    cur.truncate (0);
                    has_dot = has_exp = false;
                } else if (is_num_start (c) || c == 'e' || c == 'E') {
                    bool split = false;
                    if ((c == '-' || c == '+') && cur.len > 0) {
                        unichar last = cur.str.get_char (cur.str.length - 1);
                        if (last != 'e' && last != 'E') split = true;
                    }
                    if (c == '.' && has_dot && !has_exp) split = true;
                    if (split) {
                        list.add (cur.str);
                        cur.truncate (0);
                        has_dot = has_exp = false;
                    }
                    if (c == '.') has_dot = true;
                    if (c == 'e' || c == 'E') has_exp = true;
                    cur.append_unichar (c);
                }
            }
            if (cur.len > 0) list.add (cur.str);
            return list;
        }

        public static void trace (Cairo.Context cr, string d, double sx, double sy) {
            trace_to (new CairoSink (cr), d, sx, sy);
        }

        public static void trace_to (PathSink cr, string d, double sx, double sy) {
            var t = tokens (d);
            int i = 0;
            string cmd = "";
            double x = 0, y = 0, x0 = 0, y0 = 0, lcx = 0, lcy = 0;
            string prev = "";
            while (i < t.size) {
                string tk = t[i];
                if (tk.length == 1 && tk.get_char (0).isalpha ()) {
                    cmd = tk;
                    i++;
                    if (cmd == "Z" || cmd == "z") {
                        cr.close_path ();
                        x = x0;
                        y = y0;
                        prev = cmd;
                        continue;
                    }
                }
                if (cmd == "") break;
                bool rel = cmd.down () == cmd;
                string up = cmd.up ();
                double[] a = {};
                int need = up == "H" || up == "V" ? 1 : (up == "C" ? 6 : (up == "Q" || up == "S" ? (up == "Q" ? 4 : 4) : 2));
                if (i + need > t.size) break;
                for (int k = 0; k < need; k++) a += double.parse (t[i + k]);
                i += need;
                double bx = rel ? x : 0, by = rel ? y : 0;
                switch (up) {
                    case "M":
                        x = bx + a[0];
                        y = by + a[1];
                        x0 = x;
                        y0 = y;
                        cr.move_to (x * sx, y * sy);
                        cmd = rel ? "l" : "L";
                        break;
                    case "L":
                        x = bx + a[0];
                        y = by + a[1];
                        cr.line_to (x * sx, y * sy);
                        break;
                    case "H":
                        x = (rel ? x : 0) + a[0];
                        cr.line_to (x * sx, y * sy);
                        break;
                    case "V":
                        y = (rel ? y : 0) + a[0];
                        cr.line_to (x * sx, y * sy);
                        break;
                    case "C":
                        lcx = bx + a[2];
                        lcy = by + a[3];
                        cr.curve_to ((bx + a[0]) * sx, (by + a[1]) * sy, lcx * sx, lcy * sy, (bx + a[4]) * sx, (by + a[5]) * sy);
                        x = bx + a[4];
                        y = by + a[5];
                        break;
                    case "S":
                        double rx = prev.up () == "C" || prev.up () == "S" ? 2 * x - lcx : x;
                        double ry = prev.up () == "C" || prev.up () == "S" ? 2 * y - lcy : y;
                        lcx = bx + a[0];
                        lcy = by + a[1];
                        cr.curve_to (rx * sx, ry * sy, lcx * sx, lcy * sy, (bx + a[2]) * sx, (by + a[3]) * sy);
                        x = bx + a[2];
                        y = by + a[3];
                        break;
                    case "Q":
                        double qx = bx + a[0], qy = by + a[1], ex = bx + a[2], ey = by + a[3];
                        cr.curve_to ((x + 2.0 / 3 * (qx - x)) * sx, (y + 2.0 / 3 * (qy - y)) * sy, (ex + 2.0 / 3 * (qx - ex)) * sx, (ey + 2.0 / 3 * (qy - ey)) * sy, ex * sx, ey * sy);
                        x = ex;
                        y = ey;
                        break;
                    default:
                        i = t.size;
                        break;
                }
                prev = up;
            }
        }

        public static Gee.ArrayList<Point?> flatten (string d, double sx, double sy) {
            var f = new FlatSink ();
            trace_to (f, d, sx, sy);
            return f.points;
        }

        public static string bezier_d (Gee.List<Point?> pts, Gee.List<Point?> handles, bool closed, double minx, double miny, double w, double h) {
            int n = pts.size;
            var sb = new StringBuilder ("M %s %s".printf (SvgPath.num ((pts[0].x - minx) / w), SvgPath.num ((pts[0].y - miny) / h)));
            int segs = closed ? n : n - 1;
            for (int i = 0; i < segs; i++) {
                var a = pts[i];
                var b = pts[(i + 1) % n];
                var ha = i < handles.size ? handles[i] : Point (0, 0);
                var hb = (i + 1) % n < handles.size ? handles[(i + 1) % n] : Point (0, 0);
                double c1x = a.x + ha.x, c1y = a.y + ha.y, c2x = b.x - hb.x, c2y = b.y - hb.y;
                sb.append (" C %s %s %s %s %s %s".printf (SvgPath.num ((c1x - minx) / w), SvgPath.num ((c1y - miny) / h), SvgPath.num ((c2x - minx) / w), SvgPath.num ((c2y - miny) / h), SvgPath.num ((b.x - minx) / w), SvgPath.num ((b.y - miny) / h)));
            }
            if (closed) sb.append (" Z");
            return sb.str;
        }

        public static string num (double v) {
            return XmlOut.num (Math.round (v * 100000) / 100000);
        }

        public static string smooth (Gee.List<Point?> pts, bool closed) {
            int n = pts.size;
            if (n < 2) return "";
            var sb = new StringBuilder ("M %s %s".printf (num (pts[0].x), num (pts[0].y)));
            int segs = closed ? n : n - 1;
            for (int i = 0; i < segs; i++) {
                var p0 = pts[closed ? (i - 1 + n) % n : int.max (0, i - 1)];
                var p1 = pts[i];
                var p2 = pts[(i + 1) % n];
                var p3 = pts[closed ? (i + 2) % n : int.min (n - 1, i + 2)];
                double c1x = p1.x + (p2.x - p0.x) / 6, c1y = p1.y + (p2.y - p0.y) / 6;
                double c2x = p2.x - (p3.x - p1.x) / 6, c2y = p2.y - (p3.y - p1.y) / 6;
                sb.append (" C %s %s %s %s %s %s".printf (num (c1x), num (c1y), num (c2x), num (c2y), num (p2.x), num (p2.y)));
            }
            if (closed) sb.append (" Z");
            return sb.str;
        }
    }
}
