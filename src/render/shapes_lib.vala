namespace Singularity.Apps.Publish {

    public class ShapePreset {
        public string id;
        public string name;
        public string category;

        public ShapePreset (string id, string name, string category) {
            this.id = id;
            this.name = name;
            this.category = category;
        }
    }

    public class ShapeLib {
        private static Gee.ArrayList<ShapePreset>? list = null;

        public static Gee.ArrayList<ShapePreset> all () {
            if (list != null) return list;
            list = new Gee.ArrayList<ShapePreset> ();
            string basic = _("Basic Shapes");
            string arrows = _("Block Arrows");
            string flow = _("Flowchart");
            string stars = _("Stars and Banners");
            string callouts = _("Callouts");
            add ("triangle", _("Triangle"), basic);
            add ("right-triangle", _("Right Triangle"), basic);
            add ("parallelogram", _("Parallelogram"), basic);
            add ("trapezoid", _("Trapezoid"), basic);
            add ("diamond", _("Diamond"), basic);
            add ("pentagon", _("Pentagon"), basic);
            add ("hexagon", _("Hexagon"), basic);
            add ("heptagon", _("Heptagon"), basic);
            add ("octagon", _("Octagon"), basic);
            add ("decagon", _("Decagon"), basic);
            add ("rounded-rect", _("Rounded Rectangle"), basic);
            add ("snip-rect", _("Snipped Rectangle"), basic);
            add ("cross", _("Cross"), basic);
            add ("frame", _("Frame"), basic);
            add ("heart", _("Heart"), basic);
            add ("cloud", _("Cloud"), basic);
            add ("lightning", _("Lightning Bolt"), basic);
            add ("moon", _("Moon"), basic);
            add ("sun", _("Sun"), basic);
            add ("teardrop", _("Teardrop"), basic);
            add ("arc", _("Block Arc"), basic);
            add ("cube", _("Cube"), basic);
            add ("can", _("Can"), basic);
            add ("arrow-right", _("Right Arrow"), arrows);
            add ("arrow-left", _("Left Arrow"), arrows);
            add ("arrow-up", _("Up Arrow"), arrows);
            add ("arrow-down", _("Down Arrow"), arrows);
            add ("arrow-left-right", _("Left-Right Arrow"), arrows);
            add ("arrow-up-down", _("Up-Down Arrow"), arrows);
            add ("arrow-quad", _("Quad Arrow"), arrows);
            add ("arrow-notched", _("Notched Right Arrow"), arrows);
            add ("arrow-striped", _("Striped Right Arrow"), arrows);
            add ("chevron", _("Chevron"), arrows);
            add ("home-plate", _("Pentagon Arrow"), arrows);
            add ("arrow-u-turn", _("U-Turn Arrow"), arrows);
            add ("arrow-bent", _("Bent Arrow"), arrows);
            add ("arrow-callout", _("Right Arrow Callout"), arrows);
            add ("flow-process", _("Process"), flow);
            add ("flow-alternate", _("Alternate Process"), flow);
            add ("flow-decision", _("Decision"), flow);
            add ("flow-data", _("Data"), flow);
            add ("flow-document", _("Document"), flow);
            add ("flow-terminator", _("Terminator"), flow);
            add ("flow-preparation", _("Preparation"), flow);
            add ("flow-manual-input", _("Manual Input"), flow);
            add ("flow-manual-operation", _("Manual Operation"), flow);
            add ("flow-connector", _("Connector"), flow);
            add ("flow-off-page", _("Off-page Connector"), flow);
            add ("flow-card", _("Card"), flow);
            add ("flow-merge", _("Merge"), flow);
            add ("flow-extract", _("Extract"), flow);
            add ("flow-delay", _("Delay"), flow);
            add ("flow-display", _("Display"), flow);
            add ("star-4", _("4-Point Star"), stars);
            add ("star-5", _("5-Point Star"), stars);
            add ("star-6", _("6-Point Star"), stars);
            add ("star-8", _("8-Point Star"), stars);
            add ("star-10", _("10-Point Star"), stars);
            add ("star-12", _("12-Point Star"), stars);
            add ("star-16", _("16-Point Star"), stars);
            add ("star-24", _("24-Point Star"), stars);
            add ("star-32", _("32-Point Star"), stars);
            add ("explosion-1", _("Explosion 1"), stars);
            add ("explosion-2", _("Explosion 2"), stars);
            add ("wave", _("Wave"), stars);
            add ("double-wave", _("Double Wave"), stars);
            add ("ribbon", _("Ribbon"), stars);
            add ("scroll", _("Horizontal Scroll"), stars);
            add ("callout-rect", _("Rectangular Callout"), callouts);
            add ("callout-rounded", _("Rounded Rectangular Callout"), callouts);
            add ("callout-oval", _("Oval Callout"), callouts);
            add ("callout-cloud", _("Cloud Callout"), callouts);
            add ("callout-line", _("Line Callout"), callouts);
            return list;
        }

        private static void add (string id, string name, string category) {
            list.add (new ShapePreset (id, name, category));
        }

        public static ShapePreset? find (string id) {
            foreach (var p in all ()) if (p.id == id) return p;
            return null;
        }

        public static Gee.ArrayList<string> categories () {
            var l = new Gee.ArrayList<string> ();
            foreach (var p in all ()) if (!l.contains (p.category)) l.add (p.category);
            return l;
        }

        private static void arc (Gee.ArrayList<Point?> pts, double cx, double cy, double rx, double ry, double a0, double a1, int steps = 16) {
            for (int i = 0; i <= steps; i++) {
                double t = a0 + (a1 - a0) * i / steps;
                pts.add (Point (cx + rx * Math.cos (t), cy + ry * Math.sin (t)));
            }
        }

        private static Gee.ArrayList<Point?> poly (double[] xy) {
            var pts = new Gee.ArrayList<Point?> ();
            for (int i = 0; i + 1 < xy.length; i += 2) pts.add (Point (xy[i], xy[i + 1]));
            return pts;
        }

        private static Gee.ArrayList<Point?> regular (int n, double rot = -Math.PI / 2) {
            var pts = new Gee.ArrayList<Point?> ();
            for (int i = 0; i < n; i++) {
                double t = rot + 2 * Math.PI * i / n;
                pts.add (Point (0.5 + 0.5 * Math.cos (t), 0.5 + 0.5 * Math.sin (t)));
            }
            return pts;
        }

        public static Gee.ArrayList<Point?> star (int n, double inner) {
            var pts = new Gee.ArrayList<Point?> ();
            for (int i = 0; i < n * 2; i++) {
                double t = -Math.PI / 2 + Math.PI * i / n;
                double f = i % 2 == 0 ? 1 : inner;
                pts.add (Point (0.5 + 0.5 * f * Math.cos (t), 0.5 + 0.5 * f * Math.sin (t)));
            }
            return pts;
        }

        private static Gee.ArrayList<Point?> rounded (double r, double ry = -1) {
            if (ry < 0) ry = r;
            var pts = new Gee.ArrayList<Point?> ();
            arc (pts, 1 - r, ry, r, ry, -Math.PI / 2, 0, 8);
            arc (pts, 1 - r, 1 - ry, r, ry, 0, Math.PI / 2, 8);
            arc (pts, r, 1 - ry, r, ry, Math.PI / 2, Math.PI, 8);
            arc (pts, r, ry, r, ry, Math.PI, 3 * Math.PI / 2, 8);
            return pts;
        }

        private static Gee.ArrayList<Point?> ellipse () {
            var pts = new Gee.ArrayList<Point?> ();
            arc (pts, 0.5, 0.5, 0.5, 0.5, 0, 2 * Math.PI * 47 / 48, 47);
            return pts;
        }

        private static Gee.ArrayList<Point?> wavy (double amp, bool top, bool bottom) {
            var pts = new Gee.ArrayList<Point?> ();
            int n = 24;
            for (int i = 0; i <= n; i++) {
                double x = (double) i / n;
                pts.add (Point (x, amp + (top ? amp * Math.sin (2 * Math.PI * x) : -amp)));
            }
            for (int i = n; i >= 0; i--) {
                double x = (double) i / n;
                pts.add (Point (x, 1 - amp + (bottom ? amp * Math.sin (2 * Math.PI * x) : amp)));
            }
            return pts;
        }

        private static Gee.ArrayList<Point?> cloud () {
            var pts = new Gee.ArrayList<Point?> ();
            double[] cx = { 0.22, 0.42, 0.66, 0.84, 0.8, 0.56, 0.3, 0.14 };
            double[] cy = { 0.36, 0.22, 0.2, 0.4, 0.68, 0.82, 0.8, 0.6 };
            double[] r = { 0.18, 0.2, 0.2, 0.17, 0.17, 0.18, 0.18, 0.16 };
            int n = cx.length;
            for (int i = 0; i < n; i++) {
                double a = Math.atan2 (cy[i] - 0.5, cx[i] - 0.5);
                arc (pts, cx[i], cy[i], r[i], r[i], a - 1.4, a + 1.4, 10);
            }
            return pts;
        }

        private static Gee.ArrayList<Point?> heart () {
            var pts = new Gee.ArrayList<Point?> ();
            for (int i = 0; i < 64; i++) {
                double t = 2 * Math.PI * i / 64;
                double x = 16 * Math.pow (Math.sin (t), 3);
                double y = 13 * Math.cos (t) - 5 * Math.cos (2 * t) - 2 * Math.cos (3 * t) - Math.cos (4 * t);
                pts.add (Point (0.5 + x / 34, 0.46 - y / 32));
            }
            return pts;
        }

        public static Gee.ArrayList<Point?> points (string id) {
            switch (id) {
                case "triangle": return poly ({ 0.5, 0, 1, 1, 0, 1 });
                case "right-triangle": return poly ({ 0, 0, 1, 1, 0, 1 });
                case "parallelogram": return poly ({ 0.25, 0, 1, 0, 0.75, 1, 0, 1 });
                case "trapezoid": return poly ({ 0.2, 0, 0.8, 0, 1, 1, 0, 1 });
                case "diamond": return poly ({ 0.5, 0, 1, 0.5, 0.5, 1, 0, 0.5 });
                case "pentagon": return regular (5);
                case "hexagon": return poly ({ 0.25, 0, 0.75, 0, 1, 0.5, 0.75, 1, 0.25, 1, 0, 0.5 });
                case "heptagon": return regular (7);
                case "octagon": return poly ({ 0.3, 0, 0.7, 0, 1, 0.3, 1, 0.7, 0.7, 1, 0.3, 1, 0, 0.7, 0, 0.3 });
                case "decagon": return regular (10);
                case "rounded-rect": return rounded (0.16);
                case "snip-rect": return poly ({ 0, 0, 0.8, 0, 1, 0.2, 1, 1, 0, 1 });
                case "cross": return poly ({ 0.33, 0, 0.67, 0, 0.67, 0.33, 1, 0.33, 1, 0.67, 0.67, 0.67, 0.67, 1, 0.33, 1, 0.33, 0.67, 0, 0.67, 0, 0.33, 0.33, 0.33 });
                case "frame": return poly ({ 0, 0, 1, 0, 1, 1, 0, 1, 0, 0, 0.12, 0.12, 0.12, 0.88, 0.88, 0.88, 0.88, 0.12, 0.12, 0.12 });
                case "heart": return heart ();
                case "cloud": return cloud ();
                case "lightning": return poly ({ 0.38, 0, 0.72, 0.3, 0.58, 0.36, 0.9, 0.66, 0.74, 0.72, 1, 1, 0.42, 0.76, 0.56, 0.7, 0.2, 0.46, 0.36, 0.4, 0, 0.14 });
                case "moon":
                    var m = new Gee.ArrayList<Point?> ();
                    arc (m, 1, 0.5, 1, 0.5, Math.PI / 2, 3 * Math.PI / 2, 24);
                    arc (m, 1.05, 0.5, 0.62, 0.42, 3 * Math.PI / 2 - 0.3, Math.PI / 2 + 0.3, 24);
                    return m;
                case "sun":
                    var s = new Gee.ArrayList<Point?> ();
                    for (int i = 0; i < 32; i++) {
                        double t = -Math.PI / 2 + 2 * Math.PI * i / 32;
                        double f = i % 2 == 0 ? 0.5 : 0.36;
                        s.add (Point (0.5 + f * Math.cos (t), 0.5 + f * Math.sin (t)));
                    }
                    return s;
                case "teardrop":
                    var td = new Gee.ArrayList<Point?> ();
                    arc (td, 0.5, 0.5, 0.5, 0.5, 0, 1.5 * Math.PI, 36);
                    td.add (Point (1, 0));
                    return td;
                case "arc":
                    var ba = new Gee.ArrayList<Point?> ();
                    arc (ba, 0.5, 0.5, 0.5, 0.5, Math.PI, 2 * Math.PI, 24);
                    arc (ba, 0.5, 0.5, 0.3, 0.3, 2 * Math.PI, Math.PI, 24);
                    return ba;
                case "cube": return poly ({ 0, 0.25, 0.25, 0, 1, 0, 1, 0.75, 0.75, 1, 0, 1, 0, 0.25, 0.75, 0.25, 0.75, 1, 0.75, 0.25, 1, 0 });
                case "can":
                    var c = new Gee.ArrayList<Point?> ();
                    arc (c, 0.5, 0.12, 0.5, 0.12, Math.PI, 0, 16);
                    arc (c, 0.5, 0.88, 0.5, 0.12, 0, Math.PI, 16);
                    return c;
                case "arrow-right": return poly ({ 0, 0.25, 0.6, 0.25, 0.6, 0, 1, 0.5, 0.6, 1, 0.6, 0.75, 0, 0.75 });
                case "arrow-left": return poly ({ 1, 0.25, 0.4, 0.25, 0.4, 0, 0, 0.5, 0.4, 1, 0.4, 0.75, 1, 0.75 });
                case "arrow-up": return poly ({ 0.25, 1, 0.25, 0.4, 0, 0.4, 0.5, 0, 1, 0.4, 0.75, 0.4, 0.75, 1 });
                case "arrow-down": return poly ({ 0.25, 0, 0.25, 0.6, 0, 0.6, 0.5, 1, 1, 0.6, 0.75, 0.6, 0.75, 0 });
                case "arrow-left-right": return poly ({ 0, 0.5, 0.25, 0, 0.25, 0.25, 0.75, 0.25, 0.75, 0, 1, 0.5, 0.75, 1, 0.75, 0.75, 0.25, 0.75, 0.25, 1 });
                case "arrow-up-down": return poly ({ 0.5, 0, 1, 0.25, 0.75, 0.25, 0.75, 0.75, 1, 0.75, 0.5, 1, 0, 0.75, 0.25, 0.75, 0.25, 0.25, 0, 0.25 });
                case "arrow-quad": return poly ({ 0.5, 0, 0.65, 0.18, 0.57, 0.18, 0.57, 0.43, 0.82, 0.43, 0.82, 0.35, 1, 0.5, 0.82, 0.65, 0.82, 0.57, 0.57, 0.57, 0.57, 0.82, 0.65, 0.82, 0.5, 1, 0.35, 0.82, 0.43, 0.82, 0.43, 0.57, 0.18, 0.57, 0.18, 0.65, 0, 0.5, 0.18, 0.35, 0.18, 0.43, 0.43, 0.43, 0.43, 0.18, 0.35, 0.18 });
                case "arrow-notched": return poly ({ 0, 0.25, 0.6, 0.25, 0.6, 0, 1, 0.5, 0.6, 1, 0.6, 0.75, 0, 0.75, 0.15, 0.5 });
                case "arrow-striped": return poly ({ 0.16, 0.25, 0.6, 0.25, 0.6, 0, 1, 0.5, 0.6, 1, 0.6, 0.75, 0.16, 0.75 });
                case "chevron": return poly ({ 0, 0, 0.7, 0, 1, 0.5, 0.7, 1, 0, 1, 0.3, 0.5 });
                case "home-plate": return poly ({ 0, 0, 0.7, 0, 1, 0.5, 0.7, 1, 0, 1 });
                case "arrow-u-turn":
                    var u = new Gee.ArrayList<Point?> ();
                    u.add (Point (0, 1));
                    arc (u, 0.4, 0.4, 0.4, 0.4, Math.PI, 2 * Math.PI, 16);
                    u.add (Point (0.8, 0.6));
                    u.add (Point (1, 0.6));
                    u.add (Point (0.7, 0.9));
                    u.add (Point (0.4, 0.6));
                    u.add (Point (0.6, 0.6));
                    arc (u, 0.4, 0.4, 0.2, 0.2, 2 * Math.PI, Math.PI, 16);
                    u.add (Point (0.2, 1));
                    return u;
                case "arrow-bent": return poly ({ 0, 1, 0, 0.35, 0.65, 0.35, 0.65, 0.1, 1, 0.45, 0.65, 0.8, 0.65, 0.55, 0.22, 0.55, 0.22, 1 });
                case "arrow-callout": return poly ({ 0, 0, 0.6, 0, 0.6, 0.35, 0.8, 0.35, 0.8, 0.2, 1, 0.5, 0.8, 0.8, 0.8, 0.65, 0.6, 0.65, 0.6, 1, 0, 1 });
                case "flow-process": return poly ({ 0, 0, 1, 0, 1, 1, 0, 1 });
                case "flow-alternate": return rounded (0.12);
                case "flow-decision": return poly ({ 0.5, 0, 1, 0.5, 0.5, 1, 0, 0.5 });
                case "flow-data": return poly ({ 0.2, 0, 1, 0, 0.8, 1, 0, 1 });
                case "flow-document":
                    var d = new Gee.ArrayList<Point?> ();
                    d.add (Point (0, 0));
                    d.add (Point (1, 0));
                    for (int i = 0; i <= 24; i++) {
                        double x = 1 - (double) i / 24;
                        d.add (Point (x, 0.86 + 0.1 * Math.sin (2 * Math.PI * x)));
                    }
                    return d;
                case "flow-terminator": return rounded (0.25, 0.5);
                case "flow-preparation": return poly ({ 0.2, 0, 0.8, 0, 1, 0.5, 0.8, 1, 0.2, 1, 0, 0.5 });
                case "flow-manual-input": return poly ({ 0, 0.2, 1, 0, 1, 1, 0, 1 });
                case "flow-manual-operation": return poly ({ 0, 0, 1, 0, 0.8, 1, 0.2, 1 });
                case "flow-connector": return ellipse ();
                case "flow-off-page": return poly ({ 0, 0, 1, 0, 1, 0.8, 0.5, 1, 0, 0.8 });
                case "flow-card": return poly ({ 0.2, 0, 1, 0, 1, 1, 0, 1, 0, 0.2 });
                case "flow-merge": return poly ({ 0, 0, 1, 0, 0.5, 1 });
                case "flow-extract": return poly ({ 0.5, 0, 1, 1, 0, 1 });
                case "flow-delay":
                    var dl = new Gee.ArrayList<Point?> ();
                    dl.add (Point (0, 0));
                    arc (dl, 0.5, 0.5, 0.5, 0.5, -Math.PI / 2, Math.PI / 2, 24);
                    dl.add (Point (0, 1));
                    return dl;
                case "flow-display":
                    var ds = new Gee.ArrayList<Point?> ();
                    ds.add (Point (0, 0.5));
                    ds.add (Point (0.2, 0));
                    arc (ds, 0.8, 0.5, 0.2, 0.5, -Math.PI / 2, Math.PI / 2, 16);
                    ds.add (Point (0.2, 1));
                    return ds;
                case "star-4": return star (4, 0.38);
                case "star-5": return star (5, 0.38);
                case "star-6": return star (6, 0.5);
                case "star-8": return star (8, 0.6);
                case "star-10": return star (10, 0.7);
                case "star-12": return star (12, 0.72);
                case "star-16": return star (16, 0.78);
                case "star-24": return star (24, 0.8);
                case "star-32": return star (32, 0.82);
                case "explosion-1": return poly ({ 0.5, 0.05, 0.6, 0.3, 0.86, 0.12, 0.78, 0.4, 1, 0.45, 0.8, 0.6, 0.95, 0.88, 0.66, 0.76, 0.56, 1, 0.44, 0.78, 0.18, 0.95, 0.24, 0.66, 0, 0.58, 0.18, 0.42, 0.05, 0.18, 0.34, 0.28 });
                case "explosion-2": return poly ({ 0.42, 0, 0.55, 0.24, 0.74, 0.04, 0.72, 0.3, 1, 0.2, 0.84, 0.44, 0.98, 0.62, 0.76, 0.66, 0.86, 0.96, 0.6, 0.78, 0.46, 1, 0.38, 0.76, 0.1, 0.9, 0.2, 0.64, 0, 0.54, 0.2, 0.4, 0.04, 0.16, 0.3, 0.24 });
                case "wave": return wavy (0.1, true, true);
                case "double-wave": return wavy (0.14, true, true);
                case "ribbon": return poly ({ 0, 0.2, 0.2, 0.2, 0.2, 0, 0.8, 0, 0.8, 0.2, 1, 0.2, 0.9, 0.5, 1, 0.8, 0.8, 0.8, 0.8, 0.6, 0.2, 0.6, 0.2, 0.8, 0, 0.8, 0.1, 0.5 });
                case "scroll":
                    var sc = new Gee.ArrayList<Point?> ();
                    arc (sc, 0.06, 0.2, 0.06, 0.08, Math.PI / 2, 3 * Math.PI / 2, 8);
                    sc.add (Point (0.94, 0.12));
                    arc (sc, 0.94, 0.12, 0.06, 0.08, 3 * Math.PI / 2, 5 * Math.PI / 2, 8);
                    sc.add (Point (0.94, 0.8));
                    arc (sc, 0.94, 0.88, 0.06, 0.08, -Math.PI / 2, Math.PI / 2, 8);
                    sc.add (Point (0.06, 0.96));
                    arc (sc, 0.06, 0.88, 0.06, 0.08, Math.PI / 2, 3 * Math.PI / 2, 8);
                    return sc;
                case "callout-rect": return poly ({ 0, 0, 1, 0, 1, 0.75, 0.45, 0.75, 0.2, 1, 0.25, 0.75, 0, 0.75 });
                case "callout-rounded":
                    var cr = new Gee.ArrayList<Point?> ();
                    arc (cr, 0.88, 0.12, 0.12, 0.12, -Math.PI / 2, 0, 6);
                    arc (cr, 0.88, 0.63, 0.12, 0.12, 0, Math.PI / 2, 6);
                    cr.add (Point (0.45, 0.75));
                    cr.add (Point (0.2, 1));
                    cr.add (Point (0.25, 0.75));
                    arc (cr, 0.12, 0.63, 0.12, 0.12, Math.PI / 2, Math.PI, 6);
                    arc (cr, 0.12, 0.12, 0.12, 0.12, Math.PI, 3 * Math.PI / 2, 6);
                    return cr;
                case "callout-oval":
                    var co = new Gee.ArrayList<Point?> ();
                    arc (co, 0.5, 0.4, 0.5, 0.4, 2.1, 2 * Math.PI + 1.75, 40);
                    co.add (Point (0.18, 1));
                    return co;
                case "callout-cloud":
                    var cc = cloud ();
                    var scaled = new Gee.ArrayList<Point?> ();
                    foreach (var p in cc) scaled.add (Point (p.x, p.y * 0.8));
                    scaled.add (Point (0.22, 0.72));
                    scaled.add (Point (0.1, 0.98));
                    scaled.add (Point (0.3, 0.7));
                    return scaled;
                case "callout-line": return poly ({ 0.25, 0, 1, 0, 1, 0.6, 0.25, 0.6, 0.25, 0.35, 0, 1, 0.25, 0.25 });
                case "ellipse": return ellipse ();
                case "star": return star (5, 0.38);
                default: return poly ({ 0, 0, 1, 0, 1, 1, 0, 1 });
            }
        }

        public static ShapeItem make (Publication pub, string id, double x, double y, double w, double h) {
            var s = new ShapeItem (ShapeKind.PATH);
            s.id = pub.next_id ();
            s.name = find (id) != null ? find (id).name : "";
            s.x = x;
            s.y = y;
            s.w = w;
            s.h = h;
            s.closed = true;
            s.points.add_all (points (id));
            s.layer = pub.default_layer ().id;
            s.stroke = new Stroke.with (ColorRef.BLACK, 1);
            s.fill = new Fill.solid (ColorRef.swatch ("Cyan", 20));
            return s;
        }

        public static void path (Cairo.Context cr, string id, double w, double h) {
            var pts = points (id);
            if (pts.size == 0) return;
            cr.move_to (pts[0].x * w, pts[0].y * h);
            for (int i = 1; i < pts.size; i++) cr.line_to (pts[i].x * w, pts[i].y * h);
            cr.close_path ();
        }

        public static string[] clip_shapes () {
            return { "", "ellipse", "rounded-rect", "triangle", "diamond", "pentagon", "hexagon", "octagon", "star-5", "star-8", "heart", "cloud", "flow-document", "snip-rect", "chevron", "arrow-right", "explosion-1" };
        }

        public static string clip_label (string id) {
            if (id == "") return _("None");
            if (id == "ellipse") return _("Oval");
            var p = find (id);
            return p != null ? p.name : id;
        }
    }
}
