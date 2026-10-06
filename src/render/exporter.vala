namespace Singularity.Apps.Publish {

    public enum ImposeMode {
        NONE,
        NUP,
        BOOKLET,
        TILE,
        SIGNATURES
    }

    public enum ColorMode {
        RGB,
        CMYK,
        PDFX1A,
        PDFX3,
        PDFX4;

        public string label () {
            switch (this) {
                case CMYK: return _("CMYK");
                case PDFX1A: return "PDF/X-1a:2003";
                case PDFX3: return "PDF/X-3:2003";
                case PDFX4: return "PDF/X-4";
                default: return _("RGB");
            }
        }
    }

    public class ExportOptions {
        public string ranges = "";
        public bool spreads = false;
        public bool bleed = true;
        public bool crop_marks = false;
        public bool bleed_marks = false;
        public bool reg_marks = false;
        public bool page_info = false;
        public bool color_bars = false;
        public double marks_offset = 6;
        public ImposeMode impose = ImposeMode.NONE;
        public int signature = 16;
        public bool tagged = true;
        public double creep = 0;
        public double sheet_w = 297 * Units.PT_PER_MM;
        public double sheet_h = 210 * Units.PT_PER_MM;
        public int rows = 2;
        public int cols = 2;
        public double gap = 0;
        public bool step_repeat = false;
        public double dpi = 150;
        public int jpeg_quality = 90;
        public bool transparent = false;
        public ColorMode color_mode = ColorMode.RGB;
        public bool separations = false;
        public Gee.ArrayList<string> plates = new Gee.ArrayList<string> ();
        public double tile_scale = 1;
        public double tile_overlap = 18;
        public bool image_cmyk = false;

        public bool any_marks () {
            return crop_marks || bleed_marks || reg_marks || page_info || color_bars;
        }
    }

    public class SheetSlot {
        public int page;
        public double x;
        public double y;
        public double w;
        public double h;
        public double scale;
        public bool rotate;
        public int row = 0;
        public int col = 0;
        public int rows = 1;
        public int cols = 1;
        public bool abut = false;

        public SheetSlot (int page, double x, double y, double w, double h, double scale) {
            this.page = page;
            this.x = x;
            this.y = y;
            this.w = w;
            this.h = h;
            this.scale = scale;
        }
    }

    public class Sheet {
        public double w;
        public double h;
        public Gee.ArrayList<SheetSlot> slots = new Gee.ArrayList<SheetSlot> ();
        public string label = "";
        public Rect tile = Rect (0, 0, 0, 0);
    }

    public class Exporter {
        public Publication pub;
        public ExportOptions opts;
        public LayoutCache cache;
        public Renderer renderer;

        public Exporter (Publication pub, ExportOptions? opts = null) {
            this.pub = pub;
            this.opts = opts ?? new ExportOptions ();
            cache = new LayoutCache (pub);
            renderer = new Renderer (pub, cache);
            renderer.opts.print = true;
            renderer.opts.overset_marks = false;
            renderer.opts.placeholders = false;
        }

        public static Gee.ArrayList<int> parse_ranges (string spec, int count) {
            var list = new Gee.ArrayList<int> ();
            string s = spec.strip ();
            if (s == "") {
                for (int i = 0; i < count; i++) list.add (i);
                return list;
            }
            foreach (string part in s.split (",")) {
                string p = part.strip ();
                if (p == "") continue;
                int dash = p.index_of ("-");
                if (dash > 0) {
                    int a = int.parse (p.substring (0, dash).strip ());
                    string bs = p.substring (dash + 1).strip ();
                    int b = bs == "" ? count : int.parse (bs);
                    if (a < 1) a = 1;
                    if (b > count) b = count;
                    for (int i = a; i <= b; i++) if (!list.contains (i - 1)) list.add (i - 1);
                } else {
                    int v = int.parse (p);
                    if (v >= 1 && v <= count && !list.contains (v - 1)) list.add (v - 1);
                }
            }
            return list;
        }

        public double marks_margin () {
            if (!opts.any_marks ()) return 0;
            return opts.marks_offset + 18 + (opts.page_info ? 10 : 0);
        }

        public Rect content_rect (int page_index) {
            if (opts.bleed) return pub.bleed_rect (page_index);
            return pub.page_rect (page_index);
        }

        public Gee.ArrayList<Sheet> sheets () {
            var list = new Gee.ArrayList<Sheet> ();
            var pages = parse_ranges (opts.ranges, pub.pages.size);
            double pw = pub.settings.width, ph = pub.settings.height;
            switch (opts.impose) {
                case ImposeMode.NUP:
                    int per = int.max (1, opts.rows * opts.cols);
                    double b = opts.bleed ? pub.settings.max_bleed () : 0;
                    bool abut = opts.gap < 0.01;
                    double cellw = abut ? pw : pw + 2 * b;
                    double cellh = abut ? ph : ph + 2 * b;
                    double totw = opts.cols * cellw + (opts.cols - 1) * opts.gap + (abut ? 2 * b : 0);
                    double toth = opts.rows * cellh + (opts.rows - 1) * opts.gap + (abut ? 2 * b : 0);
                    double room = opts.crop_marks ? 2 * (opts.marks_offset + 14) : 0;
                    double sw0 = opts.sheet_w, sh0 = opts.sheet_h;
                    double sc = double.min (1, double.min ((sw0 - room) / totw, (sh0 - room) / toth));
                    double sc_rot = double.min (1, double.min ((sh0 - room) / totw, (sw0 - room) / toth));
                    if (sc_rot > sc + 1e-6) {
                        sw0 = opts.sheet_h;
                        sh0 = opts.sheet_w;
                        sc = sc_rot;
                    }
                    double ox = (sw0 - totw * sc) / 2, oy = (sh0 - toth * sc) / 2;
                    var seq = new Gee.ArrayList<int> ();
                    if (opts.step_repeat) {
                        foreach (int p in pages) for (int k = 0; k < per; k++) seq.add (p);
                    } else {
                        seq.add_all (pages);
                    }
                    for (int i = 0; i < seq.size; i += per) {
                        var sh = new Sheet ();
                        sh.w = sw0;
                        sh.h = sh0;
                        for (int k = 0; k < per && i + k < seq.size; k++) {
                            int r = k / opts.cols, c = k % opts.cols;
                            double x = ox + (c * (cellw + opts.gap) + b) * sc;
                            double y = oy + (r * (cellh + opts.gap) + b) * sc;
                            var slot = new SheetSlot (seq[i + k], x, y, pw * sc, ph * sc, sc);
                            slot.row = r;
                            slot.col = c;
                            slot.rows = opts.rows;
                            slot.cols = opts.cols;
                            slot.abut = abut;
                            sh.slots.add (slot);
                        }
                        sh.label = _("Sheet %d").printf (list.size + 1);
                        list.add (sh);
                    }
                    break;
                case ImposeMode.TILE:
                    double m = 18;
                    double sc = double.max (0.05, opts.tile_scale);
                    double tw = double.max (36, opts.sheet_w - 2 * m), th = double.max (36, opts.sheet_h - 2 * m);
                    double ov = opts.tile_overlap.clamp (0, double.min (tw, th) / 2);
                    foreach (int p in pages) {
                        var cr = content_rect (p);
                        double fw = cr.w * sc, fh = cr.h * sc;
                        int nx = int.max (1, (int) Math.ceil ((fw - ov) / (tw - ov) - 1e-6));
                        int ny = int.max (1, (int) Math.ceil ((fh - ov) / (th - ov) - 1e-6));
                        for (int r = 0; r < ny; r++) {
                            for (int c = 0; c < nx; c++) {
                                var sh = new Sheet ();
                                sh.w = opts.sheet_w;
                                sh.h = opts.sheet_h;
                                double ox = m - c * (tw - ov) - cr.x * sc, oy = m - r * (th - ov) - cr.y * sc;
                                var slot = new SheetSlot (p, ox, oy, pw * sc, ph * sc, sc);
                                slot.row = r;
                                slot.col = c;
                                slot.rows = ny;
                                slot.cols = nx;
                                sh.slots.add (slot);
                                double vx = double.max (m, ox + cr.x * sc), vy = double.max (m, oy + cr.y * sc);
                                double vx2 = double.min (m + tw, ox + (cr.x + cr.w) * sc), vy2 = double.min (m + th, oy + (cr.y + cr.h) * sc);
                                sh.tile = Rect (vx, vy, double.max (0, vx2 - vx), double.max (0, vy2 - vy));
                                sh.label = _("Page %s, tile %d of %d").printf (pub.page_label (p), r * nx + c + 1, nx * ny);
                                list.add (sh);
                            }
                        }
                    }
                    break;
                case ImposeMode.SIGNATURES:
                    list.add_all (signature_sheets (pages, pw, ph));
                    break;
                case ImposeMode.BOOKLET:
                    int n = pages.size;
                    int padded = ((n + 3) / 4) * 4;
                    var seq = new Gee.ArrayList<int> ();
                    for (int i = 0; i < padded; i++) seq.add (i < n ? pages[i] : -1);
                    double sw = pw * 2, shh = ph;
                    double sc = double.min (1, double.min (opts.sheet_w / sw, opts.sheet_h / shh));
                    double ox = (opts.sheet_w - sw * sc) / 2, oy = (opts.sheet_h - shh * sc) / 2;
                    for (int s = 0; s < padded / 4; s++) {
                        int[,] pairs = { { padded - 1 - 2 * s, 2 * s }, { 2 * s + 1, padded - 2 - 2 * s } };
                        for (int side = 0; side < 2; side++) {
                            var sh = new Sheet ();
                            sh.w = opts.sheet_w;
                            sh.h = opts.sheet_h;
                            int l = seq[pairs[side, 0]], r = seq[pairs[side, 1]];
                            if (l >= 0) sh.slots.add (new SheetSlot (l, ox, oy, pw * sc, ph * sc, sc));
                            if (r >= 0) sh.slots.add (new SheetSlot (r, ox + pw * sc, oy, pw * sc, ph * sc, sc));
                            sh.label = side == 0 ? _("Sheet %d Front").printf (s + 1) : _("Sheet %d Back").printf (s + 1);
                            list.add (sh);
                        }
                    }
                    break;
                default:
                    if (opts.spreads) {
                        foreach (var sp in pub.spreads ()) {
                            var inc = new Gee.ArrayList<int> ();
                            foreach (int p in sp.pages) if (pages.contains (p)) inc.add (p);
                            if (inc.size == 0) continue;
                            var sh = new Sheet ();
                            double m = marks_margin ();
                            double b = opts.bleed ? pub.settings.max_bleed () : 0;
                            double tw = 0, th = 0;
                            foreach (int p in inc) {
                                tw += pub.page_w (p);
                                th = double.max (th, pub.page_h (p));
                            }
                            sh.w = tw + 2 * (b + m);
                            sh.h = th + 2 * (b + m);
                            double x = b + m;
                            for (int k = 0; k < inc.size; k++) {
                                sh.slots.add (new SheetSlot (inc[k], x, b + m, pub.page_w (inc[k]), pub.page_h (inc[k]), 1));
                                x += pub.page_w (inc[k]);
                            }
                            list.add (sh);
                        }
                    } else {
                        foreach (int p in pages) {
                            var sh = new Sheet ();
                            double m = marks_margin ();
                            var cr = content_rect (p);
                            sh.w = cr.w + 2 * m;
                            sh.h = cr.h + 2 * m;
                            sh.slots.add (new SheetSlot (p, m - cr.x, m - cr.y, pub.page_w (p), pub.page_h (p), 1));
                            sh.label = pub.page_label (p);
                            list.add (sh);
                        }
                    }
                    break;
            }
            return list;
        }

        public static int[,] signature_scheme (int size, out int cols, out int rows) {
            switch (size) {
                case 4:
                    cols = 2;
                    rows = 1;
                    return { { 4, 1 }, { 2, 3 } };
                case 8:
                    cols = 2;
                    rows = 2;
                    return { { -5, -4, 8, 1 }, { -3, -6, 2, 7 } };
                default:
                    cols = 4;
                    rows = 2;
                    return { { -5, -12, -9, -8, 4, 13, 16, 1 }, { -7, -10, -11, -6, 2, 15, 14, 3 } };
            }
        }

        public Gee.ArrayList<Sheet> signature_sheets (Gee.List<int> pages, double pw, double ph) {
            var list = new Gee.ArrayList<Sheet> ();
            int full = opts.signature == 4 || opts.signature == 8 ? opts.signature : 16;
            int count = (pages.size + full - 1) / full;
            double room = opts.crop_marks ? 2 * (opts.marks_offset + 14) : 0;
            for (int s = 0; s < count; s++) {
                int left = pages.size - s * full;
                int size = full;
                if (left < full) size = left <= 4 ? 4 : (left <= 8 ? 8 : 16);
                int cols, rows;
                var scheme = signature_scheme (size, out cols, out rows);
                double tw = cols * pw, th = rows * ph;
                double sc = double.min (1, double.min ((opts.sheet_w - room) / tw, (opts.sheet_h - room) / th));
                double ox = (opts.sheet_w - tw * sc) / 2, oy = (opts.sheet_h - th * sc) / 2;
                double shift = opts.creep * s;
                for (int side = 0; side < 2; side++) {
                    var sh = new Sheet ();
                    sh.w = opts.sheet_w;
                    sh.h = opts.sheet_h;
                    for (int k = 0; k < cols * rows; k++) {
                        int code = scheme[side, k];
                        bool flip = code < 0;
                        int local = (code < 0 ? -code : code) - 1;
                        int idx = s * full + local;
                        if (idx >= pages.size) continue;
                        int r = k / cols, c = k % cols;
                        bool left_of_spine = c % 2 == 0;
                        double cx = ox + (c * pw + (left_of_spine ? -shift : shift)) * sc;
                        var slot = new SheetSlot (pages[idx], cx, oy + r * ph * sc, pw * sc, ph * sc, sc);
                        slot.row = r;
                        slot.col = c;
                        slot.rows = rows;
                        slot.cols = cols;
                        slot.rotate = flip;
                        sh.slots.add (slot);
                    }
                    sh.label = side == 0 ? _("Signature %d Front").printf (s + 1) : _("Signature %d Back").printf (s + 1);
                    list.add (sh);
                }
            }
            return list;
        }

        public void draw_sheet (Cairo.Context cr, Sheet sh) {
            bool imposed = opts.impose != ImposeMode.NONE;
            if (!opts.transparent || imposed) {
                cr.set_source_rgb (1, 1, 1);
                cr.paint ();
            }
            if (opts.impose == ImposeMode.TILE) {
                draw_tile (cr, sh);
                return;
            }
            if (imposed || (opts.spreads && sh.slots.size > 1)) {
                for (int i = 0; i < sh.slots.size; i++) {
                    var s = sh.slots[i];
                    cr.save ();
                    cr.translate (s.x, s.y);
                    if (s.rotate && opts.impose == ImposeMode.SIGNATURES) {
                        cr.translate (s.w, s.h);
                        cr.rotate (Math.PI);
                    }
                    cr.scale (s.scale, s.scale);
                    var clip = opts.bleed ? pub.bleed_rect (s.page) : pub.page_rect ();
                    if (opts.impose == ImposeMode.SIGNATURES) clip = pub.page_rect (s.page);
                    if (opts.impose == ImposeMode.NUP && s.abut) {
                        double b = opts.bleed ? pub.settings.max_bleed () : 0;
                        double l = s.col == 0 ? b : 0, r = s.col == s.cols - 1 ? b : 0;
                        double t = s.row == 0 ? b : 0, bt = s.row == s.rows - 1 ? b : 0;
                        clip = Rect (-l, -t, pub.settings.width + l + r, pub.settings.height + t + bt);
                    } else if (opts.impose == ImposeMode.NUP) {
                        double b = opts.bleed ? pub.settings.max_bleed () : 0;
                        clip = Rect (-b, -b, pub.settings.width + 2 * b, pub.settings.height + 2 * b);
                    }
                    if (opts.impose == ImposeMode.BOOKLET || (opts.spreads && !imposed)) {
                        double sw = pub.page_w (s.page);
                        clip = pub.page_rect (s.page);
                        if (opts.bleed) {
                            var br = pub.bleed_rect (s.page);
                            bool first = i == 0, last = i == sh.slots.size - 1;
                            double l = first ? -br.x : 0, r = last ? br.w - sw + br.x : 0;
                            clip = Rect (-l, br.y, sw + l + r, br.h);
                        }
                    }
                    cr.rectangle (clip.x, clip.y, clip.w, clip.h);
                    cr.clip ();
                    renderer.draw_page (cr, s.page, true);
                    cr.restore ();
                }
                if (opts.crop_marks) {
                    if (opts.impose == ImposeMode.NUP || opts.impose == ImposeMode.SIGNATURES) draw_grid_marks (cr, sh);
                    else if (sh.slots.size > 0) {
                        var a = sh.slots[0];
                        var z = sh.slots[sh.slots.size - 1];
                        draw_crop_marks (cr, Rect (a.x, a.y, z.x + z.w - a.x, a.h), opts.bleed ? pub.settings.max_bleed () * a.scale : 0);
                    }
                }
                if (opts.reg_marks && sh.slots.size > 0) {
                    var a = sh.slots[0];
                    var z = sh.slots[sh.slots.size - 1];
                    draw_reg_marks (cr, Rect (a.x, a.y, z.x + z.w - a.x, z.y + z.h - a.y));
                }
                return;
            }
            var s = sh.slots[0];
            cr.save ();
            cr.translate (s.x, s.y);
            var clip = content_rect (s.page);
            cr.rectangle (clip.x, clip.y, clip.w, clip.h);
            cr.clip ();
            renderer.draw_page (cr, s.page, !opts.transparent);
            cr.restore ();
            var trim = Rect (s.x, s.y, pub.page_w (s.page), pub.page_h (s.page));
            var bl = pub.bleed_rect (s.page);
            if (opts.crop_marks) draw_crop_marks (cr, trim, double.max (opts.marks_offset, double.max (-bl.x, -bl.y)));
            if (opts.bleed_marks) draw_bleed_marks (cr, Rect (s.x + bl.x, s.y + bl.y, bl.w, bl.h));
            if (opts.reg_marks) draw_reg_marks (cr, trim);
            if (opts.color_bars) draw_color_bars (cr, trim);
            if (opts.page_info) draw_page_info (cr, trim, s.page);
        }

        private void draw_tile (Cairo.Context cr, Sheet sh) {
            if (sh.slots.size == 0) return;
            var s = sh.slots[0];
            var t = sh.tile;
            cr.save ();
            cr.rectangle (t.x, t.y, t.w, t.h);
            cr.clip ();
            cr.translate (s.x, s.y);
            cr.scale (s.scale, s.scale);
            var clip = content_rect (s.page);
            cr.rectangle (clip.x, clip.y, clip.w, clip.h);
            cr.clip ();
            renderer.draw_page (cr, s.page, true);
            cr.restore ();
            double ov = opts.tile_overlap;
            cr.save ();
            registration (cr);
            cr.set_line_width (0.4);
            double len = 10, off = 3;
            double[] xs = { t.x, t.x + t.w };
            double[] ys = { t.y, t.y + t.h };
            foreach (double x in xs) {
                cr.move_to (x, t.y - off);
                cr.line_to (x, t.y - off - len);
                cr.move_to (x, t.y + t.h + off);
                cr.line_to (x, t.y + t.h + off + len);
            }
            foreach (double y in ys) {
                cr.move_to (t.x - off, y);
                cr.line_to (t.x - off - len, y);
                cr.move_to (t.x + t.w + off, y);
                cr.line_to (t.x + t.w + off + len, y);
            }
            cr.stroke ();
            if (ov > 0.5) {
                cr.set_dash ({ 2, 2 }, 0);
                cr.set_line_width (0.25);
                if (s.col > 0) {
                    cr.move_to (t.x + ov, t.y - off);
                    cr.line_to (t.x + ov, t.y - off - len);
                }
                if (s.row > 0) {
                    cr.move_to (t.x - off, t.y + ov);
                    cr.line_to (t.x - off - len, t.y + ov);
                }
                cr.stroke ();
            }
            var layout = new Pango.Layout (TextEngine.context ());
            var fd = new Pango.FontDescription ();
            fd.set_family ("Inter");
            fd.set_absolute_size (6.5 * Pango.SCALE);
            layout.set_font_description (fd);
            layout.set_text ("%s    %s".printf (sh.label, _("Row %d, column %d").printf (s.row + 1, s.col + 1)), -1);
            cr.move_to (t.x, double.max (2, t.y - 16));
            Pango.cairo_show_layout (cr, layout);
            cr.restore ();
        }

        private void registration (Cairo.Context cr) {
            renderer.overprint (false);
            renderer.set_color (cr, "swatch:Registration");
        }

        public void draw_crop_marks (Cairo.Context cr, Rect trim, double offset) {
            cr.save ();
            registration (cr);
            cr.set_line_width (0.25);
            double len = 12;
            double off = double.max (offset, 3);
            double[] xs = { trim.x, trim.x + trim.w };
            double[] ys = { trim.y, trim.y + trim.h };
            foreach (double x in xs) {
                cr.move_to (x, trim.y - off);
                cr.line_to (x, trim.y - off - len);
                cr.move_to (x, trim.y + trim.h + off);
                cr.line_to (x, trim.y + trim.h + off + len);
            }
            foreach (double y in ys) {
                cr.move_to (trim.x - off, y);
                cr.line_to (trim.x - off - len, y);
                cr.move_to (trim.x + trim.w + off, y);
                cr.line_to (trim.x + trim.w + off + len, y);
            }
            cr.stroke ();
            cr.restore ();
        }

        public void draw_grid_marks (Cairo.Context cr, Sheet sh) {
            if (sh.slots.size == 0) return;
            var xs = new Gee.TreeSet<double?> ((a, b) => a < b ? -1 : (a > b ? 1 : 0));
            var ys = new Gee.TreeSet<double?> ((a, b) => a < b ? -1 : (a > b ? 1 : 0));
            double x0 = double.MAX, y0 = double.MAX, x1 = -double.MAX, y1 = -double.MAX;
            foreach (var s in sh.slots) {
                xs.add (Math.round (s.x * 100) / 100);
                xs.add (Math.round ((s.x + s.w) * 100) / 100);
                ys.add (Math.round (s.y * 100) / 100);
                ys.add (Math.round ((s.y + s.h) * 100) / 100);
                x0 = double.min (x0, s.x);
                y0 = double.min (y0, s.y);
                x1 = double.max (x1, s.x + s.w);
                y1 = double.max (y1, s.y + s.h);
            }
            double b = (opts.bleed ? pub.settings.max_bleed () : 0) * sh.slots[0].scale;
            double off = b + 3, len = 10;
            cr.save ();
            registration (cr);
            cr.set_line_width (0.25);
            foreach (var x in xs) {
                cr.move_to (x, y0 - off);
                cr.line_to (x, y0 - off - len);
                cr.move_to (x, y1 + off);
                cr.line_to (x, y1 + off + len);
            }
            foreach (var y in ys) {
                cr.move_to (x0 - off, y);
                cr.line_to (x0 - off - len, y);
                cr.move_to (x1 + off, y);
                cr.line_to (x1 + off + len, y);
            }
            cr.stroke ();
            cr.restore ();
        }

        public void draw_bleed_marks (Cairo.Context cr, Rect bleed) {
            cr.save ();
            registration (cr);
            cr.set_line_width (0.25);
            cr.set_dash ({ 3, 2 }, 0);
            double len = 8, off = 3;
            cr.move_to (bleed.x - off, bleed.y);
            cr.line_to (bleed.x - off - len, bleed.y);
            cr.move_to (bleed.x, bleed.y - off);
            cr.line_to (bleed.x, bleed.y - off - len);
            cr.move_to (bleed.x + bleed.w + off, bleed.y + bleed.h);
            cr.line_to (bleed.x + bleed.w + off + len, bleed.y + bleed.h);
            cr.move_to (bleed.x + bleed.w, bleed.y + bleed.h + off);
            cr.line_to (bleed.x + bleed.w, bleed.y + bleed.h + off + len);
            cr.stroke ();
            cr.restore ();
        }

        private static void target (Cairo.Context cr, double cx, double cy) {
            double r = 5;
            cr.new_sub_path ();
            cr.arc (cx, cy, r, 0, 2 * Math.PI);
            cr.new_sub_path ();
            cr.arc (cx, cy, r * 0.5, 0, 2 * Math.PI);
            cr.move_to (cx - r - 3, cy);
            cr.line_to (cx + r + 3, cy);
            cr.move_to (cx, cy - r - 3);
            cr.line_to (cx, cy + r + 3);
            cr.stroke ();
        }

        public void draw_reg_marks (Cairo.Context cr, Rect trim) {
            cr.save ();
            registration (cr);
            cr.set_line_width (0.3);
            double off = opts.marks_offset + 12;
            target (cr, trim.x + trim.w / 2, trim.y - off);
            target (cr, trim.x + trim.w / 2, trim.y + trim.h + off);
            target (cr, trim.x - off, trim.y + trim.h / 2);
            target (cr, trim.x + trim.w + off, trim.y + trim.h / 2);
            cr.restore ();
        }

        public void draw_color_bars (Cairo.Context cr, Rect trim) {
            double s = 8;
            double y = trim.y - opts.marks_offset - 18;
            double[,] cmyk = { { 1, 0, 0, 0 }, { 0, 1, 0, 0 }, { 0, 0, 1, 0 }, { 0, 0, 0, 1 }, { 1, 1, 0, 0 }, { 0, 1, 1, 0 }, { 1, 0, 1, 0 }, { 0, 0, 0, 0.5 }, { 0, 0, 0, 0.25 } };
            double x = trim.x + 24;
            for (int i = 0; i < 9; i++) {
                renderer.set_color (cr, "cmyk:%s,%s,%s,%s".printf (XmlOut.num (cmyk[i, 0]), XmlOut.num (cmyk[i, 1]), XmlOut.num (cmyk[i, 2]), XmlOut.num (cmyk[i, 3])));
                cr.rectangle (x + i * s, y, s, s);
                cr.fill ();
            }
        }

        public void draw_page_info (Cairo.Context cr, Rect trim, int page) {
            var layout = new Pango.Layout (TextEngine.context ());
            var fd = new Pango.FontDescription ();
            fd.set_family ("Inter");
            fd.set_absolute_size (6 * Pango.SCALE);
            layout.set_font_description (fd);
            string name = pub.meta.title != "" ? pub.meta.title : _("Publication");
            var now = new DateTime.now_local ();
            layout.set_text ("%s    %s %s    %s".printf (name, _("Page"), pub.page_label (page), now.format ("%Y-%m-%d %H:%M")), -1);
            cr.save ();
            registration (cr);
            cr.move_to (trim.x, trim.y + trim.h + opts.marks_offset + 20);
            Pango.cairo_show_layout (cr, layout);
            cr.restore ();
        }

        public int export_pdf (string path) throws Error {
            if (opts.color_mode != ColorMode.RGB || opts.separations) return PrepressExport.export_pdf (pub, opts, path);
            var list = sheets ();
            if (list.size == 0) throw new FormatError.INVALID (_("There are no pages to export."));
            var surf = new Cairo.PdfSurface (path, list[0].w, list[0].h);
            surf.restrict_to_version (Cairo.PdfVersion.VERSION_1_4);
            prepare_links (list);
            if (pub.meta.title != "") surf.set_metadata (Cairo.PdfMetadata.TITLE, pub.meta.title);
            if (pub.meta.author != "") surf.set_metadata (Cairo.PdfMetadata.AUTHOR, pub.meta.author);
            if (pub.meta.subject != "") surf.set_metadata (Cairo.PdfMetadata.SUBJECT, pub.meta.subject);
            if (pub.meta.keywords != "") surf.set_metadata (Cairo.PdfMetadata.KEYWORDS, pub.meta.keywords);
            surf.set_metadata (Cairo.PdfMetadata.CREATOR, "Singularity Publish");
            var cr = new Cairo.Context (surf);
            bool tag = opts.tagged && opts.impose == ImposeMode.NONE;
            renderer.opts.tagged = tag;
            renderer.opts.alt_sink = new Gee.ArrayList<string> ();
            for (int i = 0; i < list.size; i++) {
                var sh = list[i];
                surf.set_size (sh.w, sh.h);
                if (opts.impose == ImposeMode.NONE && sh.slots.size == 1) surf.set_page_label (pub.page_label (sh.slots[0].page));
                draw_sheet (cr, sh);
                emit_destinations (cr, sh);
                cr.show_page ();
            }
            add_outline (surf);
            surf.finish ();
            renderer.opts.tagged = false;
            if (surf.status () != Cairo.Status.SUCCESS) throw new FileError.FAILED (_("Could not write the PDF: %s").printf (surf.status ().to_string ()));
            var o2 = opts;
            if (!tag) {
                o2 = new ExportOptions ();
                o2.tagged = false;
            }
            if (opts.impose == ImposeMode.NONE) PdfFinish.apply (path, pub, o2, list, renderer.opts.alt_sink);
            return list.size;
        }

        public void prepare_links (Gee.ArrayList<Sheet> list) {
            renderer.opts.links = true;
            var map = new Gee.HashMap<int, int> ();
            for (int i = 0; i < list.size; i++) foreach (var s in list[i].slots) if (!map.has_key (s.page)) map[s.page] = i + 1;
            renderer.opts.page_map = map;
        }

        public void emit_destinations (Cairo.Context cr, Sheet sh) {
            foreach (var b in pub.bookmarks) {
                foreach (var s in sh.slots) {
                    if (s.page != b.page) continue;
                    double x = s.x + b.x * s.scale, y = s.y + b.y * s.scale;
                    cr.save ();
                    cr.tag_begin (Cairo.TAG_DEST, "name='%s' x=%s y=%s".printf (Renderer.dest_name (b.name), XmlOut.num (x), XmlOut.num (y)));
                    cr.tag_end (Cairo.TAG_DEST);
                    cr.restore ();
                    break;
                }
            }
        }

        public void add_outline (Cairo.PdfSurface surf) {
            if (renderer.opts.page_map == null) return;
            var marks = new Gee.ArrayList<Bookmark> ();
            foreach (var b in pub.bookmarks) if (renderer.opts.page_map.has_key (b.page)) marks.add (b);
            marks.sort ((a, b) => a.page != b.page ? a.page - b.page : (a.y < b.y ? -1 : (a.y > b.y ? 1 : 0)));
            foreach (var b in marks) surf.add_outline (Cairo.PDF_OUTLINE_ROOT, b.name, "dest='%s'".printf (Renderer.dest_name (b.name)), (Cairo.PdfOutlineFlags) 0);
        }

        public Cairo.ImageSurface render_sheet (Sheet sh) {
            double sc = opts.dpi / 72.0;
            int w = int.max (1, (int) Math.ceil (sh.w * sc)), h = int.max (1, (int) Math.ceil (sh.h * sc));
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surf);
            cr.scale (sc, sc);
            draw_sheet (cr, sh);
            surf.flush ();
            return surf;
        }

        public static Gdk.Pixbuf surface_to_pixbuf (Cairo.ImageSurface surf, bool alpha) {
            int w = surf.get_width (), h = surf.get_height (), ss = surf.get_stride ();
            var pb = new Gdk.Pixbuf (Gdk.Colorspace.RGB, alpha, 8, w, h);
            unowned uint8[] src = surf.get_data ();
            unowned uint8[] dst = pb.get_pixels_with_length ();
            int ds = pb.rowstride, nc = pb.n_channels;
            bool le = GLib.ByteOrder.HOST == GLib.ByteOrder.LITTLE_ENDIAN;
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int si = y * ss + x * 4, di = y * ds + x * nc;
                    uint b = src[si + (le ? 0 : 3)], g = src[si + (le ? 1 : 2)], r = src[si + (le ? 2 : 1)], a = src[si + (le ? 3 : 0)];
                    if (a > 0 && a < 255) {
                        r = uint.min (255, r * 255 / a);
                        g = uint.min (255, g * 255 / a);
                        b = uint.min (255, b * 255 / a);
                    }
                    if (!alpha && a < 255) {
                        r = (r * a + 255 * (255 - a)) / 255;
                        g = (g * a + 255 * (255 - a)) / 255;
                        b = (b * a + 255 * (255 - a)) / 255;
                    }
                    dst[di] = (uint8) r;
                    dst[di + 1] = (uint8) g;
                    dst[di + 2] = (uint8) b;
                    if (alpha) dst[di + 3] = (uint8) a;
                }
            }
            return pb;
        }

        public Gee.ArrayList<string> export_images (string dir, string base_name, string format) throws Error {
            if (format != "png" && format != "jpeg") return ImageExport.export (this, dir, base_name, format);
            var out_files = new Gee.ArrayList<string> ();
            var list = sheets ();
            for (int i = 0; i < list.size; i++) {
                var sh = list[i];
                var surf = render_sheet (sh);
                string label = sh.slots.size == 1 && opts.impose == ImposeMode.NONE ? pub.page_label (sh.slots[0].page) : (i + 1).to_string ();
                string name = list.size == 1 ? "%s.%s".printf (base_name, format == "jpeg" ? "jpg" : "png") : "%s-%s.%s".printf (base_name, label, format == "jpeg" ? "jpg" : "png");
                string p = Path.build_filename (dir, name);
                if (format == "jpeg") {
                    var pb = surface_to_pixbuf (surf, false);
                    pb.save (p, "jpeg", "quality", opts.jpeg_quality.to_string ());
                } else {
                    var st = surf.write_to_png (p);
                    if (st != Cairo.Status.SUCCESS) throw new FileError.FAILED (_("Could not write \"%s\".").printf (name));
                }
                out_files.add (p);
            }
            return out_files;
        }

        public Cairo.ImageSurface thumbnail (int page_index, int max_px) {
            double sc = double.min (max_px / pub.settings.width, max_px / pub.settings.height);
            int w = int.max (1, (int) (pub.settings.width * sc)), h = int.max (1, (int) (pub.settings.height * sc));
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surf);
            cr.scale (sc, sc);
            renderer.draw_page (cr, page_index, true);
            surf.flush ();
            return surf;
        }
    }
}
