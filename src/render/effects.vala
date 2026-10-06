namespace Singularity.Apps.Publish {

    public class FxRender {
        private static Gee.HashMap<string, Cairo.ImageSurface>? textures = null;
        private static Gee.HashMap<string, Cairo.ImageSurface>? adjusted = null;

        public static string[] pattern_ids () {
            return { "horizontal", "vertical", "diag-up", "diag-down", "grid", "diag-grid", "dots-10", "dots-25", "dots-50", "dots-75", "small-grid", "large-grid", "checker-small", "checker-large", "brick", "brick-diag", "weave", "zigzag", "wave", "plaid", "shingle", "trellis", "divot", "dash-h", "dash-v", "dotted-grid", "diamond-outline", "diamond-solid", "confetti", "sphere", "wide-horizontal", "wide-vertical" };
        }

        public static string pattern_label (string id) {
            switch (id) {
                case "horizontal": return _("Horizontal Lines");
                case "vertical": return _("Vertical Lines");
                case "diag-up": return _("Upward Diagonal");
                case "diag-down": return _("Downward Diagonal");
                case "grid": return _("Cross");
                case "diag-grid": return _("Diagonal Cross");
                case "dots-10": return _("10% Dots");
                case "dots-25": return _("25% Dots");
                case "dots-50": return _("50% Dots");
                case "dots-75": return _("75% Dots");
                case "small-grid": return _("Small Grid");
                case "large-grid": return _("Large Grid");
                case "checker-small": return _("Small Checkerboard");
                case "checker-large": return _("Large Checkerboard");
                case "brick": return _("Horizontal Brick");
                case "brick-diag": return _("Diagonal Brick");
                case "weave": return _("Weave");
                case "zigzag": return _("Zig Zag");
                case "wave": return _("Wave");
                case "plaid": return _("Plaid");
                case "shingle": return _("Shingle");
                case "trellis": return _("Trellis");
                case "divot": return _("Divot");
                case "dash-h": return _("Dashed Horizontal");
                case "dash-v": return _("Dashed Vertical");
                case "dotted-grid": return _("Dotted Grid");
                case "diamond-outline": return _("Outlined Diamond");
                case "diamond-solid": return _("Solid Diamond");
                case "confetti": return _("Confetti");
                case "sphere": return _("Sphere");
                case "wide-horizontal": return _("Wide Horizontal");
                case "wide-vertical": return _("Wide Vertical");
                default: return id;
            }
        }

        private static void draw_pattern_cell (Cairo.Context c, string id, double s) {
            double lw = s / 8;
            c.set_line_width (lw);
            switch (id) {
                case "horizontal":
                    c.rectangle (0, s / 2 - lw / 2, s, lw);
                    c.fill ();
                    break;
                case "wide-horizontal":
                    c.rectangle (0, s / 4, s, s / 2);
                    c.fill ();
                    break;
                case "vertical":
                    c.rectangle (s / 2 - lw / 2, 0, lw, s);
                    c.fill ();
                    break;
                case "wide-vertical":
                    c.rectangle (s / 4, 0, s / 2, s);
                    c.fill ();
                    break;
                case "diag-up":
                case "diag-down":
                case "diag-grid":
                    for (int k = -1; k <= 1; k++) {
                        if (id != "diag-down") {
                            c.move_to (k * s, s);
                            c.line_to (k * s + s, 0);
                        }
                        if (id != "diag-up") {
                            c.move_to (k * s, 0);
                            c.line_to (k * s + s, s);
                        }
                    }
                    c.stroke ();
                    break;
                case "grid":
                case "small-grid":
                case "large-grid":
                    double step = id == "small-grid" ? s / 2 : (id == "large-grid" ? s * 2 : s);
                    for (double v = 0; v < s * (id == "large-grid" ? 2 : 1) + 0.01; v += step) {
                        c.rectangle (v - lw / 4, 0, lw / 2, s * (id == "large-grid" ? 2 : 1));
                        c.rectangle (0, v - lw / 4, s * (id == "large-grid" ? 2 : 1), lw / 2);
                    }
                    c.fill ();
                    break;
                case "dots-10":
                case "dots-25":
                case "dots-50":
                case "dots-75":
                    double pct = id == "dots-10" ? 0.1 : (id == "dots-25" ? 0.25 : (id == "dots-50" ? 0.5 : 0.75));
                    double r = Math.sqrt (pct * s * s / 2 / Math.PI);
                    c.arc (s / 4, s / 4, r, 0, 2 * Math.PI);
                    c.new_sub_path ();
                    c.arc (3 * s / 4, 3 * s / 4, r, 0, 2 * Math.PI);
                    c.fill ();
                    break;
                case "checker-small":
                case "checker-large":
                    double q = id == "checker-small" ? s / 4 : s / 2;
                    for (int y = 0; y * q < s - 0.01; y++) for (int x = 0; x * q < s - 0.01; x++) if ((x + y) % 2 == 0) c.rectangle (x * q, y * q, q, q);
                    c.fill ();
                    break;
                case "brick":
                    c.rectangle (0, 0, s, lw / 2);
                    c.rectangle (0, s / 2, s, lw / 2);
                    c.rectangle (0, 0, lw / 2, s / 2);
                    c.rectangle (s / 2, s / 2, lw / 2, s / 2);
                    c.fill ();
                    break;
                case "brick-diag":
                    c.move_to (0, s);
                    c.line_to (s, 0);
                    c.move_to (s / 4, s / 4 * 3);
                    c.line_to (s / 2, s);
                    c.stroke ();
                    break;
                case "weave":
                    c.move_to (0, 0);
                    c.line_to (s / 2, s / 2);
                    c.move_to (s / 2, 0);
                    c.line_to (s, s / 2);
                    c.move_to (s / 2, s / 2);
                    c.line_to (0, s);
                    c.move_to (s, s / 2);
                    c.line_to (s / 2, s);
                    c.stroke ();
                    break;
                case "zigzag":
                    c.move_to (0, s * 0.7);
                    c.line_to (s / 2, s * 0.3);
                    c.line_to (s, s * 0.7);
                    c.stroke ();
                    break;
                case "wave":
                    c.move_to (0, s / 2);
                    c.curve_to (s / 4, 0, s / 4, 0, s / 2, s / 2);
                    c.curve_to (3 * s / 4, s, 3 * s / 4, s, s, s / 2);
                    c.stroke ();
                    break;
                case "plaid":
                    c.save ();
                    c.push_group ();
                    c.rectangle (0, 0, s, s / 3);
                    c.rectangle (0, 0, s / 3, s);
                    c.fill ();
                    c.pop_group_to_source ();
                    c.paint_with_alpha (0.6);
                    c.restore ();
                    c.rectangle (s / 2, 0, lw / 2, s);
                    c.rectangle (0, s / 2, s, lw / 2);
                    c.fill ();
                    break;
                case "shingle":
                    c.move_to (0, s);
                    c.line_to (s, 0);
                    c.move_to (0, 0);
                    c.line_to (s / 2, s / 2);
                    c.stroke ();
                    break;
                case "trellis":
                    c.set_line_width (lw * 2);
                    c.move_to (0, s);
                    c.line_to (s, 0);
                    c.move_to (0, 0);
                    c.line_to (s, s);
                    c.stroke ();
                    break;
                case "divot":
                    c.move_to (s * 0.3, s * 0.2);
                    c.line_to (s * 0.5, s * 0.3);
                    c.line_to (s * 0.3, s * 0.4);
                    c.move_to (s * 0.7, s * 0.6);
                    c.line_to (s * 0.9, s * 0.7);
                    c.line_to (s * 0.7, s * 0.8);
                    c.stroke ();
                    break;
                case "dash-h":
                    c.rectangle (0, s / 4, s / 2, lw);
                    c.rectangle (s / 2, 3 * s / 4, s / 2, lw);
                    c.fill ();
                    break;
                case "dash-v":
                    c.rectangle (s / 4, 0, lw, s / 2);
                    c.rectangle (3 * s / 4, s / 2, lw, s / 2);
                    c.fill ();
                    break;
                case "dotted-grid":
                    for (int k = 0; k < 4; k++) {
                        c.rectangle (k * s / 4, 0, lw, lw);
                        c.rectangle (0, k * s / 4, lw, lw);
                    }
                    c.fill ();
                    break;
                case "diamond-outline":
                    c.move_to (s / 2, 0);
                    c.line_to (s, s / 2);
                    c.line_to (s / 2, s);
                    c.line_to (0, s / 2);
                    c.close_path ();
                    c.stroke ();
                    break;
                case "diamond-solid":
                    c.move_to (s / 2, s * 0.1);
                    c.line_to (s * 0.9, s / 2);
                    c.line_to (s / 2, s * 0.9);
                    c.line_to (s * 0.1, s / 2);
                    c.close_path ();
                    c.fill ();
                    break;
                case "confetti":
                    double[] cx = { 0.1, 0.55, 0.3, 0.8, 0.65, 0.15 };
                    double[] cy = { 0.2, 0.1, 0.55, 0.45, 0.85, 0.8 };
                    for (int k = 0; k < cx.length; k++) c.rectangle (cx[k] * s, cy[k] * s, lw * 1.5, lw * 1.5);
                    c.fill ();
                    break;
                case "sphere":
                    c.arc (s / 2, s / 2, s * 0.42, 0, 2 * Math.PI);
                    c.stroke ();
                    c.arc (s * 0.4, s * 0.4, s * 0.1, 0, 2 * Math.PI);
                    c.fill ();
                    break;
                default:
                    break;
            }
        }

        public static void set_pattern_source (Renderer r, Cairo.Context cr, Fill f) {
            double s = 8 * double.max (0.1, f.tile_scale);
            double span = f.pattern == "large-grid" ? s * 2 : s;
            var rec = new Cairo.RecordingSurface (Cairo.Content.COLOR_ALPHA, { 0, 0, span, span });
            var c = new Cairo.Context (rec);
            if (f.bg_color != ColorRef.NONE) {
                r.set_color (c, f.bg_color);
                c.paint ();
            }
            r.set_color (c, f.color != ColorRef.NONE ? f.color : ColorRef.BLACK);
            draw_pattern_cell (c, f.pattern, s);
            var pat = new Cairo.Pattern.for_surface (rec);
            pat.set_extend (Cairo.Extend.REPEAT);
            cr.set_source (pat);
        }

        public static string[] texture_ids () {
            return { "paper", "parchment", "recycled", "canvas", "burlap", "denim", "wood", "oak", "marble", "green-marble", "granite", "sand", "cork", "stone", "water", "newsprint" };
        }

        public static string texture_label (string id) {
            switch (id) {
                case "paper": return _("Paper");
                case "parchment": return _("Parchment");
                case "recycled": return _("Recycled Paper");
                case "canvas": return _("Canvas");
                case "burlap": return _("Burlap");
                case "denim": return _("Denim");
                case "wood": return _("Walnut");
                case "oak": return _("Oak");
                case "marble": return _("White Marble");
                case "green-marble": return _("Green Marble");
                case "granite": return _("Granite");
                case "sand": return _("Sand");
                case "cork": return _("Cork");
                case "stone": return _("Stone");
                case "water": return _("Water Droplets");
                case "newsprint": return _("Newsprint");
                default: return id;
            }
        }

        private static uint32 hash2 (int x, int y, uint32 seed) {
            uint32 h = (uint32) x * 374761393u + (uint32) y * 668265263u + seed * 2246822519u;
            h = (h ^ (h >> 13)) * 1274126177u;
            return h ^ (h >> 16);
        }

        private static double lattice (int x, int y, uint32 seed, int period) {
            return (hash2 (((x % period) + period) % period, ((y % period) + period) % period, seed) & 0xffff) / 65535.0;
        }

        private static double smooth (double t) {
            return t * t * (3 - 2 * t);
        }

        public static double noise (double x, double y, uint32 seed, int period) {
            int xi = (int) Math.floor (x), yi = (int) Math.floor (y);
            double fx = smooth (x - xi), fy = smooth (y - yi);
            double a = lattice (xi, yi, seed, period), b = lattice (xi + 1, yi, seed, period);
            double c = lattice (xi, yi + 1, seed, period), d = lattice (xi + 1, yi + 1, seed, period);
            return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy;
        }

        public static double fbm (double x, double y, uint32 seed, int period, int octaves = 4) {
            double v = 0, amp = 0.5, total = 0;
            int p = period;
            for (int o = 0; o < octaves; o++) {
                v += amp * noise (x, y, seed + o, p);
                total += amp;
                x *= 2;
                y *= 2;
                p *= 2;
                amp *= 0.5;
            }
            return v / total;
        }

        public static Cairo.ImageSurface texture (string id) {
            if (textures == null) textures = new Gee.HashMap<string, Cairo.ImageSurface> ();
            if (textures.has_key (id)) return textures[id];
            int n = 256;
            var surf = new Cairo.ImageSurface (Cairo.Format.RGB24, n, n);
            unowned uint8[] d = surf.get_data ();
            int stride = surf.get_stride ();
            uint32 seed = (uint32) id.hash ();
            for (int y = 0; y < n; y++) {
                for (int x = 0; x < n; x++) {
                    double u = x / 32.0, v = y / 32.0;
                    double r = 1, g = 1, b = 1;
                    double f = fbm (u, v, seed, 8);
                    double fine = noise (x / 2.0, y / 2.0, seed + 11, 128);
                    switch (id) {
                        case "paper":
                            double t = 0.93 + 0.06 * f + 0.02 * fine;
                            r = t;
                            g = t;
                            b = t * 0.98;
                            break;
                        case "parchment":
                            double pt = 0.82 + 0.14 * f;
                            r = pt;
                            g = pt * 0.9;
                            b = pt * 0.68;
                            break;
                        case "recycled":
                            double rt = 0.8 + 0.1 * f + 0.1 * (fine > 0.92 ? -1 : 0);
                            r = rt;
                            g = rt * 0.98;
                            b = rt * 0.94;
                            break;
                        case "canvas":
                        case "burlap":
                            double weave = 0.5 + 0.25 * Math.sin (x * 0.9) + 0.25 * Math.sin (y * 0.9);
                            double ct = 0.72 + 0.16 * weave + 0.08 * f;
                            if (id == "burlap") {
                                r = ct * 0.78;
                                g = ct * 0.64;
                                b = ct * 0.42;
                            } else {
                                r = ct * 0.98;
                                g = ct * 0.95;
                                b = ct * 0.86;
                            }
                            break;
                        case "denim":
                            double twill = 0.5 + 0.5 * Math.sin ((x + y) * 0.8);
                            double dt = 0.35 + 0.2 * twill + 0.15 * f;
                            r = dt * 0.45;
                            g = dt * 0.6;
                            b = dt * 1.2;
                            break;
                        case "wood":
                        case "oak":
                            double ring = Math.sin ((v * 6 + f * 6) * Math.PI);
                            double wt = 0.5 + 0.25 * ring + 0.15 * fine;
                            if (id == "wood") {
                                r = 0.32 + 0.22 * wt;
                                g = 0.2 + 0.14 * wt;
                                b = 0.1 + 0.08 * wt;
                            } else {
                                r = 0.62 + 0.2 * wt;
                                g = 0.46 + 0.16 * wt;
                                b = 0.26 + 0.1 * wt;
                            }
                            break;
                        case "marble":
                        case "green-marble":
                            double vein = Math.fabs (Math.sin ((u + v + fbm (u, v, seed + 3, 8, 5) * 4) * 1.6));
                            double mt = Math.pow (vein, 0.35);
                            if (id == "marble") {
                                r = 0.62 + 0.36 * mt;
                                g = 0.62 + 0.36 * mt;
                                b = 0.64 + 0.35 * mt;
                            } else {
                                r = 0.08 + 0.3 * (1 - mt);
                                g = 0.3 + 0.35 * mt;
                                b = 0.2 + 0.25 * mt;
                            }
                            break;
                        case "granite":
                            double gs = fine;
                            double gt = gs > 0.8 ? 0.2 : (gs < 0.2 ? 0.85 : 0.55 + 0.1 * f);
                            r = gt;
                            g = gt * 0.96;
                            b = gt * 0.94;
                            break;
                        case "sand":
                            double st = 0.78 + 0.1 * f + 0.08 * (fine - 0.5);
                            r = st;
                            g = st * 0.88;
                            b = st * 0.64;
                            break;
                        case "cork":
                            double kt = 0.5 + 0.25 * f + (fine > 0.75 ? -0.2 : 0.05);
                            r = kt * 0.85;
                            g = kt * 0.6;
                            b = kt * 0.38;
                            break;
                        case "stone":
                            double sn = 0.5 + 0.3 * fbm (u * 2, v * 2, seed + 7, 16, 5);
                            r = sn;
                            g = sn * 0.97;
                            b = sn * 0.92;
                            break;
                        case "water":
                            double drop = noise (u * 1.5, v * 1.5, seed, 12);
                            double wv = drop > 0.72 ? 0.95 : 0.55 + 0.2 * f;
                            r = wv * 0.55;
                            g = wv * 0.78;
                            b = wv;
                            break;
                        case "newsprint":
                            double nt = 0.86 + 0.06 * f + 0.03 * fine;
                            r = nt;
                            g = nt * 0.98;
                            b = nt * 0.93;
                            break;
                    }
                    int i = y * stride + x * 4;
                    d[i + 2] = (uint8) (r.clamp (0, 1) * 255);
                    d[i + 1] = (uint8) (g.clamp (0, 1) * 255);
                    d[i] = (uint8) (b.clamp (0, 1) * 255);
                    d[i + 3] = 255;
                }
            }
            surf.mark_dirty ();
            textures[id] = surf;
            return surf;
        }

        public static bool set_raster_fill (Renderer r, Cairo.Context cr, Fill f, double w, double h) {
            Cairo.ImageSurface? img = null;
            if (f.kind == FillKind.TEXTURE) {
                img = texture (f.texture != "" ? f.texture : "paper");
            } else if (f.kind == FillKind.PICTURE) {
                var probe = new ImageFrame ();
                probe.media = f.media;
                probe.link = f.link;
                var inf = ImageStore.get_default ().info (r.pub, probe);
                if (inf != null && inf.surface != null) img = inf.surface;
            }
            if (img == null) return false;
            Cairo.Surface src = img;
            if (r.pub.output != null) {
                var mapped = r.pub.output.map_image (img);
                if (mapped != null) src = mapped;
            }
            var pat = new Cairo.Pattern.for_surface (src);
            var m = Cairo.Matrix.identity ();
            double iw = img.get_width (), ih = img.get_height ();
            if (f.tile || f.kind == FillKind.TEXTURE) {
                double sc = (f.kind == FillKind.TEXTURE ? 0.5 : 0.75) * double.max (0.05, f.tile_scale);
                m.scale (1 / sc, 1 / sc);
                pat.set_extend (Cairo.Extend.REPEAT);
            } else {
                m.scale (iw / double.max (1, w), ih / double.max (1, h));
                pat.set_extend (Cairo.Extend.PAD);
            }
            pat.set_matrix (m);
            pat.set_filter (Cairo.Filter.GOOD);
            cr.set_source (pat);
            return true;
        }

        public static Cairo.ImageSurface adjust (Publication pub, Cairo.ImageSurface src, ImageFrame f) {
            if (!f.adjusted ()) return src;
            if (adjusted == null) adjusted = new Gee.HashMap<string, Cairo.ImageSurface> ();
            Rgba tint = pub.resolve_screen (f.recolor_color);
            string key = "%p:%s:%s:%d:%s:%s".printf (src, XmlOut.num (f.brightness), XmlOut.num (f.contrast), f.recolor, tint.to_hex (), f.transparent_color);
            if (adjusted.has_key (key)) return adjusted[key];
            if (adjusted.size > 48) adjusted.clear ();
            int w = src.get_width (), h = src.get_height ();
            var out_s = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var c = new Cairo.Context (out_s);
            c.set_source_surface (src, 0, 0);
            c.set_operator (Cairo.Operator.SOURCE);
            c.paint ();
            out_s.flush ();
            unowned uint8[] d = out_s.get_data ();
            int stride = out_s.get_stride ();
            double br = f.brightness.clamp (-1, 1), ct = f.contrast.clamp (-1, 1);
            if (f.recolor == 3) {
                br = 0.55;
                ct = -0.6;
            }
            double factor = ct >= 0 ? 1 + ct * 3 : 1 + ct;
            Rgba tr = Rgba (0, 0, 0, 0);
            bool has_tr = f.transparent_color != "" && Rgba.parse_hex (f.transparent_color, out tr);
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int i = y * stride + x * 4;
                    double a = d[i + 3] / 255.0;
                    if (a <= 0) continue;
                    double r = d[i + 2] / 255.0 / a, g = d[i + 1] / 255.0 / a, b = d[i] / 255.0 / a;
                    if (has_tr && Math.fabs (r - tr.r) < 0.06 && Math.fabs (g - tr.g) < 0.06 && Math.fabs (b - tr.b) < 0.06) {
                        d[i] = d[i + 1] = d[i + 2] = d[i + 3] = 0;
                        continue;
                    }
                    r = (r - 0.5) * factor + 0.5 + br;
                    g = (g - 0.5) * factor + 0.5 + br;
                    b = (b - 0.5) * factor + 0.5 + br;
                    double l = (0.299 * r + 0.587 * g + 0.114 * b).clamp (0, 1);
                    switch (f.recolor) {
                        case 1:
                            r = g = b = l;
                            break;
                        case 2:
                            r = l * 1.07 + 0.08;
                            g = l * 0.92 + 0.04;
                            b = l * 0.72;
                            break;
                        case 4:
                            r = g = b = l >= 0.5 ? 1 : 0;
                            break;
                        case 5:
                            r = tint.r + (1 - tint.r) * l;
                            g = tint.g + (1 - tint.g) * l;
                            b = tint.b + (1 - tint.b) * l;
                            break;
                        default:
                            break;
                    }
                    d[i + 2] = (uint8) (r.clamp (0, 1) * a * 255);
                    d[i + 1] = (uint8) (g.clamp (0, 1) * a * 255);
                    d[i] = (uint8) (b.clamp (0, 1) * a * 255);
                }
            }
            out_s.mark_dirty ();
            adjusted[key] = out_s;
            return out_s;
        }

        public static string[] recolor_labels () {
            return { _("No Recolor"), _("Grayscale"), _("Sepia"), _("Washout"), _("Black and White"), _("Tint with Colour") };
        }

        private static Cairo.ImageSurface? alpha_mask (double w, double h, double pad, double scale, out int pw, out int ph) {
            pw = (int) Math.ceil ((w + pad * 2) * scale);
            ph = (int) Math.ceil ((h + pad * 2) * scale);
            if (pw <= 0 || ph <= 0 || pw > 6000 || ph > 6000) return null;
            return new Cairo.ImageSurface (Cairo.Format.A8, pw, ph);
        }

        private static double device_scale (Cairo.Context cr, bool print) {
            double sx = 1, sy = 1;
            cr.user_to_device_distance (ref sx, ref sy);
            double scale = double.min (4, double.max (0.5, Math.sqrt (Math.fabs (sx * sy))));
            if (print) scale = double.max (scale, 2);
            return scale;
        }

        public delegate void MaskPainter (Cairo.Context c);

        public static void paint_blurred (Renderer r, Cairo.Context cr, Item it, double pad, double blur, string color, double opacity, double dx, double dy, MaskPainter painter) {
            double scale = device_scale (cr, r.opts.print);
            int pw, ph;
            var surf = alpha_mask (it.w, it.h, pad, scale, out pw, out ph);
            if (surf == null) return;
            var c = new Cairo.Context (surf);
            c.scale (scale, scale);
            c.translate (pad, pad);
            c.set_source_rgba (0, 0, 0, 1);
            painter (c);
            surf.flush ();
            Renderer.box_blur (surf, (int) Math.round (blur * scale / 2));
            cr.save ();
            cr.translate (dx - pad, dy - pad);
            cr.scale (1 / scale, 1 / scale);
            r.set_color (cr, color, opacity);
            cr.mask_surface (surf, 0, 0);
            cr.restore ();
        }

        public static void draw_glow (Renderer r, Cairo.Context cr, Item it) {
            var e = it.effects;
            double size = double.max (1, e.glow_size);
            paint_blurred (r, cr, it, size * 2 + 4, size, e.glow_color, e.glow_opacity, 0, 0, (c) => {
                r.shape_path (c, it);
                c.fill_preserve ();
                c.set_line_width (size * 1.4);
                c.stroke ();
            });
        }

        public delegate void ContentPainter (Cairo.Context c);

        public static void draw_reflection (Renderer r, Cairo.Context cr, Item it, ContentPainter painter) {
            var e = it.effects;
            double h = it.h;
            cr.save ();
            cr.push_group ();
            cr.translate (0, 2 * h + e.reflection_distance);
            cr.scale (1, -1);
            painter (cr);
            var content = cr.pop_group ();
            var grad = new Cairo.Pattern.linear (0, h + e.reflection_distance, 0, h + e.reflection_distance + h * e.reflection_size.clamp (0.05, 1));
            grad.add_color_stop_rgba (0, 0, 0, 0, e.reflection_opacity.clamp (0, 1));
            grad.add_color_stop_rgba (1, 0, 0, 0, 0);
            cr.set_source (content);
            cr.mask (grad);
            cr.restore ();
        }

        public static void draw_soft_content (Renderer r, Cairo.Context cr, Item it, ContentPainter painter) {
            double rad = it.effects.soft_edges;
            double scale = device_scale (cr, r.opts.print);
            int pw, ph;
            double pad = 2;
            var mask = alpha_mask (it.w, it.h, pad, scale, out pw, out ph);
            if (mask == null) {
                painter (cr);
                return;
            }
            var c = new Cairo.Context (mask);
            c.scale (scale, scale);
            c.translate (pad, pad);
            c.set_source_rgba (0, 0, 0, 1);
            r.shape_path (c, it);
            c.fill_preserve ();
            c.set_operator (Cairo.Operator.DEST_OUT);
            c.set_line_width (rad * 2);
            c.stroke ();
            mask.flush ();
            Renderer.box_blur (mask, (int) Math.round (rad * scale / 2));
            cr.push_group ();
            painter (cr);
            var content = cr.pop_group ();
            cr.save ();
            cr.set_source (content);
            var mp = new Cairo.Pattern.for_surface (mask);
            var m = Cairo.Matrix.identity ();
            m.scale (scale, scale);
            m.translate (pad, pad);
            mp.set_matrix (m);
            cr.mask (mp);
            cr.restore ();
        }

        public static void draw_bevel (Renderer r, Cairo.Context cr, Item it) {
            double d = double.max (1, it.effects.bevel_depth);
            double pad = d + 2;
            paint_blurred (r, cr, it, pad, d, "#ffffff", 0.55, 0, 0, (c) => {
                r.shape_path (c, it);
                c.fill ();
                c.set_operator (Cairo.Operator.DEST_OUT);
                c.translate (d * 0.7, d * 0.7);
                r.shape_path (c, it);
                c.fill ();
            });
            paint_blurred (r, cr, it, pad, d, "#000000", 0.35, 0, 0, (c) => {
                r.shape_path (c, it);
                c.fill ();
                c.set_operator (Cairo.Operator.DEST_OUT);
                c.translate (-d * 0.7, -d * 0.7);
                r.shape_path (c, it);
                c.fill ();
            });
        }

        public static void text_effects_under (Renderer r, Cairo.Context cr, LaidLine l, double x, CharFormat f, double x0, double x1) {
            double top = l.baseline - l.ascent - 2, bottom = l.baseline + l.descent + 2;
            if (f.reflection == 1) {
                cr.save ();
                double mirror = l.baseline + l.descent * 0.6;
                cr.rectangle (x0, mirror, x1 - x0, (l.ascent + l.descent) * 0.9);
                cr.clip ();
                cr.push_group ();
                cr.translate (0, 2 * mirror);
                cr.scale (1, -1);
                cr.move_to (x, l.baseline);
                r.set_color (cr, f.color ?? ColorRef.BLACK);
                Pango.cairo_show_layout_line (cr, l.line ());
                var content = cr.pop_group ();
                var grad = new Cairo.Pattern.linear (0, mirror, 0, mirror + (l.ascent + l.descent) * 0.8);
                grad.add_color_stop_rgba (0, 0, 0, 0, 0.45);
                grad.add_color_stop_rgba (1, 0, 0, 0, 0);
                cr.set_source (content);
                cr.mask (grad);
                cr.restore ();
            }
            if (f.text_shadow == 1 || (f.glow_color != null && f.glow_color != "" && f.glow_size > 0)) {
                double gs = f.glow_size.is_nan () ? 0 : f.glow_size;
                double pad = double.max (8, gs * 2 + 4);
                double scale = device_scale (cr, r.opts.print);
                int pw = (int) Math.ceil ((x1 - x0 + pad * 2) * scale), ph = (int) Math.ceil ((bottom - top + pad * 2) * scale);
                if (pw > 0 && ph > 0 && pw < 8000 && ph < 4000) {
                    if (f.glow_color != null && f.glow_color != "" && gs > 0) {
                        var surf = new Cairo.ImageSurface (Cairo.Format.A8, pw, ph);
                        var c = new Cairo.Context (surf);
                        c.scale (scale, scale);
                        c.translate (pad - x0, pad - top);
                        c.rectangle (x0 - 1, top - pad, x1 - x0 + 2, bottom - top + pad * 2);
                        c.clip ();
                        c.move_to (x, l.baseline);
                        Pango.cairo_layout_line_path (c, l.line ());
                        c.set_line_width (gs * 1.4);
                        c.set_line_join (Cairo.LineJoin.ROUND);
                        c.fill_preserve ();
                        c.stroke ();
                        surf.flush ();
                        Renderer.box_blur (surf, (int) Math.round (gs * scale / 2));
                        cr.save ();
                        cr.translate (x0 - pad, top - pad);
                        cr.scale (1 / scale, 1 / scale);
                        r.set_color (cr, f.glow_color, 0.75);
                        cr.mask_surface (surf, 0, 0);
                        cr.restore ();
                    }
                    if (f.text_shadow == 1) {
                        double off = double.max (1, f.size * 0.06);
                        var surf = new Cairo.ImageSurface (Cairo.Format.A8, pw, ph);
                        var c = new Cairo.Context (surf);
                        c.scale (scale, scale);
                        c.translate (pad - x0, pad - top);
                        c.rectangle (x0, top - pad, x1 - x0, bottom - top + pad * 2);
                        c.clip ();
                        c.move_to (x, l.baseline);
                        Pango.cairo_layout_line_path (c, l.line ());
                        c.fill ();
                        surf.flush ();
                        Renderer.box_blur (surf, (int) Math.round (off * scale / 2));
                        cr.save ();
                        cr.translate (x0 - pad + off, top - pad + off);
                        cr.scale (1 / scale, 1 / scale);
                        r.set_color (cr, ColorRef.BLACK, 0.4);
                        cr.mask_surface (surf, 0, 0);
                        cr.restore ();
                    }
                }
            }
            if (f.emboss > 0) {
                double off = double.max (0.4, f.size * 0.03);
                cr.save ();
                cr.rectangle (x0, top, x1 - x0, bottom - top);
                cr.clip ();
                cr.move_to (x + (f.emboss == 1 ? -off : off), l.baseline + (f.emboss == 1 ? -off : off));
                Pango.cairo_layout_line_path (cr, l.line ());
                r.set_color (cr, "#ffffff", 0.9);
                cr.fill ();
                cr.move_to (x + (f.emboss == 1 ? off : -off), l.baseline + (f.emboss == 1 ? off : -off));
                Pango.cairo_layout_line_path (cr, l.line ());
                r.set_color (cr, "#000000", 0.45);
                cr.fill ();
                cr.restore ();
            }
        }

        public static void text_effects_over (Renderer r, Cairo.Context cr, LaidLine l, double x, CharFormat f, double x0, double x1) {
            if (f.outline_color == null || f.outline_color == "" || f.outline_width.is_nan () || f.outline_width <= 0) return;
            cr.save ();
            cr.rectangle (x0, l.baseline - l.ascent - 4, x1 - x0, l.ascent + l.descent + 8);
            cr.clip ();
            cr.move_to (x, l.baseline);
            Pango.cairo_layout_line_path (cr, l.line ());
            r.set_color (cr, f.outline_color);
            cr.set_line_width (f.outline_width);
            cr.set_line_join (Cairo.LineJoin.ROUND);
            cr.stroke ();
            cr.restore ();
        }

        public static Pango.Layout wordart_layout (WordArtItem wa) {
            var layout = new Pango.Layout (TextEngine.context ());
            var fd = new Pango.FontDescription ();
            fd.set_family (wa.font);
            fd.set_absolute_size (100 * Pango.SCALE);
            fd.set_weight (wa.bold ? Pango.Weight.BOLD : Pango.Weight.NORMAL);
            fd.set_style (wa.italic ? Pango.Style.ITALIC : Pango.Style.NORMAL);
            layout.set_font_description (fd);
            layout.set_alignment (Pango.Alignment.CENTER);
            layout.set_text (wa.text != "" ? wa.text : " ", -1);
            return layout;
        }

        public static Point warp (WarpKind k, double amount, double u, double v, double w, double h) {
            double a = amount.clamp (0, 1);
            switch (k) {
                case WarpKind.ARCH_UP:
                case WarpKind.ARCH_DOWN:
                    double span = Math.PI * (0.35 + 0.65 * a);
                    double ang = -Math.PI / 2 + (u - 0.5) * span;
                    if (k == WarpKind.ARCH_DOWN) ang = Math.PI / 2 - (u - 0.5) * span;
                    double rad_out = w / 2 / Math.sin (span / 2) * 0.98;
                    double thick = h * 0.5;
                    double rr = k == WarpKind.ARCH_UP ? rad_out - v * thick : rad_out - thick + v * thick;
                    double cy = k == WarpKind.ARCH_UP ? rad_out : h - rad_out;
                    return Point (w / 2 + rr * Math.cos (ang), cy + rr * Math.sin (ang));
                case WarpKind.CIRCLE:
                    double ca = -Math.PI / 2 + (u - 0.5) * 2 * Math.PI * 0.95;
                    double cr0 = double.min (w, h) / 2;
                    double crr = cr0 - v * cr0 * 0.35;
                    return Point (w / 2 + crr * Math.cos (ca), h / 2 + crr * Math.sin (ca));
                case WarpKind.WAVE:
                    double amp = h * 0.18 * (0.3 + a);
                    return Point (u * w, amp + v * (h - 2 * amp) + amp * Math.sin (u * 2 * Math.PI));
                case WarpKind.INFLATE:
                    double ipad = h * 0.3 * a * (1 - Math.sin (u * Math.PI));
                    return Point (u * w, ipad + v * (h - 2 * ipad));
                case WarpKind.DEFLATE:
                    double pinch = Math.sin (u * Math.PI) * h * 0.3 * a;
                    double top = pinch, bottom = h - pinch;
                    return Point (u * w, top + v * (bottom - top));
                case WarpKind.SLANT_UP:
                    double sl = h * 0.35 * a;
                    return Point (u * w, (1 - u) * sl + v * (h - sl));
                case WarpKind.SLANT_DOWN:
                    double sd = h * 0.35 * a;
                    return Point (u * w, u * sd + v * (h - sd));
                case WarpKind.TRIANGLE_UP:
                    double tri = (1 - Math.fabs (u - 0.5) * 2) * h * 0.4 * a;
                    return Point (u * w, h * 0.4 * a - tri + v * (h - h * 0.4 * a));
                case WarpKind.FADE_RIGHT:
                    double shrink = u * 0.45 * a;
                    return Point (u * w, h * shrink / 2 + v * h * (1 - shrink));
                case WarpKind.CASCADE:
                    double rise = u * h * 0.4 * a;
                    return Point (u * w, h * 0.4 * a - rise + v * (h - h * 0.4 * a));
                default:
                    return Point (u * w, v * h);
            }
        }

        public static void wordart_path (Cairo.Context cr, WordArtItem wa) {
            var layout = wordart_layout (wa);
            Pango.Rectangle ink, logical;
            layout.get_extents (out ink, out logical);
            double ix = ink.x / (double) Pango.SCALE, iy = ink.y / (double) Pango.SCALE;
            double iw = double.max (1, ink.width / (double) Pango.SCALE), ih = double.max (1, ink.height / (double) Pango.SCALE);
            var tmp = new Cairo.ImageSurface (Cairo.Format.A8, 1, 1);
            var tc = new Cairo.Context (tmp);
            tc.set_tolerance (0.3);
            Pango.cairo_layout_path (tc, layout);
            var path = tc.copy_path_flat ();
            double w = double.max (1, wa.w), h = double.max (1, wa.h);
            int* ip = (int*) path.data;
            double* dp = (double*) path.data;
            var kinds = new Gee.ArrayList<int> ();
            var pts = new Gee.ArrayList<Point?> ();
            double x0 = double.MAX, y0 = double.MAX, x1 = -double.MAX, y1 = -double.MAX;
            int i = 0;
            while (i < path.num_data) {
                int kind = ip[i * 4];
                int len = int.max (1, ip[i * 4 + 1]);
                if (kind == Cairo.PathDataType.CLOSE_PATH) {
                    kinds.add (kind);
                    pts.add (Point (0, 0));
                } else if (len > 1) {
                    double px = dp[(i + 1) * 2], py = dp[(i + 1) * 2 + 1];
                    var q = warp (wa.warp, wa.warp_amount, (px - ix) / iw, (py - iy) / ih, w, h);
                    kinds.add (kind);
                    pts.add (q);
                    x0 = double.min (x0, q.x);
                    y0 = double.min (y0, q.y);
                    x1 = double.max (x1, q.x);
                    y1 = double.max (y1, q.y);
                }
                i += len;
            }
            double sx = x1 > x0 ? w / (x1 - x0) : 1, sy = y1 > y0 ? h / (y1 - y0) : 1;
            for (int k = 0; k < kinds.size; k++) {
                if (kinds[k] == Cairo.PathDataType.CLOSE_PATH) {
                    cr.close_path ();
                    continue;
                }
                double qx = (pts[k].x - x0) * sx, qy = (pts[k].y - y0) * sy;
                if (kinds[k] == Cairo.PathDataType.MOVE_TO) cr.move_to (qx, qy);
                else cr.line_to (qx, qy);
            }
        }

        public static string[] border_ids () {
            return { "stars", "hearts", "circles", "diamonds", "triangles", "squares", "dots", "zigzag", "waves", "scallops", "rope", "checker", "flowers", "leaves", "suns", "snowflakes", "crosses", "arrows", "sawtooth", "candy", "film", "double-line", "thick-thin", "balloons", "trees", "apples", "confetti", "ribbons" };
        }

        public static string border_label (string id) {
            switch (id) {
                case "stars": return _("Stars");
                case "hearts": return _("Hearts");
                case "circles": return _("Circles");
                case "diamonds": return _("Diamonds");
                case "triangles": return _("Triangles");
                case "squares": return _("Squares");
                case "dots": return _("Dots");
                case "zigzag": return _("Zig Zag");
                case "waves": return _("Waves");
                case "scallops": return _("Scallops");
                case "rope": return _("Rope");
                case "checker": return _("Checkerboard");
                case "flowers": return _("Flowers");
                case "leaves": return _("Leaves");
                case "suns": return _("Suns");
                case "snowflakes": return _("Snowflakes");
                case "crosses": return _("Crosses");
                case "arrows": return _("Arrows");
                case "sawtooth": return _("Sawtooth");
                case "candy": return _("Candy Stripes");
                case "film": return _("Film Strip");
                case "double-line": return _("Double Line");
                case "thick-thin": return _("Thick and Thin");
                case "balloons": return _("Balloons");
                case "trees": return _("Trees");
                case "apples": return _("Apples");
                case "confetti": return _("Confetti");
                case "ribbons": return _("Ribbons");
                default: return id;
            }
        }

        private static string default_color (string id) {
            switch (id) {
                case "hearts": return "#d9263a";
                case "apples": return "#c8202b";
                case "trees": return "#2e7d32";
                case "leaves": return "#4f8a2b";
                case "suns": return "#f2a900";
                case "flowers": return "#d14f9b";
                case "snowflakes": return "#3b8ed8";
                case "balloons": return "#e6452f";
                case "candy": return "#d9263a";
                default: return ColorRef.BLACK;
            }
        }

        private static void unit_star (Cairo.Context c, double cx, double cy, double r, int n, double inner) {
            for (int i = 0; i < n * 2; i++) {
                double t = -Math.PI / 2 + Math.PI * i / n;
                double f = i % 2 == 0 ? r : r * inner;
                if (i == 0) c.move_to (cx + f * Math.cos (t), cy + f * Math.sin (t));
                else c.line_to (cx + f * Math.cos (t), cy + f * Math.sin (t));
            }
            c.close_path ();
        }

        private static void motif (Renderer r, Cairo.Context c, string id, double w, double h, string color) {
            double s = double.min (w, h);
            double cx = w / 2, cy = h / 2;
            r.set_color (c, color);
            switch (id) {
                case "stars":
                    unit_star (c, cx, cy, s * 0.45, 5, 0.42);
                    c.fill ();
                    break;
                case "hearts":
                    for (int i = 0; i < 32; i++) {
                        double t = 2 * Math.PI * i / 32;
                        double x = 16 * Math.pow (Math.sin (t), 3), y = 13 * Math.cos (t) - 5 * Math.cos (2 * t) - 2 * Math.cos (3 * t) - Math.cos (4 * t);
                        double px = cx + x / 34 * s * 0.9, py = cy - y / 34 * s * 0.9;
                        if (i == 0) c.move_to (px, py);
                        else c.line_to (px, py);
                    }
                    c.close_path ();
                    c.fill ();
                    break;
                case "circles":
                    c.set_line_width (s * 0.1);
                    c.arc (cx, cy, s * 0.35, 0, 2 * Math.PI);
                    c.stroke ();
                    break;
                case "dots":
                    c.arc (cx, cy, s * 0.2, 0, 2 * Math.PI);
                    c.fill ();
                    break;
                case "diamonds":
                    c.move_to (cx, cy - s * 0.45);
                    c.line_to (cx + s * 0.3, cy);
                    c.line_to (cx, cy + s * 0.45);
                    c.line_to (cx - s * 0.3, cy);
                    c.close_path ();
                    c.fill ();
                    break;
                case "triangles":
                    c.move_to (0, h);
                    c.line_to (w / 2, 0);
                    c.line_to (w, h);
                    c.close_path ();
                    c.fill ();
                    break;
                case "squares":
                    c.rectangle (cx - s * 0.32, cy - s * 0.32, s * 0.64, s * 0.64);
                    c.fill ();
                    break;
                case "zigzag":
                    c.set_line_width (s * 0.14);
                    c.move_to (0, h * 0.75);
                    c.line_to (w / 2, h * 0.25);
                    c.line_to (w, h * 0.75);
                    c.stroke ();
                    break;
                case "waves":
                    c.set_line_width (s * 0.14);
                    c.move_to (0, cy);
                    c.curve_to (w * 0.25, h * 0.1, w * 0.25, h * 0.1, w * 0.5, cy);
                    c.curve_to (w * 0.75, h * 0.9, w * 0.75, h * 0.9, w, cy);
                    c.stroke ();
                    break;
                case "scallops":
                    c.move_to (0, h);
                    c.arc_negative (w / 2, h, w / 2, Math.PI, 0);
                    c.close_path ();
                    c.fill ();
                    break;
                case "rope":
                    c.set_line_width (s * 0.12);
                    c.move_to (0, h * 0.2);
                    c.curve_to (w * 0.5, h * 0.2, w * 0.5, h * 0.8, w, h * 0.8);
                    c.move_to (0, h * 0.8);
                    c.curve_to (w * 0.3, h * 0.8, w * 0.3, h * 0.55, w * 0.42, h * 0.55);
                    c.stroke ();
                    break;
                case "checker":
                    c.rectangle (0, 0, w / 2, h / 2);
                    c.rectangle (w / 2, h / 2, w / 2, h / 2);
                    c.fill ();
                    break;
                case "flowers":
                    for (int i = 0; i < 5; i++) {
                        double t = 2 * Math.PI * i / 5;
                        c.arc (cx + s * 0.2 * Math.cos (t), cy + s * 0.2 * Math.sin (t), s * 0.16, 0, 2 * Math.PI);
                        c.fill ();
                    }
                    r.set_color (c, "#f2c200");
                    c.arc (cx, cy, s * 0.12, 0, 2 * Math.PI);
                    c.fill ();
                    break;
                case "leaves":
                    c.move_to (w * 0.1, cy);
                    c.curve_to (w * 0.35, h * 0.05, w * 0.7, h * 0.05, w * 0.9, cy);
                    c.curve_to (w * 0.7, h * 0.95, w * 0.35, h * 0.95, w * 0.1, cy);
                    c.fill ();
                    break;
                case "suns":
                    unit_star (c, cx, cy, s * 0.46, 12, 0.7);
                    c.fill ();
                    break;
                case "snowflakes":
                    c.set_line_width (s * 0.07);
                    for (int i = 0; i < 3; i++) {
                        double t = Math.PI * i / 3;
                        c.move_to (cx - s * 0.42 * Math.cos (t), cy - s * 0.42 * Math.sin (t));
                        c.line_to (cx + s * 0.42 * Math.cos (t), cy + s * 0.42 * Math.sin (t));
                    }
                    c.stroke ();
                    break;
                case "crosses":
                    c.rectangle (cx - s * 0.08, cy - s * 0.35, s * 0.16, s * 0.7);
                    c.rectangle (cx - s * 0.35, cy - s * 0.08, s * 0.7, s * 0.16);
                    c.fill ();
                    break;
                case "arrows":
                    c.move_to (w * 0.1, h * 0.35);
                    c.line_to (w * 0.55, h * 0.35);
                    c.line_to (w * 0.55, h * 0.15);
                    c.line_to (w * 0.9, cy);
                    c.line_to (w * 0.55, h * 0.85);
                    c.line_to (w * 0.55, h * 0.65);
                    c.line_to (w * 0.1, h * 0.65);
                    c.close_path ();
                    c.fill ();
                    break;
                case "sawtooth":
                    c.move_to (0, h);
                    c.line_to (w, 0);
                    c.line_to (w, h);
                    c.close_path ();
                    c.fill ();
                    break;
                case "candy":
                    c.move_to (0, h);
                    c.line_to (w * 0.5, 0);
                    c.line_to (w, 0);
                    c.line_to (w * 0.5, h);
                    c.close_path ();
                    c.fill ();
                    break;
                case "film":
                    c.rectangle (0, 0, w, h);
                    c.fill ();
                    r.set_color (c, ColorRef.PAPER);
                    c.rectangle (w * 0.3, h * 0.15, w * 0.4, h * 0.22);
                    c.rectangle (w * 0.3, h * 0.63, w * 0.4, h * 0.22);
                    c.fill ();
                    break;
                case "double-line":
                    c.rectangle (0, h * 0.2, w, h * 0.14);
                    c.rectangle (0, h * 0.66, w, h * 0.14);
                    c.fill ();
                    break;
                case "thick-thin":
                    c.rectangle (0, h * 0.1, w, h * 0.4);
                    c.rectangle (0, h * 0.72, w, h * 0.1);
                    c.fill ();
                    break;
                case "balloons":
                    c.save ();
                    c.translate (cx, cy - s * 0.1);
                    c.scale (s * 0.28, s * 0.34);
                    c.arc (0, 0, 1, 0, 2 * Math.PI);
                    c.restore ();
                    c.fill ();
                    c.set_line_width (s * 0.04);
                    c.move_to (cx, cy + s * 0.24);
                    c.line_to (cx, h);
                    c.stroke ();
                    break;
                case "trees":
                    c.move_to (cx, h * 0.05);
                    c.line_to (cx + s * 0.35, h * 0.72);
                    c.line_to (cx - s * 0.35, h * 0.72);
                    c.close_path ();
                    c.fill ();
                    r.set_color (c, "#6d4c2f");
                    c.rectangle (cx - s * 0.06, h * 0.72, s * 0.12, h * 0.22);
                    c.fill ();
                    break;
                case "apples":
                    c.arc (cx - s * 0.12, cy + s * 0.05, s * 0.26, 0, 2 * Math.PI);
                    c.arc (cx + s * 0.12, cy + s * 0.05, s * 0.26, 0, 2 * Math.PI);
                    c.fill ();
                    r.set_color (c, "#3f7f2a");
                    c.move_to (cx, cy - s * 0.2);
                    c.curve_to (cx + s * 0.1, cy - s * 0.4, cx + s * 0.25, cy - s * 0.4, cx + s * 0.3, cy - s * 0.35);
                    c.curve_to (cx + s * 0.2, cy - s * 0.25, cx + s * 0.1, cy - s * 0.2, cx, cy - s * 0.2);
                    c.fill ();
                    break;
                case "confetti":
                    string[] cols = { "#e53935", "#1e88e5", "#43a047", "#fdd835" };
                    for (int i = 0; i < 4; i++) {
                        r.set_color (c, cols[i]);
                        c.rectangle (w * (0.1 + 0.22 * i), h * (i % 2 == 0 ? 0.2 : 0.6), s * 0.16, s * 0.16);
                        c.fill ();
                    }
                    break;
                case "ribbons":
                    c.move_to (0, h * 0.3);
                    c.line_to (w * 0.5, h * 0.7);
                    c.line_to (w, h * 0.3);
                    c.line_to (w, h * 0.5);
                    c.line_to (w * 0.5, h * 0.9);
                    c.line_to (0, h * 0.5);
                    c.close_path ();
                    c.fill ();
                    break;
                default:
                    c.rectangle (0, h * 0.35, w, h * 0.3);
                    c.fill ();
                    break;
            }
        }

        public static void draw_border_art (Renderer r, Cairo.Context cr, Item it) {
            var ba = it.border_art;
            double s = ba.size.clamp (2, double.min (it.w, it.h) / 2);
            if (s <= 0) return;
            string color = ba.color != "" ? ba.color : default_color (ba.design);
            double w = it.w, h = it.h;
            cr.save ();
            cr.set_dash (null, 0);
            int nx = int.max (1, (int) Math.round ((w - 2 * s) / s));
            int ny = int.max (1, (int) Math.round ((h - 2 * s) / s));
            double cw = (w - 2 * s) / nx, ch = (h - 2 * s) / ny;
            double[] cxs = { 0, w - s, w - s, 0 };
            double[] cys = { 0, 0, h - s, h - s };
            for (int i = 0; i < 4; i++) {
                cr.save ();
                cr.translate (cxs[i], cys[i]);
                motif (r, cr, ba.design, s, s, color);
                cr.restore ();
            }
            for (int i = 0; i < nx && cw > 0.5; i++) {
                cr.save ();
                cr.translate (s + i * cw, 0);
                motif (r, cr, ba.design, cw, s, color);
                cr.restore ();
                cr.save ();
                cr.translate (s + (i + 1) * cw, h);
                cr.rotate (Math.PI);
                motif (r, cr, ba.design, cw, s, color);
                cr.restore ();
            }
            for (int i = 0; i < ny && ch > 0.5; i++) {
                cr.save ();
                cr.translate (w, s + i * ch);
                cr.rotate (Math.PI / 2);
                motif (r, cr, ba.design, ch, s, color);
                cr.restore ();
                cr.save ();
                cr.translate (0, s + (i + 1) * ch);
                cr.rotate (-Math.PI / 2);
                motif (r, cr, ba.design, ch, s, color);
                cr.restore ();
            }
            cr.restore ();
        }

        public static void draw_border_preview (Cairo.Context cr, Publication pub, string design, double w, double h, double size) {
            var r = new Renderer (pub);
            var probe = new ShapeItem (ShapeKind.RECT);
            probe.w = w;
            probe.h = h;
            probe.border_art.design = design;
            probe.border_art.size = size;
            draw_border_art (r, cr, probe);
        }
    }
}
